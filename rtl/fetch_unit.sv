//
// fetch_unit.sv
// NeoCore 16x32 CPU - Instruction Fetch Unit (Aligned / Buffered)
//
// Fetches 128-bit aligned blocks from unified memory.
// Uses a 32-byte (256-bit) internal buffer (Current + Next blocks).
//
// Operation:
//   - 'buf_hi' holds the 16-byte block containing 'current_pc'.
//   - 'buf_lo' holds the next 16-byte block (prefetch).
//   - Decoder extracts instructions freely across the buf_hi/buf_lo boundary.
//   - When 'current_pc' advances into 'buf_lo' territory:
//       buf_hi <- buf_lo
//       buf_lo <- INVALID (trigger fetch)
//

module fetch_unit
  import neocore_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  
  // PC control
  input  logic        branch_taken,
  input  logic [31:0] branch_target,
  input  logic        stall,        // Stall fetch (from hazard detection)
  
  // Unified memory interface (128-bit aligned fetch)
  output logic [31:0] mem_addr,     // 32-bit byte address (bottom 4 bits ignored by mem)
  output logic        mem_req,
  input  logic [127:0] mem_rdata,   // 16 bytes of instruction data (Big Endian)
  input  logic        mem_ack,
  
  // Output to decode
  output logic [71:0]  inst_data_0,  // First instruction (up to 9 bytes)
  output logic [3:0]   inst_len_0,   // First instruction length
  output logic [31:0]  pc_0,         // PC of first instruction
  output logic         valid_0,      // First instruction valid
  
  output logic [71:0]  inst_data_1,  // Second instruction (for dual-issue)
  output logic [3:0]   inst_len_1,
  output logic [31:0]  pc_1,
  output logic         valid_1,
  
  // Feedback from Issue Stage
  input  logic [1:0]   consumed_count, // 0, 1, or 2 instructions consumed
  input  logic [3:0]   id_inst_len_0,
  input  logic [3:0]   id_inst_len_1,
  input  logic [31:0]  id_pc,
  input  logic         id_valid
);

  // ============================================================================
  // Buffer State
  // ============================================================================
  
  logic [127:0] buf_hi;       // Current block (aligned PC base)
  logic [127:0] buf_lo;       // Next block (aligned PC base + 16)
  logic         buf_hi_valid;
  logic         buf_lo_valid;
  logic [31:0]  buf_base_addr;// Base address of buf_hi
  logic [31:0]  current_pc;   // Current instruction pointer

  logic [255:0] buffer;
  assign buffer = {buf_hi, buf_lo}; // Big Endian: hi is lower address (earlier bytes)

  // ============================================================================
  // Fetch Control State Machine
  // ============================================================================
  
  typedef enum logic [2:0] {
    IDLE,       // Init / Reset
    FETCH_HI,   // Fetching the block for current_pc (buf_hi empty)
    FETCH_LO_WAIT, // Wait state to issue LO request
    FETCH_LO,   // Fetching the next block (buf_hi valid, buf_lo empty)
    STEADY      // Both buffers valid
  } state_e;
  
  state_e state, state_next;
  
  logic [31:0] req_addr;      // Next address to request
  logic        req_valid;     // Request output valid
  
  // PC Update Logic (Combinational Next PC)
  logic [31:0] next_pc_comb;
  logic [4:0]  total_consumed_len;
  
  // Calc next PC based on *predicted* consumption this cycle
  // (We use feedback 'consumed_count' for state update, but for *this* cycle's logic
  //  we need to know what we are providing).
  // Actually, standard CPU pipeline: Fetch presents valid data. Decode consumes it.
  // Next cycle, Fetch updates PC based on consumption.
  // So 'current_pc' is stable during the cycle. Update happens at clock edge.
  
  // Logic to handle "Shift" (Moving from Hi to Lo block)
  // Shift condition: The new PC (after consumption) is >= buf_base_addr + 16
  logic [31:0] pc_after_consume;
  logic [31:0] correct_pc_from_issue;
  
  logic shift_needed;
  logic branch_flush;
  logic flush_speculation;

  always_comb begin
      // Calculate where PC will be next cycle if we consume what issue says
      logic [4:0] cons_len;
      cons_len = 0;
      if (consumed_count >= 1) cons_len += id_inst_len_0;
      if (consumed_count == 2) cons_len += id_inst_len_1;
      
      pc_after_consume = id_pc + {27'h0, cons_len};
      correct_pc_from_issue = pc_after_consume; // Alias for clarity
  end

  // Detect PC correction (Branch or mis-prediction/wait)
  // If id_valid is high, Issue stage is telling us the TRUE state.
  // If (current_pc != id_pc), we are out of sync (pipeline flush/stall catchup).
  // But normally fetch is ahead.
  // Wait, the interface here: "consumed_count" tells us how many instructions
  // from THIS cycle's 'inst_data' were accepted.
  // So 'current_pc' should advance by 'consumed_len'.
  
  // Let's implement the standard advance logic:
  // If !stall and we provided valid instructions:
  //   next_pc = current_pc + len(inst0) [+ len(inst1)]
  // We don't have 'consumed_count' for the CURRENT cycle's output yet.
  // 'consumed_count' is from the PREVIOUS cycle's decode, effectively?
  // No, usually it's combinational feedback or from latch.
  // Assuming 'consumed_count' is feedback from the Decode stage consuming valid_0/valid_1.
  // But normally that's a registered "consumed" signal from the previous cycle?
  // "Feedback from Issue Stage": likely combinational or registered.
  // Let's assume standard behavior:
  // We present PC. Decode sees PC. Decode says "I took 2".
  // Next cycle, PC += length(2).
  
  logic [31:0] pc_next;
  logic        perform_shift;
  logic [31:0] next_req_addr;
  
  always_comb begin
    state_next = state;
    req_valid = 1'b0;
    req_addr = 32'h0;
    perform_shift = 1'b0;
    next_req_addr = 32'h0;

    // Default req address depends on state
    case (state)
      IDLE: begin
         if (!stall) state_next = FETCH_HI;
      end
      
      FETCH_HI: begin
         // We are fetching 'buf_base_addr'
         req_valid = 1'b1;
         req_addr = buf_base_addr;
         
         if (mem_ack) begin
            // Got HI. Next need LO.
            state_next = FETCH_LO_WAIT;
         end
      end
      
      FETCH_LO_WAIT: begin
         // Issue LO request, ignore Ack (stale/latency)
         req_valid = 1'b1;
         req_addr = buf_base_addr + 32'h10;
         state_next = FETCH_LO;
      end
      
      FETCH_LO: begin
         // We have HI. Fetching LO (buf_base_addr + 16)
         req_valid = 1'b1;
         req_addr = buf_base_addr + 32'h10;
         
         if (mem_ack) begin
            state_next = STEADY;
         end
      end
      
      STEADY: begin
         // Buffer Full. Do nothing unless we consume/shift.
         // If we shift, we invalidate LO (it becomes HI) and go to FETCH_LO_WAIT
         // We can pipeline this: if shifting, immediately request Next.
      end
      
      default: state_next = IDLE;
    endcase
  end
  
  // ============================================================================
  // Decode Logic (Extract from Buffer)
  // ============================================================================
  
  logic [3:0] pc_offset;
  assign pc_offset = current_pc[3:0]; // Offset within buf_hi
  
  // We need to verify if 'current_pc' is within [buf_base, buf_base+31]
  // But simpler: We trust 'current_pc' is in range because we shift when it exits.
  // EXCEPT: Buffer might be empty/invalid initially.
  
  logic buffer_has_data;
  // We have enough data if:
  // 1. buf_hi_valid is TRUE.
  // 2. We are not asking for data beyond what's valid.
  //    - If buf_lo_valid is FALSE, we can only serve if instruction fits in buf_hi.
  //    - (Strictly: buffer_hi captures [0..15]. If pc_offset=14, we need 14..22?
  //      That crosses to LO. If LO invalid, we can't serve).
  
  logic [255:0] buffer_shifted;
  // Logically: buffer >> (pc_offset * 8)
  // But specific byte extraction is cheaper.
  
  // Helper to extract 9 bytes at offset
  // Helper to extract 9 bytes at offset
  function automatic logic [71:0] extract_9_bytes(input logic [255:0] buf_in, input logic [4:0] off);
      // Byte 0 of buffer is at [255:248]
      // Byte 'off' is at [255 - off*8 ... ]
      // We want 9 bytes (72 bits).
      int start_idx;
      start_idx = 255 - (int'(off) * 8);
      return buf_in[start_idx -: 72];
  endfunction

  logic [71:0] raw_inst_0, raw_inst_1;
  logic [3:0]  len_0, len_1;
  logic [3:0]  inst0_off;
  logic [4:0]  inst1_off;

  always_comb begin
      inst0_off = pc_offset;
      raw_inst_0 = extract_9_bytes(buffer, {1'b0, inst0_off});
      
      // Calculate length of inst 0
      len_0 = get_inst_length(raw_inst_0[63:56], raw_inst_0[71:64]);
      
      // Inst 1
      inst1_off = {1'b0, inst0_off} + {1'b0, len_0};
      
      raw_inst_1 = extract_9_bytes(buffer, inst1_off);
      len_1 = get_inst_length(raw_inst_1[63:56], raw_inst_1[71:64]);
  end

  // Validity Checks
  logic inst0_fits;
  logic inst1_fits;
  logic inst0_len_knowable;
  logic inst1_len_knowable;
  
  always_comb begin
      inst0_fits = 0;
      inst1_fits = 0;
      inst0_len_knowable = 0;
      inst1_len_knowable = 0;
      
      if (buf_hi_valid && (current_pc[31:4] == buf_base_addr[31:4]) && !feedback_wait) begin
          // Inst 0 Length knowability: Need Byte 0 (Spec) and Byte 1 (Opcode).
          // Byte 1 of inst0 is at (pc_offset + 1). 
          if (pc_offset < 15) begin
             inst0_len_knowable = 1; // Both bytes in HI block (which is valid here)
          end else if (pc_offset == 15) begin
             inst0_len_knowable = buf_lo_valid; // Byte 0 in HI, Byte 1 in LO
          end else begin
             // pc_offset >= 16: Should not happen if buf_hi points to current_pc
             // But if we are in buf_lo territory, we would have shifted.
             inst0_len_knowable = 0;
          end

          if (inst0_len_knowable) begin
              // Check if entire instruction fits in current valid blocks
              if (pc_offset + len_0 <= 16) begin
                  inst0_fits = 1; // Entirely in HI
              end else if (pc_offset + len_0 <= 32 && buf_lo_valid) begin
                  inst0_fits = 1; // Straddles HI/LO, and LO is valid
              end
          end
          
          // Inst 1
          if (inst0_fits && len_0 > 0) begin
             logic [4:0] start_off_1;
             start_off_1 = {1'b0, pc_offset} + len_0;
             
             // Can we know len_1? Need bytes start_off_1 and start_off_1 + 1
             if (start_off_1 < 15) begin
                inst1_len_knowable = 1; // Both in HI
             end else if (start_off_1 == 15) begin
                inst1_len_knowable = buf_lo_valid; // Straddles
             end else if (start_off_1 < 31) begin
                inst1_len_knowable = buf_lo_valid; // Both in LO
             end
             
             if (inst1_len_knowable) begin
                logic [5:0] end_off_1;
                end_off_1 = {1'b0, start_off_1} + len_1;
                if (end_off_1 <= 16) begin
                    inst1_fits = 1;
                end else if (end_off_1 <= 32 && buf_lo_valid) begin
                    inst1_fits = 1;
                end
             end
          end
      end
  end

  // Output Assignment
  always_comb begin
      // Defaults
      valid_0 = 0;
      inst_data_0 = 72'h0;
      inst_len_0 = len_0;
      pc_0 = current_pc;
      
      valid_1 = 0;
      inst_data_1 = 72'h0;
      inst_len_1 = len_1;
      pc_1 = current_pc + {28'h0, len_0};
      
      if (!branch_taken && !stall && inst0_fits) begin
          valid_0 = 1;
          inst_data_0 = raw_inst_0;
          
          if (inst1_fits) begin
              valid_1 = 1;
              inst_data_1 = raw_inst_1;
          end
      end
  end

  // ============================================================================
  // Sequential Logic
  // ============================================================================
  
  logic feedback_wait;

  always_ff @(posedge clk) begin
    logic [4:0] adv_len;
    logic [31:0] pc_new;
    logic [31:0] offset_check;
    logic       n_hi_valid;
    logic       n_lo_valid;
    logic [127:0] n_buf_hi;
    logic [127:0] n_buf_lo;
    logic [31:0]  n_buf_base;
    logic [31:0]  next_block_addr;

    if (rst) begin
        state <= IDLE;
        current_pc <= 32'h0; // Reset vector 0
        buf_base_addr <= 32'h0;
        buf_hi_valid <= 0;
        buf_lo_valid <= 0;
        feedback_wait <= 0;
        
    end else if (branch_taken) begin
        // Flush and Branch
        state <= FETCH_HI;
        current_pc <= branch_target;
        buf_base_addr <= branch_target & 32'hFFFF_FFF0; // Align 16
        buf_hi_valid <= 0;
        buf_lo_valid <= 0;
        feedback_wait <= 0;
        
    end else if (!stall) begin
        // Update Feedback Wait
        if (valid_0) feedback_wait <= 1;
        else feedback_wait <= 0;

        // 1. Update Buffer Content (Memory Responses)
        if (state == FETCH_HI && mem_ack) begin
            buf_hi <= mem_rdata;
            buf_hi_valid <= 1;
        end
        
        if (state == FETCH_LO && mem_ack) begin
            buf_lo <= mem_rdata;
            buf_lo_valid <= 1;
        end
        
        // 2. Update PC (Consumption)
        adv_len = 0;
        
        // Use lengths from ID stage (which are being consumed)
        if (consumed_count >= 1) adv_len += id_inst_len_0;
        if (consumed_count == 2) adv_len += id_inst_len_1;

        
        pc_new = current_pc + {27'h0, adv_len};
         
        current_pc <= pc_new;

        // 3. Handle Buffer Shift / Refill
        // 3. Handle Buffer Shift / Refill
        // Calculate the 16-byte aligned block address for the NEW PC
        // We use 32'hFFFF_FFF0 to align to 16 bytes
        next_block_addr = pc_new & 32'hFFFF_FFF0; 

        // Parallel update logic
        n_hi_valid = buf_hi_valid;
        n_lo_valid = buf_lo_valid;
        n_buf_hi   = buf_hi;
        n_buf_lo   = buf_lo;
        n_buf_base = buf_base_addr;
        
        // Update with memory responses (if any) before processing shift
        if (state == FETCH_HI && mem_ack) begin
            n_buf_hi = mem_rdata;
            n_hi_valid = 1;
        end
        if (state == FETCH_LO && mem_ack) begin
            n_buf_lo = mem_rdata;
            n_lo_valid = 1;
        end
        
        // Now determine if we need to shift or jump
        if (next_block_addr != buf_base_addr) begin
            if (next_block_addr == buf_base_addr + 32'd16) begin
                // Standard Shift (Next sequential block)
                n_buf_base = next_block_addr;
                
                // Hi becomes old Lo (if valid)
                n_buf_hi = n_buf_lo;
                n_hi_valid = n_lo_valid;
                
                // Lo becomes invalid (need fetch)
                n_lo_valid = 0;
            end else begin
                // Jumped far (branch, or >16 byte advance, or backwards)
                // Invalidate both to be safe and force re-fetch
                n_buf_base = next_block_addr;
                n_hi_valid = 0;
                n_lo_valid = 0;
            end
        end

        // Commit Updates
        buf_hi <= n_buf_hi;
        buf_lo <= n_buf_lo;
        buf_hi_valid <= n_hi_valid;
        buf_lo_valid <= n_lo_valid;
        buf_base_addr <= n_buf_base;
        
        // 4. Update Main State Machine
        // Override state based on buffer status
        if (n_hi_valid && n_lo_valid) begin
           state <= STEADY;
        end else if (n_hi_valid && !n_lo_valid) begin
           // If we just gathered HI, or shifted from STEADY, we need to fetch LO.
           // If shifting from STEADY, we need wait cycle.
           // If coming from FSM (FETCH_HI->WAIT or WAIT->LO), trust state_next.
           if (state == STEADY) begin
               state <= FETCH_LO_WAIT;
           end else begin
               state <= state_next;
           end
        end else if (!n_hi_valid) begin
           state <= FETCH_HI;
        end else begin
           state <= state_next;
        end

    end
  end

  // Assign memory request outputs
  assign mem_req = req_valid && !stall && !branch_taken && !rst;
  assign mem_addr = req_addr;

  // ============================================================================
  // Debug / Testbench Signals
  // ============================================================================
  logic [7:0] spec_0, op_0;
  logic [7:0] spec_1, op_1;
  logic [7:0] current_block [16];
  
  assign spec_0 = inst_data_0[71:64];
  assign op_0   = inst_data_0[63:56];
  assign spec_1 = inst_data_1[71:64];
  assign op_1   = inst_data_1[63:56];
  
  genvar i;
  generate
    for (i=0; i<16; i++) begin : gen_debug_block
      assign current_block[i] = buf_hi[ 127 - (i*8) -: 8 ]; // Big Endian: Byte 0 is [127:120]
    end
  endgenerate

endmodule : fetch_unit