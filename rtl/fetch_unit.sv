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

  // Registered output stage (IF2)
  logic [71:0] out_inst_data_0;
  logic [3:0]  out_len_0;
  logic [31:0] out_pc_0;
  logic        out_valid_0;

  logic [71:0] out_inst_data_1;
  logic [3:0]  out_len_1;
  logic [31:0] out_pc_1;
  logic        out_valid_1;

  logic        out_hold;
  localparam logic FETCH_DUAL_ENABLE = 1'b1;

  // ============================================================================
  // Buffer State
  // ============================================================================
  
  logic [127:0] buf_hi;       // Current block (aligned PC base)
  logic [127:0] buf_lo;       // Next block (aligned PC base + 16)
  logic [127:0] buf_pf;       // Prefetch block (aligned PC base + 32)
  logic [127:0] buf_p2;       // Prefetch block (aligned PC base + 48)
  logic         buf_hi_valid;
  logic         buf_lo_valid;
  logic         buf_pf_valid;
  logic         buf_p2_valid;
  logic [31:0]  buf_base_addr;// Base address of buf_hi
  logic [31:0]  current_pc;   // Current instruction pointer
  logic         pending_hi_fetch;
  logic         pending_lo_fetch;
  logic         pending_pf_fetch;
  logic         pending_p2_fetch;

  // ============================================================================
  // Fetch Control State Machine
  // ============================================================================
  
  typedef enum logic [2:0] {
    IDLE,       // Init / Reset
    FETCH_HI,   // Fetching the block for current_pc (buf_hi empty)
    FETCH_LO_WAIT, // Wait state to issue LO request
    FETCH_LO,   // Fetching the next block (buf_hi valid, buf_lo empty)
    FETCH_PF,   // Prefetching the block after buf_lo
    STEADY      // Both buffers valid
  } state_e;
  
  typedef enum logic [2:0] {REQ_NONE, REQ_HI, REQ_LO, REQ_PF, REQ_P2} req_dest_e;

  state_e state, state_next;
  
  logic [31:0] req_addr;      // Next address to request
  logic        req_valid;     // Request output valid
  req_dest_e   req_dest;      // Destination for the request response

  // Registered request output stage (+1 cycle cut on mem request path)
  logic        mem_req_q;
  logic        branch_req_q;
  logic [31:0] mem_addr_q;

  // Explicit in-flight request queue (2 deep) for request/ack bookkeeping
  logic [1:0]  req_q_count;
  req_dest_e   req_q0;
  req_dest_e   req_q1;
  
  // PC Update Logic (Combinational Next PC)
  logic [31:0] pc_after_accept;
  logic [4:0]  accept_len;
  logic [5:0]  pc_offset_after_accept;
  logic [1:0]  block_step_after_accept;
  logic        need_hi_fetch;
  logic        need_lo_fetch;
  logic        need_pf_fetch;
  logic        need_p2_fetch;
  logic [31:0] decode_pc;
  logic [31:0] decode_base_addr;
  logic [127:0] decode_buf_hi;
  logic [127:0] decode_buf_lo;
  logic        decode_hi_valid;
  logic        decode_lo_valid;
  logic [127:0] hi_data_eff;
  logic [127:0] lo_data_eff;
  logic [127:0] pf_data_eff;
  logic [127:0] p2_data_eff;
  logic        hi_valid_eff;
  logic        lo_valid_eff;
  logic        pf_valid_eff;
  logic        p2_valid_eff;

  logic [255:0] buffer;
  assign buffer = {decode_buf_hi, decode_buf_lo}; // Big Endian: hi is lower address (earlier bytes)
  
  always_comb begin
    accept_len = 5'd0;
    if (accept_count >= 1) accept_len += out_len_0;
    if (accept_count == 2) accept_len += out_len_1;

    // Advance based on instructions actually accepted into the IB stage.
    pc_after_accept = current_pc + {27'h0, accept_len};
    pc_offset_after_accept = {2'b00, current_pc[3:0]} + {1'b0, accept_len};
    block_step_after_accept = 2'd0;
    if (pc_offset_after_accept >= 6'd32) begin
      block_step_after_accept = 2'd2;
    end else if (pc_offset_after_accept >= 6'd16) begin
      block_step_after_accept = 2'd1;
    end
    need_hi_fetch = !buf_hi_valid && !pending_hi_fetch;
    // Allow LO fetch to overlap the in-flight HI request so the next block
    // is ready before we consume the tail of HI.
    need_lo_fetch = (buf_hi_valid || pending_hi_fetch) &&
                    !buf_lo_valid && !pending_lo_fetch;
    need_pf_fetch = buf_hi_valid && (buf_lo_valid || pending_lo_fetch) &&
                    !buf_pf_valid && !pending_pf_fetch;
    need_p2_fetch = buf_hi_valid && (buf_pf_valid || pending_pf_fetch) &&
                    !buf_p2_valid && !pending_p2_fetch;
  end

  // Use incoming memory data for decode in the same cycle it arrives.
  always_comb begin
    hi_data_eff = buf_hi;
    lo_data_eff = buf_lo;
    pf_data_eff = buf_pf;
    p2_data_eff = buf_p2;
    hi_valid_eff = buf_hi_valid;
    lo_valid_eff = buf_lo_valid;
    pf_valid_eff = buf_pf_valid;
    p2_valid_eff = buf_p2_valid;


  end

  // Select the PC/buffer view for decode. If the current outputs are being
  // accepted this cycle, precompute decode from the post-accept PC/buffer.
  always_comb begin
    decode_pc = current_pc;
    decode_base_addr = buf_base_addr;
    decode_buf_hi = hi_data_eff;
    decode_buf_lo = lo_data_eff;
    decode_hi_valid = hi_valid_eff;
    decode_lo_valid = lo_valid_eff;

    if (!out_hold) begin
      decode_pc = pc_after_accept;
      decode_base_addr = buf_base_addr;
      if (block_step_after_accept == 2'd1) begin
        decode_base_addr = buf_base_addr + 32'd16;
        decode_buf_hi = lo_data_eff;
        decode_buf_lo = pf_data_eff;
        decode_hi_valid = lo_valid_eff;
        decode_lo_valid = pf_valid_eff;
      end else if (block_step_after_accept == 2'd2) begin
        decode_base_addr = buf_base_addr + 32'd32;
        decode_buf_hi = pf_data_eff;
        decode_buf_lo = p2_data_eff;
        decode_hi_valid = pf_valid_eff;
        decode_lo_valid = p2_valid_eff;
      end
    end
  end

  // Request scheduling: prefer filling HI, then LO, then speculative next block.
  always_comb begin
    req_valid = 1'b0;
    req_addr = 32'h0;
    req_dest = REQ_NONE;
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
    end else if (need_pf_fetch) begin
      req_valid = 1'b1;
      req_addr = buf_base_addr + 32'h20;
      req_dest = REQ_PF;
      state_next = FETCH_PF;
    end else if (need_p2_fetch) begin
      req_valid = 1'b1;
      req_addr = buf_base_addr + 32'h30;
      req_dest = REQ_P2;
      state_next = FETCH_PF;
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
  assign pc_offset = decode_pc[3:0]; // Offset within buf_hi
  
  // Helper to extract up to 9 bytes at offset without variable part-select.
  // Bytes beyond the 32-byte buffer are padded with zero.
  function automatic logic [71:0] extract_9_bytes(input logic [255:0] buf_in, input logic [4:0] off);
      begin
          case (off)
              5'd0:  extract_9_bytes = buf_in[255 -: 72];
              5'd1:  extract_9_bytes = buf_in[247 -: 72];
              5'd2:  extract_9_bytes = buf_in[239 -: 72];
              5'd3:  extract_9_bytes = buf_in[231 -: 72];
              5'd4:  extract_9_bytes = buf_in[223 -: 72];
              5'd5:  extract_9_bytes = buf_in[215 -: 72];
              5'd6:  extract_9_bytes = buf_in[207 -: 72];
              5'd7:  extract_9_bytes = buf_in[199 -: 72];
              5'd8:  extract_9_bytes = buf_in[191 -: 72];
              5'd9:  extract_9_bytes = buf_in[183 -: 72];
              5'd10: extract_9_bytes = buf_in[175 -: 72];
              5'd11: extract_9_bytes = buf_in[167 -: 72];
              5'd12: extract_9_bytes = buf_in[159 -: 72];
              5'd13: extract_9_bytes = buf_in[151 -: 72];
              5'd14: extract_9_bytes = buf_in[143 -: 72];
              5'd15: extract_9_bytes = buf_in[135 -: 72];
              5'd16: extract_9_bytes = buf_in[127 -: 72];
              5'd17: extract_9_bytes = buf_in[119 -: 72];
              5'd18: extract_9_bytes = buf_in[111 -: 72];
              5'd19: extract_9_bytes = buf_in[103 -: 72];
              5'd20: extract_9_bytes = buf_in[95 -: 72];
              5'd21: extract_9_bytes = buf_in[87 -: 72];
              5'd22: extract_9_bytes = buf_in[79 -: 72];
              5'd23: extract_9_bytes = buf_in[71 -: 72];
              5'd24: extract_9_bytes = {buf_in[63:0], 8'h00};
              5'd25: extract_9_bytes = {buf_in[55:0], 16'h0000};
              5'd26: extract_9_bytes = {buf_in[47:0], 24'h000000};
              5'd27: extract_9_bytes = {buf_in[39:0], 32'h00000000};
              5'd28: extract_9_bytes = {buf_in[31:0], 40'h0000000000};
              5'd29: extract_9_bytes = {buf_in[23:0], 48'h000000000000};
              5'd30: extract_9_bytes = {buf_in[15:0], 56'h00000000000000};
              5'd31: extract_9_bytes = {buf_in[7:0], 64'h0000000000000000};
              default: extract_9_bytes = 72'h0;
          endcase
      end
  endfunction

  function automatic logic [7:0] extract_byte(input logic [255:0] buf_in, input logic [4:0] off);
      begin
          case (off)
              5'd0:  extract_byte = buf_in[255 -: 8];
              5'd1:  extract_byte = buf_in[247 -: 8];
              5'd2:  extract_byte = buf_in[239 -: 8];
              5'd3:  extract_byte = buf_in[231 -: 8];
              5'd4:  extract_byte = buf_in[223 -: 8];
              5'd5:  extract_byte = buf_in[215 -: 8];
              5'd6:  extract_byte = buf_in[207 -: 8];
              5'd7:  extract_byte = buf_in[199 -: 8];
              5'd8:  extract_byte = buf_in[191 -: 8];
              5'd9:  extract_byte = buf_in[183 -: 8];
              5'd10: extract_byte = buf_in[175 -: 8];
              5'd11: extract_byte = buf_in[167 -: 8];
              5'd12: extract_byte = buf_in[159 -: 8];
              5'd13: extract_byte = buf_in[151 -: 8];
              5'd14: extract_byte = buf_in[143 -: 8];
              5'd15: extract_byte = buf_in[135 -: 8];
              5'd16: extract_byte = buf_in[127 -: 8];
              5'd17: extract_byte = buf_in[119 -: 8];
              5'd18: extract_byte = buf_in[111 -: 8];
              5'd19: extract_byte = buf_in[103 -: 8];
              5'd20: extract_byte = buf_in[95 -: 8];
              5'd21: extract_byte = buf_in[87 -: 8];
              5'd22: extract_byte = buf_in[79 -: 8];
              5'd23: extract_byte = buf_in[71 -: 8];
              5'd24: extract_byte = buf_in[63 -: 8];
              5'd25: extract_byte = buf_in[55 -: 8];
              5'd26: extract_byte = buf_in[47 -: 8];
              5'd27: extract_byte = buf_in[39 -: 8];
              5'd28: extract_byte = buf_in[31 -: 8];
              5'd29: extract_byte = buf_in[23 -: 8];
              5'd30: extract_byte = buf_in[15 -: 8];
              5'd31: extract_byte = buf_in[7 -: 8];
              default: extract_byte = 8'h00;
          endcase
      end
  endfunction

  logic [3:0]  len_0, len_1;
  logic [3:0]  inst0_off;

  always_comb begin
      logic [4:0] inst0_off_5;
      logic [7:0] opcode_0;
      logic [7:0] spec_0;
      inst0_off = pc_offset;
      inst0_off_5 = {1'b0, inst0_off};
      spec_0 = extract_byte(buffer, inst0_off_5);
      opcode_0 = extract_byte(buffer, inst0_off_5 + 5'd1);

      // Calculate length from opcode/specifier bytes only.
      len_0 = get_inst_length(opcode_0, spec_0);
  end

  // Validity Checks
  logic inst0_fits;
  logic inst1_fits;
  logic inst0_len_knowable;
  logic inst1_len_knowable;
  logic [71:0] next_inst_data_0, next_inst_data_1;
  logic [3:0]  next_len_0, next_len_1;
  logic [31:0] next_pc_0, next_pc_1;
  logic        next_valid_0, next_valid_1;
  
  always_comb begin
      inst0_fits = 0;
      inst1_fits = 0;
      inst0_len_knowable = 0;
      inst1_len_knowable = 0;
      len_1 = 4'h0;
      
      if (decode_hi_valid && (decode_pc[31:4] == decode_base_addr[31:4])) begin
          // Inst 0 Length knowability: Need Byte 0 (Spec) and Byte 1 (Opcode).
          // Byte 1 of inst0 is at (pc_offset + 1). 
          if (pc_offset < 15) begin
             inst0_len_knowable = 1; // Both bytes in HI block (which is valid here)
          end else if (pc_offset == 15) begin
             inst0_len_knowable = decode_lo_valid; // Byte 0 in HI, Byte 1 in LO
          end else begin
             // pc_offset >= 16: Should not happen if buf_hi points to current_pc
             // But if we are in buf_lo territory, we would have shifted.
             inst0_len_knowable = 0;
          end

          if (inst0_len_knowable) begin
              // Check if entire instruction fits in current valid blocks
              if (pc_offset + len_0 <= 16) begin
                  inst0_fits = 1; // Entirely in HI
              end else if (pc_offset + len_0 <= 32 && decode_lo_valid) begin
                  inst0_fits = 1; // Straddles HI/LO, and LO is valid
              end
          end
          
          // Inst 1
          if (FETCH_DUAL_ENABLE && inst0_fits && len_0 > 0) begin
             logic [4:0] start_off_1;
             start_off_1 = {1'b0, pc_offset} + len_0;
             
             // Can we know len_1? Need bytes start_off_1 and start_off_1 + 1
             if (start_off_1 < 15) begin
                inst1_len_knowable = 1; // Both in HI
             end else if (start_off_1 == 15) begin
                inst1_len_knowable = decode_lo_valid; // Straddles
             end else if (start_off_1 < 31) begin
                inst1_len_knowable = decode_lo_valid; // Both in LO
             end
             
             if (inst1_len_knowable) begin
                logic [5:0] end_off_1;
                logic [7:0] opcode_1;
                logic [7:0] spec_1;
                spec_1 = extract_byte(buffer, start_off_1);
                opcode_1 = extract_byte(buffer, start_off_1 + 5'd1);
                len_1 = get_inst_length(opcode_1, spec_1);
                end_off_1 = {1'b0, start_off_1} + len_1;
                if (end_off_1 <= 16) begin
                    inst1_fits = 1;
                end else if (end_off_1 <= 32 && decode_lo_valid) begin
                    inst1_fits = 1;
                end
             end
          end
      end
  end

  // Output Assignment (Combinational -> Registered IF2 stage)
  always_comb begin
      logic [4:0] inst0_off_5;
      logic [4:0] start_off_1;
      // Payload always follows current decode window; validity bits gate use.
      next_valid_0 = 0;
      next_inst_data_0 = 72'h0;
      next_len_0 = len_0;
      next_pc_0 = decode_pc;
      
      next_valid_1 = 0;
      next_inst_data_1 = 72'h0;
      next_len_1 = 4'h0;
      next_pc_1 = 32'h0;
      inst0_off_5 = {1'b0, pc_offset};
      start_off_1 = 5'd0;

      next_inst_data_0 = extract_9_bytes(buffer, inst0_off_5);

      if (FETCH_DUAL_ENABLE) begin
        next_len_1 = len_1;
        next_pc_1 = decode_pc + {28'h0, len_0};
        start_off_1 = inst0_off_5 + len_0;
        next_inst_data_1 = extract_9_bytes(buffer, start_off_1);
      end

      if (inst0_fits) next_valid_0 = 1;
      if (FETCH_DUAL_ENABLE && inst1_fits) next_valid_1 = 1;
  end

  // ============================================================================
  // Sequential Logic
  // ============================================================================

  // Registered output stage (IF2).
  assign out_hold = (accept_count == 2'd0) && out_valid_0;

  // Keep branch flush local to validity bits; payload data can remain stale when
  // invalid. This avoids routing branch_kill through wide IF2 payload controls.
  always_ff @(posedge clk) begin
    if (rst || branch_taken) begin
      out_valid_0 <= 1'b0;
      out_valid_1 <= 1'b0;
    end else if (!out_hold) begin
      out_valid_0 <= next_valid_0;
      out_valid_1 <= next_valid_1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      out_inst_data_0 <= 72'h0;
      out_len_0 <= 4'h0;
      out_pc_0 <= 32'h0;
      out_inst_data_1 <= 72'h0;
      out_len_1 <= 4'h0;
      out_pc_1 <= 32'h0;
    end else if (!out_hold) begin
      out_inst_data_0 <= next_inst_data_0;
      out_len_0 <= next_len_0;
      out_pc_0 <= next_pc_0;
      out_inst_data_1 <= next_inst_data_1;
      out_len_1 <= next_len_1;
      out_pc_1 <= next_pc_1;
    end
  end

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
    logic [127:0] n_buf_pf;
    logic [127:0] n_buf_p2;
    logic        n_hi_valid;
    logic        n_lo_valid;
    logic        n_pf_valid;
    logic        n_p2_valid;
    logic        n_pending_hi;
    logic        n_pending_lo;
    logic        n_pending_pf;
    logic        n_pending_p2;
    logic        n_mem_req;
    logic [31:0] n_mem_addr;
    logic [1:0]  n_req_q_count;
    req_dest_e   n_req_q0;
    req_dest_e   n_req_q1;

    if (rst) begin
        state <= IDLE;
        buf_hi_valid <= 1'b0;
        buf_lo_valid <= 1'b0;
        buf_pf_valid <= 1'b0;
        buf_p2_valid <= 1'b0;
        pending_hi_fetch <= 1'b0;
        pending_lo_fetch <= 1'b0;
        pending_pf_fetch <= 1'b0;
        pending_p2_fetch <= 1'b0;
        mem_req_q <= 1'b0;
        branch_req_q <= 1'b0;
        mem_addr_q <= 32'h0;
        req_q_count <= 2'd0;
        req_q0 <= REQ_NONE;
        req_q1 <= REQ_NONE;
        
    end else if (branch_taken) begin
        // Branch redirect: reuse buffers if target stays within the current window.
        logic [31:0] target_base;
        target_base = branch_target & 32'hFFFF_FFF0;

        state <= FETCH_HI;
        mem_req_q <= 1'b0;
        branch_req_q <= 1'b0;
        mem_addr_q <= 32'h0;
        req_q_count <= 2'd0;
        req_q0 <= REQ_NONE;
        req_q1 <= REQ_NONE;
        pending_hi_fetch <= 1'b0;
        pending_lo_fetch <= 1'b0;
        pending_pf_fetch <= 1'b0;
        pending_p2_fetch <= 1'b0;

        if ((target_base == buf_base_addr) && buf_hi_valid) begin
            buf_hi <= buf_hi;
            buf_lo <= buf_lo;
            buf_pf <= buf_pf;
            buf_p2 <= buf_p2;
            buf_hi_valid <= buf_hi_valid;
            buf_lo_valid <= buf_lo_valid;
            buf_pf_valid <= buf_pf_valid;
            buf_p2_valid <= buf_p2_valid;
        end else if ((target_base == (buf_base_addr + 32'd16)) && buf_lo_valid) begin
            buf_hi <= buf_lo;
            buf_lo <= buf_pf;
            buf_pf <= buf_p2;
            buf_p2 <= 128'h0;
            buf_hi_valid <= buf_lo_valid;
            buf_lo_valid <= buf_pf_valid;
            buf_pf_valid <= buf_p2_valid;
            buf_p2_valid <= 1'b0;
        end else if ((target_base == (buf_base_addr + 32'd32)) && buf_pf_valid) begin
            buf_hi <= buf_pf;
            buf_lo <= buf_p2;
            buf_pf <= 128'h0;
            buf_p2 <= 128'h0;
            buf_hi_valid <= buf_pf_valid;
            buf_lo_valid <= buf_p2_valid;
            buf_pf_valid <= 1'b0;
            buf_p2_valid <= 1'b0;
        end else if ((target_base == (buf_base_addr + 32'd48)) && buf_p2_valid) begin
            buf_hi <= buf_p2;
            buf_lo <= 128'h0;
            buf_pf <= 128'h0;
            buf_p2 <= 128'h0;
            buf_hi_valid <= buf_p2_valid;
            buf_lo_valid <= 1'b0;
            buf_pf_valid <= 1'b0;
            buf_p2_valid <= 1'b0;
        end else begin
            buf_hi_valid <= 1'b0;
            buf_lo_valid <= 1'b0;
            buf_pf_valid <= 1'b0;
            buf_p2_valid <= 1'b0;
            buf_hi <= 128'h0;
            buf_lo <= 128'h0;
            buf_pf <= 128'h0;
            buf_p2 <= 128'h0;

            // Issue branch target fetch immediately (1-cycle mem).
            mem_req_q <= 1'b1;
            branch_req_q <= 1'b1;
            mem_addr_q <= target_base;
            pending_hi_fetch <= 1'b1;
            req_q_count <= 2'd1;
            req_q0 <= REQ_HI;
        end
        
    end else begin
        // Defaults
        n_buf_hi   = buf_hi;
        n_buf_lo   = buf_lo;
        n_buf_pf   = buf_pf;
        n_buf_p2   = buf_p2;
        n_hi_valid = buf_hi_valid;
        n_lo_valid = buf_lo_valid;
        n_pf_valid = buf_pf_valid;
        n_p2_valid = buf_p2_valid;
        n_pending_hi = pending_hi_fetch;
        n_pending_lo = pending_lo_fetch;
        n_pending_pf = pending_pf_fetch;
        n_pending_p2 = pending_p2_fetch;
        n_mem_req = 1'b0;
        n_mem_addr = mem_addr_q;
        n_req_q_count = req_q_count;
        n_req_q0 = req_q0;
        n_req_q1 = req_q1;

        // Consume memory response from the in-flight request queue.
        if (mem_ack && (n_req_q_count != 2'd0)) begin
            req_dest_e ack_dest;
            ack_dest = n_req_q0;
            case (ack_dest)
                REQ_HI: begin
                    n_buf_hi = mem_rdata;
                    n_hi_valid = 1'b1;
                    n_pending_hi = 1'b0;
                end
                REQ_LO: begin
                    n_buf_lo = mem_rdata;
                    n_lo_valid = 1'b1;
                    n_pending_lo = 1'b0;
                end
                REQ_PF: begin
                    n_buf_pf = mem_rdata;
                    n_pf_valid = 1'b1;
                    n_pending_pf = 1'b0;
                end
                REQ_P2: begin
                    n_buf_p2 = mem_rdata;
                    n_p2_valid = 1'b1;
                    n_pending_p2 = 1'b0;
                end
                default: ;
            endcase
            // Pop head
            if (n_req_q_count == 2'd2) begin
                n_req_q0 = n_req_q1;
                n_req_q1 = REQ_NONE;
            end else begin
                n_req_q0 = REQ_NONE;
            end
            n_req_q_count = n_req_q_count - 2'd1;
        end

        // Drive memory request stage from scheduler outputs (registered pulse).
        // Keep this before shift bookkeeping so LO->HI reclassification remains correct.
        if (req_valid && (n_req_q_count < 2'd2)) begin
            n_mem_req = 1'b1;
            n_mem_addr = req_addr;
            if (n_req_q_count == 2'd0) begin
                n_req_q0 = req_dest;
            end else begin
                n_req_q1 = req_dest;
            end
            n_req_q_count = n_req_q_count + 2'd1;
            if (req_dest == REQ_HI) begin
                n_pending_hi = 1'b1;
            end else if (req_dest == REQ_LO) begin
                n_pending_lo = 1'b1;
            end else if (req_dest == REQ_PF) begin
                n_pending_pf = 1'b1;
            end else if (req_dest == REQ_P2) begin
                n_pending_p2 = 1'b1;
            end
        end

        if (accept_count != 2'd0) begin
            // Buffer shift based on the post-accept PC (max two-instruction window is 16 bytes)
            if (block_step_after_accept != 2'd0) begin
                if (block_step_after_accept == 2'd1) begin
                    n_buf_hi = n_buf_lo;
                    n_hi_valid = n_lo_valid;
                    n_buf_lo = n_buf_pf;
                    n_lo_valid = n_pf_valid;
                    n_buf_pf = n_buf_p2;
                    n_pf_valid = n_p2_valid;
                    n_p2_valid = 1'b0;
                    n_buf_p2 = 128'h0;
                    
                    // If we had a pending LO fetch, it now corresponds to the new HI block.
                    if (n_pending_lo) begin
                        n_pending_hi = 1'b1;
                        n_pending_lo = 1'b0;
                        if (n_req_q0 == REQ_LO) n_req_q0 = REQ_HI;
                        if (n_req_q1 == REQ_LO) n_req_q1 = REQ_HI;
                    end
                    if (n_pending_pf) begin
                        n_pending_lo = 1'b1;
                        n_pending_pf = 1'b0;
                        if (n_req_q0 == REQ_PF) n_req_q0 = REQ_LO;
                        if (n_req_q1 == REQ_PF) n_req_q1 = REQ_LO;
                    end
                    if (n_pending_p2) begin
                        n_pending_pf = 1'b1;
                        n_pending_p2 = 1'b0;
                        if (n_req_q0 == REQ_P2) n_req_q0 = REQ_PF;
                        if (n_req_q1 == REQ_P2) n_req_q1 = REQ_PF;
                    end
                end else begin
                    n_buf_hi = n_buf_pf;
                    n_hi_valid = n_pf_valid;
                    n_buf_lo = n_buf_p2;
                    n_lo_valid = n_p2_valid;
                    n_pf_valid = 1'b0;
                    n_buf_pf = 128'h0;
                    n_p2_valid = 1'b0;
                    n_buf_p2 = 128'h0;
                    
                    // Skipped blocks; drop stale HI/LO requests and remap PF to HI.
                    n_pending_hi = n_pending_pf;
                    n_pending_lo = n_pending_p2;
                    n_pending_pf = 1'b0;
                    n_pending_p2 = 1'b0;
                    n_mem_req = 1'b0;
                    // Preserve only PF requests (now HI); drop stale HI/LO.
                    if (n_req_q_count != 2'd0) begin
                      logic [1:0] keep_count;
                      req_dest_e keep0;
                      req_dest_e keep1;
                      req_dest_e mapped;
                      keep_count = 2'd0;
                      keep0 = REQ_NONE;
                      keep1 = REQ_NONE;

                      mapped = REQ_NONE;
                      if (n_req_q0 == REQ_PF) mapped = REQ_HI;
                      else if (n_req_q0 == REQ_P2) mapped = REQ_LO;
                      if (mapped != REQ_NONE) begin
                        keep0 = mapped;
                        keep_count = keep_count + 2'd1;
                      end

                      mapped = REQ_NONE;
                      if (n_req_q1 == REQ_PF) mapped = REQ_HI;
                      else if (n_req_q1 == REQ_P2) mapped = REQ_LO;
                      if (mapped != REQ_NONE) begin
                        if (keep_count == 2'd0) begin
                          keep0 = mapped;
                        end else begin
                          keep1 = mapped;
                        end
                        keep_count = keep_count + 2'd1;
                      end

                      n_req_q_count = keep_count;
                      n_req_q0 = keep0;
                      n_req_q1 = keep1;
                    end else begin
                      n_req_q_count = 2'd0;
                      n_req_q0 = REQ_NONE;
                      n_req_q1 = REQ_NONE;
                    end
                end
            end
        end

        // Commit Updates
        buf_hi <= n_buf_hi;
        buf_lo <= n_buf_lo;
        buf_pf <= n_buf_pf;
        buf_p2 <= n_buf_p2;
        buf_hi_valid <= n_hi_valid;
        buf_lo_valid <= n_lo_valid;
        buf_pf_valid <= n_pf_valid;
        buf_p2_valid <= n_p2_valid;
        pending_hi_fetch <= n_pending_hi;
        pending_lo_fetch <= n_pending_lo;
        pending_pf_fetch <= n_pending_pf;
        pending_p2_fetch <= n_pending_p2;
        mem_req_q <= n_mem_req;
        mem_addr_q <= n_mem_addr;
        req_q_count <= n_req_q_count;
        req_q0 <= n_req_q0;
        req_q1 <= n_req_q1;
        state <= state_next;
        branch_req_q <= 1'b0;
    end
  end

  // Assign outputs from registered IF2 stage
  assign inst_data_0 = out_inst_data_0;
  assign inst_len_0 = out_len_0;
  assign pc_0 = out_pc_0;
  assign valid_0 = out_valid_0;

  assign inst_data_1 = out_inst_data_1;
  assign inst_len_1 = out_len_1;
  assign pc_1 = out_pc_1;
  assign valid_1 = out_valid_1;

  // Assign memory request outputs
  assign mem_req = mem_req_q && !rst && (!branch_taken || branch_req_q);
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
