//
// fetch_unit.sv
// NeoCore 16x32 CPU - Instruction Fetch Unit (Simplified)
//
// Fetches variable-length instructions using 16-byte aligned access.
// Uses the memory output register as the primary buffer.
// Handles straddling instructions using a small residual buffer.
//
// Strategy:
//   - Fetch 16-byte aligned blocks.
//   - Execute instructions from the memory output (mem_rdata).
//   - If an instruction straddles the 16-byte boundary:
//     1. Save the available bytes into 'residual_buffer'.
//     2. Fetch the next 16-byte block.
//     3. Combine residual + new block to form the instruction.
//     4. Continue execution from the new block.
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
  input  logic        dual_issue,   // Dual-issue enable from issue unit
  
  // Unified memory interface (16-byte aligned fetch)
  output logic [31:0] mem_addr,
  output logic        mem_req,
  input  logic [127:0] mem_rdata,   // 16 bytes of instruction data (big-endian)
  input  logic        mem_ack,
  
  // Output to decode
  output logic [71:0]  inst_data_0,  // First instruction (up to 9 bytes, padded to 72 bits)
  output logic [3:0]   inst_len_0,   // First instruction length
  output logic [31:0]  pc_0,         // PC of first instruction
  output logic         valid_0,      // First instruction valid
  
  output logic [71:0]  inst_data_1,  // Second instruction (for dual-issue)
  output logic [3:0]   inst_len_1,
  output logic [31:0]  pc_1,
  output logic         valid_1
);

  // ============================================================================
  // Internal State
  // ============================================================================
  
  // Current PC (byte address)
  logic [31:0] current_pc;
  
  // Offset within the current 16-byte block (0-15)
  logic [3:0] block_offset;
  
  // Base address of the current block (aligned to 16 bytes)
  logic [31:0] block_base_addr;
  
  // Residual Buffer for Straddling Instructions
  // Max instruction length is 9 bytes.
  // We might save up to 15 bytes (if 1 byte is in next block).
  logic [7:0] residual_buffer[16];
  logic [4:0] residual_len; // Changed to 5 bits to hold up to 16 safely
  
  // State Machine
  typedef enum logic [2:0] {
    STATE_INIT,         // Start/Reset/Branch: Request first block
    STATE_WAIT_FIRST,   // Wait for first block
    STATE_NORMAL,       // Execute from mem_rdata
    STATE_FETCH_NEXT,   // Request next block (for straddle or end of block)
    STATE_WAIT_NEXT,    // Wait for next block (straddle)
    STATE_STRADDLE      // Execute straddling instruction
  } state_e;
  
  state_e state, state_next;
  
  // Helper to map mem_rdata (128 bits) to byte array
  logic [7:0] current_block[16];
  
  genvar i;
  generate
    for (i=0; i<16; i++) begin : gen_block_map
      assign current_block[i] = mem_rdata[(15-i)*8 +: 8];
    end
  endgenerate

  // ============================================================================
  // Fetch Logic & State Machine
  // ============================================================================
  
  logic [31:0] fetch_addr;
  logic        fetch_req;
  
  always_comb begin
    state_next = state;
    fetch_req = 1'b0;
    fetch_addr = 32'h0;
    
    case (state)
      STATE_INIT: begin
        fetch_req = 1'b1;
        fetch_addr = {current_pc[31:4], 4'h0}; // Align
        if (!stall) state_next = STATE_WAIT_FIRST;
      end
      
      STATE_WAIT_FIRST: begin
        // Keep requesting until ack
        fetch_req = 1'b1;
        fetch_addr = {current_pc[31:4], 4'h0};
        if (mem_ack) state_next = STATE_NORMAL;
      end
      
      STATE_NORMAL: begin
        // Normal execution handled in output logic.
        // Transitions handled in FF block based on consumption/straddle.
      end
      
      STATE_FETCH_NEXT: begin
        fetch_req = 1'b1;
        fetch_addr = block_base_addr + 32'd16;
        if (!stall) state_next = STATE_WAIT_NEXT;
      end
      
      STATE_WAIT_NEXT: begin
        fetch_req = 1'b1;
        fetch_addr = block_base_addr + 32'd16;
        if (mem_ack) begin
             // If we were fetching for a straddle, go to STRADDLE
             // If we were fetching because we finished a block exactly, go to NORMAL
             // We can distinguish by checking residual_len
             if (residual_len > 0) state_next = STATE_STRADDLE;
             else state_next = STATE_NORMAL;
        end
      end
      
      STATE_STRADDLE: begin
        // Execute straddling instruction.
        // Next cycle go to NORMAL.
        if (!stall) state_next = STATE_NORMAL;
      end
    endcase
  end
  
  assign mem_req = fetch_req && !stall;
  assign mem_addr = fetch_addr;
  
  // ============================================================================
  // Instruction Pre-Decode (Combinational)
  // ============================================================================
  
  logic [7:0] spec_0, op_0;
  logic [3:0] len_0;
  logic       straddle_0;
  
  logic [7:0] spec_1, op_1;
  logic [3:0] len_1;
  logic       straddle_1;
  logic [4:0] offset_1; // Moved to module scope
  
  always_comb begin
    // Defaults
    spec_0 = 8'h0; op_0 = 8'h0; len_0 = 4'h0; straddle_0 = 1'b0;
    spec_1 = 8'h0; op_1 = 8'h0; len_1 = 4'h0; straddle_1 = 1'b0;
    offset_1 = 5'h0;
    
    if (state == STATE_NORMAL) begin
      // --- Inst 0 ---
      if (block_offset < 16) begin
        spec_0 = current_block[block_offset];
        // Opcode might be in next byte
        if (block_offset < 15) op_0 = current_block[block_offset + 1];
        else op_0 = 8'h00; // Opcode straddles!
        
        len_0 = get_inst_length(op_0, spec_0);
        
        // Check straddle
        if (({1'b0, block_offset} + {1'b0, len_0}) > 5'd16) straddle_0 = 1'b1;
        if (block_offset == 15) straddle_0 = 1'b1; // Special case: Opcode missing
      end
      
      // --- Inst 1 ---
      // Only if Inst 0 is valid and doesn't straddle
      if (len_0 > 0 && !straddle_0) begin
        offset_1 = {1'b0, block_offset} + {1'b0, len_0};
        if (offset_1 < 16) begin
          spec_1 = current_block[offset_1];
          if (offset_1 < 15) op_1 = current_block[offset_1 + 1];
          else op_1 = 8'h00;
          
          len_1 = get_inst_length(op_1, spec_1);
          
          if (({1'b0, offset_1} + {1'b0, len_1}) > 5'd16) straddle_1 = 1'b1;
          if (offset_1 == 15) straddle_1 = 1'b1;
        end
      end
    end
  end

  // ============================================================================
  // Output Generation
  // ============================================================================
  
  // Temporary variables for straddle reconstruction
  logic [7:0] s0_straddle, o0_straddle;
  
  always_comb begin
    valid_0 = 1'b0;
    valid_1 = 1'b0;
    inst_data_0 = 72'h0;
    inst_data_1 = 72'h0;
    inst_len_0 = len_0; // From pre-decode
    inst_len_1 = len_1;
    pc_0 = current_pc;
    pc_1 = current_pc;
    
    // Initialize straddle temps
    s0_straddle = 8'h0;
    o0_straddle = 8'h0;
    
    if (state == STATE_NORMAL && !branch_taken) begin
      if (len_0 > 0 && !straddle_0) begin
        valid_0 = 1'b1;
        pc_0 = current_pc;
        for (int i=0; i<9; i++) begin
           if (block_offset + i < 16) inst_data_0[(8-i)*8 +: 8] = current_block[block_offset + i];
        end
        
        // Dual Issue
        if (dual_issue && len_1 > 0 && !straddle_1 && (op_1 != OP_HLT)) begin
          valid_1 = 1'b1;
          pc_1 = current_pc + {28'h0, len_0};
          for (int i=0; i<9; i++) begin
             if (block_offset + len_0 + i < 16) 
               inst_data_1[(8-i)*8 +: 8] = current_block[block_offset + len_0 + i];
          end
        end
      end
      // If straddle_0, we output nothing and wait for state transition
    end
    
    else if (state == STATE_STRADDLE && !branch_taken) begin
      // Reconstruct instruction from residual + current_block (which is now next block)
      valid_0 = 1'b1;
      pc_0 = current_pc;
      
      // First bytes from residual
      for (int i=0; i<16; i++) begin
        if (i < residual_len && i < 9) inst_data_0[(8-i)*8 +: 8] = residual_buffer[i];
      end
      
      // Remaining bytes from current_block (new block)
      // We need to fill inst_data starting at byte 'residual_len'
      // inst_data byte J comes from current_block[J - residual_len]
      for (int i=0; i<9; i++) begin
        if (i >= residual_len) begin
           inst_data_0[(8-i)*8 +: 8] = current_block[i - residual_len];
        end
      end
      
      // Recalculate length based on full data (opcode might have been missing)
      s0_straddle = residual_buffer[0];
      if (residual_len >= 5'd2) o0_straddle = residual_buffer[1];
      else o0_straddle = current_block[0];
      
      inst_len_0 = get_inst_length(o0_straddle, s0_straddle);
      
      // No dual issue on straddle
      valid_1 = 1'b0;
    end
  end

  // ============================================================================
  // Sequential Logic (State & Data Update)
  // ============================================================================
  
  // Temporary variables for sequential logic
  logic [4:0] total_len_seq;
  logic [4:0] next_offset_seq;
  logic [3:0] bytes_from_new_seq;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_INIT;
      current_pc <= 32'h0;
      block_offset <= 4'h0;
      block_base_addr <= 32'h0;
      residual_len <= 5'h0;
      for (int i=0; i<16; i++) residual_buffer[i] <= 8'h0;
      
    end else if (branch_taken) begin
      state <= STATE_INIT;
      current_pc <= branch_target;
      block_offset <= branch_target[3:0];
      // block_base_addr will be updated when we fetch
      
    end else if (!stall) begin
      state <= state_next;
      
      // Update Block Base Address
      if (state == STATE_INIT || state == STATE_WAIT_FIRST) begin
        if (mem_ack) block_base_addr <= {current_pc[31:4], 4'h0};
      end else if (state == STATE_WAIT_NEXT) begin
        if (mem_ack) block_base_addr <= block_base_addr + 32'd16;
      end
      
      // Handle Consumption / Transitions
      if (state == STATE_NORMAL) begin
        if (straddle_0) begin
          // Straddle detected on Inst 0
          // Save residual
          residual_len <= 5'd16 - {1'b0, block_offset};
          for (int i=0; i<16; i++) begin
            if (block_offset + i < 16) residual_buffer[i] <= current_block[block_offset + i];
          end
          // Transition to FETCH_NEXT
          state <= STATE_FETCH_NEXT;
          
        end else if (valid_0) begin
          // Inst 0 valid
          total_len_seq = {1'b0, len_0};
          
          if (valid_1) begin
             total_len_seq = total_len_seq + {1'b0, len_1};
          end
          
          // Update PC
          current_pc <= current_pc + {27'h0, total_len_seq};
          
          // Update Offset
          next_offset_seq = {1'b0, block_offset} + total_len_seq;
          
          if (next_offset_seq >= 5'd16) begin
             // Exact match or overflow
             block_offset <= 4'h0;
             residual_len <= 5'h0; // No residual
             state <= STATE_FETCH_NEXT;
          end else begin
             block_offset <= next_offset_seq[3:0];
          end
        end
      end
      
      else if (state == STATE_STRADDLE) begin
        // We just executed the straddling instruction
        // Update PC
        current_pc <= current_pc + {28'h0, inst_len_0};
        
        // Update Offset in NEW block
        bytes_from_new_seq = inst_len_0 - residual_len[3:0];
        
        block_offset <= bytes_from_new_seq;
        state <= STATE_NORMAL;
      end
    end
  end

endmodule : fetch_unit
