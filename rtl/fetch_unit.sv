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
  
  // Feedback from IB Stage (acceptance)
  input  logic [1:0]   accept_count   // 0, 1, or 2 instructions accepted
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
  logic         pending_hi_fetch;
  logic         pending_lo_fetch;
  logic         pending_lo_prefetch;

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
  
  typedef enum logic [1:0] {REQ_NONE, REQ_HI, REQ_LO} req_dest_e;

  state_e state, state_next;
  
  logic [31:0] req_addr;      // Next address to request
  logic        req_valid;     // Request output valid
  req_dest_e   req_dest;      // Destination for the request response
  logic        req_is_prefetch;

  // Registered request output stage (+1 cycle cut on mem request path)
  logic        mem_req_q;
  logic [31:0] mem_addr_q;
  req_dest_e   mem_req_dest_q;
  logic        mem_req_prefetch_q;

  // Explicit single-inflight tracking for request/ack bookkeeping
  logic        inflight_valid_q;
  req_dest_e   inflight_dest_q;
  logic        inflight_prefetch_q;
  
  // PC Update Logic (Combinational Next PC)
  logic [31:0] pc_after_accept;
  logic [4:0]  accept_len;
  logic [5:0]  pc_offset_after_accept;
  logic [1:0]  block_step_after_accept;
  logic        shift_one_predicted;
  logic        need_hi_fetch;
  logic        need_lo_fetch;
  logic        prefetch_arm_d;
  logic        prefetch_arm_q;
  logic        prefetch_next;
  
  always_comb begin
    accept_len = 5'd0;
    if (accept_count >= 1) accept_len += len_0;
    if (accept_count == 2) accept_len += len_1;

    // Advance based on instructions actually accepted into the IB stage.
    pc_after_accept = current_pc + {27'h0, accept_len};
    pc_offset_after_accept = {2'b00, current_pc[3:0]} + {1'b0, accept_len};
    block_step_after_accept = 2'd0;
    if (pc_offset_after_accept >= 6'd32) begin
      block_step_after_accept = 2'd2;
    end else if (pc_offset_after_accept >= 6'd16) begin
      block_step_after_accept = 2'd1;
    end
    shift_one_predicted = (block_step_after_accept == 2'd1);

    need_hi_fetch = !buf_hi_valid && !pending_hi_fetch;
    need_lo_fetch = buf_hi_valid && !buf_lo_valid && !pending_lo_fetch;
    // With a 16-byte maximum two-instruction window, we only prefetch one block ahead.
    prefetch_arm_d = buf_hi_valid && buf_lo_valid && shift_one_predicted &&
                     !pending_lo_fetch;
    prefetch_next = prefetch_arm_q && !pending_lo_fetch;
  end

  // Request scheduling: prefer filling HI, then LO, then speculative next block.
  always_comb begin
    req_valid = 1'b0;
    req_addr = 32'h0;
    req_dest = REQ_NONE;
    req_is_prefetch = 1'b0;
    state_next = state;

    if (need_hi_fetch) begin
      req_valid = 1'b1;
      req_addr = buf_base_addr;
      req_dest = REQ_HI;
      state_next = FETCH_HI;
    end else if (need_lo_fetch) begin
      req_valid = 1'b1;
      req_addr = buf_base_addr + 32'h10;
      req_dest = REQ_LO;
      state_next = FETCH_LO;
    end else if (prefetch_next) begin
      req_valid = 1'b1;
      req_addr = buf_base_addr + 32'h20;
      req_dest = REQ_LO;
      req_is_prefetch = 1'b1;
      state_next = FETCH_LO;
    end else begin
      if (buf_hi_valid && buf_lo_valid) state_next = STEADY;
      else if (buf_hi_valid) state_next = FETCH_LO_WAIT;
      else state_next = IDLE;
    end
  end
  
  // ============================================================================
  // Decode Logic (Extract from Buffer)
  // ============================================================================
  
  logic [3:0] pc_offset;
  assign pc_offset = current_pc[3:0]; // Offset within buf_hi
  
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
      
      if (buf_hi_valid && (current_pc[31:4] == buf_base_addr[31:4])) begin
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
      
      if (!branch_taken && inst0_fits) begin
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

  // Isolate PC/base pointer updates from buffer/memory bookkeeping to reduce
  // cross-coupled control depth in the fetch state cone.
  always_ff @(posedge clk) begin
    if (rst) begin
      current_pc <= 32'h0;
      buf_base_addr <= 32'h0;
    end else if (branch_taken) begin
      current_pc <= branch_target;
      buf_base_addr <= branch_target & 32'hFFFF_FFF0;
    end else if (accept_count != 2'd0) begin
      current_pc <= pc_after_accept;
      if (block_step_after_accept == 2'd1) begin
        buf_base_addr <= buf_base_addr + 32'd16;
      end else if (block_step_after_accept == 2'd2) begin
        buf_base_addr <= buf_base_addr + 32'd32;
      end
    end
  end
  
  always_ff @(posedge clk) begin
    logic [127:0] n_buf_hi;
    logic [127:0] n_buf_lo;
    logic        n_hi_valid;
    logic        n_lo_valid;
    logic        n_pending_hi;
    logic        n_pending_lo;
    logic        n_pending_lo_prefetch;
    logic        n_prefetch_arm;
    logic        n_mem_req;
    logic [31:0] n_mem_addr;
    req_dest_e   n_mem_req_dest;
    logic        n_mem_req_prefetch;
    logic        n_inflight_valid;
    req_dest_e   n_inflight_dest;
    logic        n_inflight_prefetch;

    if (rst) begin
        state <= IDLE;
        buf_hi_valid <= 1'b0;
        buf_lo_valid <= 1'b0;
        pending_hi_fetch <= 1'b0;
        pending_lo_fetch <= 1'b0;
        pending_lo_prefetch <= 1'b0;
        prefetch_arm_q <= 1'b0;
        mem_req_q <= 1'b0;
        mem_addr_q <= 32'h0;
        mem_req_dest_q <= REQ_NONE;
        mem_req_prefetch_q <= 1'b0;
        inflight_valid_q <= 1'b0;
        inflight_dest_q <= REQ_NONE;
        inflight_prefetch_q <= 1'b0;
        
    end else if (branch_taken) begin
        // Flush and Branch
        state <= FETCH_HI;
        buf_hi_valid <= 1'b0;
        buf_lo_valid <= 1'b0;
        pending_hi_fetch <= 1'b0;
        pending_lo_fetch <= 1'b0;
        pending_lo_prefetch <= 1'b0;
        prefetch_arm_q <= 1'b0;
        mem_req_q <= 1'b0;
        mem_addr_q <= 32'h0;
        mem_req_dest_q <= REQ_NONE;
        mem_req_prefetch_q <= 1'b0;
        inflight_valid_q <= 1'b0;
        inflight_dest_q <= REQ_NONE;
        inflight_prefetch_q <= 1'b0;
        
    end else begin
        // Defaults
        n_buf_hi   = buf_hi;
        n_buf_lo   = buf_lo;
        n_hi_valid = buf_hi_valid;
        n_lo_valid = buf_lo_valid;
        n_pending_hi = pending_hi_fetch;
        n_pending_lo = pending_lo_fetch;
        n_pending_lo_prefetch = pending_lo_prefetch;
        n_prefetch_arm = prefetch_arm_d;
        n_mem_req = 1'b0;
        n_mem_addr = mem_addr_q;
        n_mem_req_dest = mem_req_dest_q;
        n_mem_req_prefetch = mem_req_prefetch_q;
        n_inflight_valid = inflight_valid_q;
        n_inflight_dest = inflight_dest_q;
        n_inflight_prefetch = inflight_prefetch_q;

        // Consume memory response from the single inflight request.
        if (mem_ack && inflight_valid_q) begin
            case (inflight_dest_q)
                REQ_HI: begin
                    n_buf_hi = mem_rdata;
                    n_hi_valid = 1'b1;
                    n_pending_hi = 1'b0;
                end
                REQ_LO: begin
                    n_buf_lo = mem_rdata;
                    n_lo_valid = 1'b1;
                    n_pending_lo = 1'b0;
                    n_pending_lo_prefetch = 1'b0;
                end
                default: ;
            endcase
            n_inflight_valid = 1'b0;
            n_inflight_dest = REQ_NONE;
            n_inflight_prefetch = 1'b0;
        end

        // Drive memory request stage from scheduler outputs (registered pulse).
        // Keep this before shift bookkeeping so LO->HI reclassification remains correct.
        if (req_valid && !n_inflight_valid) begin
            n_mem_req = 1'b1;
            n_mem_addr = req_addr;
            n_mem_req_dest = req_dest;
            n_mem_req_prefetch = req_is_prefetch;
            n_inflight_valid = 1'b1;
            n_inflight_dest = req_dest;
            n_inflight_prefetch = req_is_prefetch;

            if (req_dest == REQ_HI) begin
                n_pending_hi = 1'b1;
            end else if (req_dest == REQ_LO) begin
                n_pending_lo = 1'b1;
                n_pending_lo_prefetch = req_is_prefetch;
            end
        end

        if (accept_count != 2'd0) begin
            // Buffer shift based on the post-accept PC (max two-instruction window is 16 bytes)
            if (block_step_after_accept != 2'd0) begin
                if (block_step_after_accept == 2'd1) begin
                    n_buf_hi = n_buf_lo;
                    n_hi_valid = n_lo_valid;
                    n_lo_valid = 1'b0;
                    
                    // If we had a pending LO fetch, it now corresponds to the new HI block.
                    if (n_pending_lo && !n_pending_lo_prefetch) begin
                        n_pending_hi = 1'b1;
                        n_pending_lo = 1'b0;
                        n_pending_lo_prefetch = 1'b0;
                        if (n_inflight_valid && (n_inflight_dest == REQ_LO) &&
                            !n_inflight_prefetch) begin
                            n_inflight_dest = REQ_HI;
                        end
                    end
                end else begin
                    n_hi_valid = 1'b0;
                    n_lo_valid = 1'b0;
                    
                    // Skipped blocks; drop any pending fetches to avoid stale fills.
                    n_pending_hi = 1'b0;
                    n_pending_lo = 1'b0;
                    n_pending_lo_prefetch = 1'b0;
                    n_prefetch_arm = 1'b0;
                    n_mem_req = 1'b0;
                    n_mem_req_dest = REQ_NONE;
                    n_mem_req_prefetch = 1'b0;
                    n_inflight_valid = 1'b0;
                    n_inflight_dest = REQ_NONE;
                    n_inflight_prefetch = 1'b0;
                end
            end
        end

        // Commit Updates
        buf_hi <= n_buf_hi;
        buf_lo <= n_buf_lo;
        buf_hi_valid <= n_hi_valid;
        buf_lo_valid <= n_lo_valid;
        prefetch_arm_q <= n_prefetch_arm;
        pending_hi_fetch <= n_pending_hi;
        pending_lo_fetch <= n_pending_lo;
        pending_lo_prefetch <= n_pending_lo_prefetch;
        mem_req_q <= n_mem_req;
        mem_addr_q <= n_mem_addr;
        mem_req_dest_q <= n_mem_req_dest;
        mem_req_prefetch_q <= n_mem_req_prefetch;
        inflight_valid_q <= n_inflight_valid;
        inflight_dest_q <= n_inflight_dest;
        inflight_prefetch_q <= n_inflight_prefetch;
        state <= state_next;
    end
  end

  // Assign memory request outputs
  assign mem_req = mem_req_q && !branch_taken && !rst;
  assign mem_addr = mem_addr_q;

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
