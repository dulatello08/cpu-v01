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
  output logic         valid_1,
  
  // Feedback from Issue Stage
  input  logic [1:0]   consumed_count, // 0, 1, or 2
  input  logic [3:0]   id_inst_len_0,
  input  logic [3:0]   id_inst_len_1,
  input  logic [31:0]  id_pc,
  input  logic         id_valid
);

  // ============================================================================
  // Internal State
  // ============================================================================
  
  // Current PC (byte address)
  logic [31:0] current_pc;
  
  // State Machine
  typedef enum logic [1:0] {
    STATE_INIT,         // Start/Reset/Branch
    STATE_REQ,          // Issue memory request
    STATE_WAIT_ACK      // Wait for memory ack
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
  
  // ============================================================================
  // Fetch Logic & State Machine
  // ============================================================================
  
  logic [31:0] fetch_addr;
  logic        fetch_req;
  
  // Calculate next PC combinationally based on current decode attempt
  logic [31:0] next_pc_comb;
  
  always_comb begin
     logic [4:0] total_len_comb;
     total_len_comb = 5'd0;
     
     if (valid_0) begin
        total_len_comb = {1'b0, len_0};
        if (valid_1) begin
           total_len_comb = total_len_comb + {1'b0, len_1};
        end
     end
     
     next_pc_comb = current_pc + {27'h0, total_len_comb};
  end

  always_comb begin
    state_next = state;
    fetch_req = 1'b0;
    fetch_addr = 32'h0;
    
    // Default: Request current conceptual PC
    // We might override this below if we are "streaming"
    
    case (state)
      STATE_INIT: begin
        // Transition to REQ to start fetching
        if (!stall) state_next = STATE_REQ;
      end
      
      STATE_REQ: begin
        // By default request current
        // If we get an ACK this cycle, we want to Request NEXT_PC in the SAME cycle
        // to avoid a dead bubble.
        
        fetch_req = 1'b1;
        fetch_addr = current_pc;
        
        if (!stall) begin
          if (mem_ack) begin
            // OPTIMIZATION: Zero-Wait State Machine
            // We received data for 'current_pc' NOW.
            // We can immediately issue request for 'next_pc_comb'.
            
            // To do this, we must update the address output THIS cycle.
            // But 'current_pc' register won't update until clock edge.
            // So we bypass the address output.
             
            fetch_addr = next_pc_comb; // Speculative next request
            
            // Stay in REQ state -> Fetch pipeline full
            state_next = STATE_REQ;
          end else begin
            // Wait for ack
            state_next = STATE_WAIT_ACK;
          end
        end
      end
      
      STATE_WAIT_ACK: begin
        // Request already issued for current_pc
        fetch_req = 1'b0;
        fetch_addr = current_pc; 
        
        if (mem_ack && !stall) begin
           // Received late ack.
           // We can immediately switch back to REQ and issue for next_pc_comb
           // effectively restarting the stream
           fetch_req = 1'b1;
           fetch_addr = next_pc_comb;
           
           state_next = STATE_REQ;
        end
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
  
  logic [7:0] spec_1, op_1;
  logic [3:0] len_1;
  
  always_comb begin
    // Defaults
    spec_0 = 8'h0; op_0 = 8'h0; len_0 = 4'h0;
    spec_1 = 8'h0; op_1 = 8'h0; len_1 = 4'h0;
    
    // We always have 16 bytes starting at current_pc
    // So Inst 0 is at offset 0
    
    // --- Inst 0 ---
    spec_0 = current_block[0];
    op_0 = current_block[1]; // Opcode is always at byte 1
    
    len_0 = get_inst_length(op_0, spec_0);
      
    // --- Inst 1 ---
    // Only if Inst 0 is valid
    if (len_0 > 0) begin
      // Inst 1 starts at offset len_0
      if (len_0 < 15) begin
        spec_1 = current_block[len_0];
        op_1 = current_block[len_0 + 1];
        len_1 = get_inst_length(op_1, spec_1);
      end
    end
  end

  // ============================================================================
  // Output Generation
  // ============================================================================
  
  always_comb begin
    valid_0 = 1'b0;
    valid_1 = 1'b0;
    inst_data_0 = 72'h0;
    inst_data_1 = 72'h0;
    inst_len_0 = len_0;
    inst_len_1 = len_1;
    pc_0 = current_pc;
    pc_1 = current_pc;
    
    // Data is valid if we have an Ack in REQ or WAIT_ACK state
    // AND if we are not about to correct the PC (flush speculative fetch)
    if (((state == STATE_REQ && mem_ack) || (state == STATE_WAIT_ACK && mem_ack)) && !branch_taken && (current_pc == correct_pc)) begin
      // Inst 0
      if (len_0 > 0) begin
        valid_0 = 1'b1;
        pc_0 = current_pc;
        for (int i=0; i<9; i++) begin
           inst_data_0[(8-i)*8 +: 8] = current_block[i];
        end
        
        // Always attempt to issue 2nd instruction if it fits
        if (len_1 > 0 && (op_1 != OP_HLT)) begin
          if (({1'b0, len_0} + {1'b0, len_1}) <= 5'd16) begin
            valid_1 = 1'b1;
            pc_1 = current_pc + {28'h0, len_0};
            for (int i=0; i<9; i++) begin
               if (len_0 + i < 16) 
                 inst_data_1[(8-i)*8 +: 8] = current_block[len_0 + i];
            end
          end
        end
      end
    end
  end

  // ============================================================================
  // Sequential Logic (State & Data Update)
  // ============================================================================
  
  logic [4:0] total_len_seq;
  
  // PC Correction Logic
  logic [31:0] correct_pc;
  logic [4:0] consumed_len;
  
  always_comb begin
    consumed_len = 5'd0;
    if (consumed_count >= 2'd1) consumed_len = consumed_len + {1'b0, id_inst_len_0};
    if (consumed_count == 2'd2) consumed_len = consumed_len + {1'b0, id_inst_len_1};
    correct_pc = id_pc + {27'h0, consumed_len};
  end
  
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_INIT;
      current_pc <= 32'h0;
      
    end else if (branch_taken) begin
      state <= STATE_INIT;
      current_pc <= branch_target;
      
    end else if (!stall) begin
      state <= state_next;
      
      // PC Update Logic
      // Priority:
      // 1. Correction from Issue stage (if we mis-speculated or need to wait)
      // 2. Speculative advance (if we just fetched)
      
      if (id_valid && (current_pc != correct_pc)) begin
        // Correction needed: Snap PC to what ID expects next
        current_pc <= correct_pc;
        // Force re-fetch from corrected PC
        state <= STATE_REQ;
      end else if ((state == STATE_REQ && mem_ack) || (state == STATE_WAIT_ACK && mem_ack)) begin
        // Speculative advance
        // We successfully fetched THIS cycle.
        // We advance the PC register for the NEXT cycle.
        
        current_pc <= next_pc_comb;
      end
    end
  end

endmodule : fetch_unit
