//
// ib_queue.sv
// NeoCore 16x32 CPU - Instruction Buffer (IB) Queue
//
// Decouples fetch from decode by buffering up to 6 instructions.
// Accepts up to two instructions per cycle and dequeues up to two per cycle.
//

module ib_queue
  import neocore_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  logic        flush,
  input  logic        stall,
  input  logic        halted,

  input  if_id_t      in0,
  input  if_id_t      in1,
  input  logic [1:0]  consume_count,

  output logic [1:0]  accept_count,
  output if_id_t      out0,
  output if_id_t      out1,
  output logic [2:0]  count
);

  localparam int IB_DEPTH = 6;

  logic        ib_valid[IB_DEPTH];
  logic [31:0] ib_pc[IB_DEPTH];
  logic [71:0] ib_inst_data[IB_DEPTH];
  logic [3:0]  ib_inst_len[IB_DEPTH];

  logic        ib_valid_next[IB_DEPTH];
  logic [31:0] ib_pc_next[IB_DEPTH];
  logic [71:0] ib_inst_data_next[IB_DEPTH];
  logic [3:0]  ib_inst_len_next[IB_DEPTH];

  logic [1:0]  ib_need_slots;
  logic [2:0]  ib_free_slots;
  logic        ib_can_accept;
  logic [1:0]  ib_deq_req;
  logic [1:0]  ib_deq_count;
  logic [2:0]  ib_count_after_deq;
  logic [2:0]  ib_count_next;

  always_comb begin
    ib_need_slots = {1'b0, in0.valid} + {1'b0, in1.valid};
    ib_free_slots = IB_DEPTH[2:0] - count;
    ib_can_accept = !flush && !halted && (ib_need_slots <= ib_free_slots);
    accept_count = ib_can_accept ? ib_need_slots : 2'd0;

    ib_deq_req = (!stall && !flush) ? consume_count : 2'd0;
    if (count == 0) begin
      ib_deq_count = 2'd0;
    end else if ((count == 1) && (ib_deq_req == 2'd2)) begin
      ib_deq_count = 2'd1;
    end else begin
      ib_deq_count = ib_deq_req;
    end

    ib_count_after_deq = count - ib_deq_count;
    ib_count_next = ib_count_after_deq + accept_count;
  end

  always_comb begin
    // Default cleared state (prevents latch inference and keeps empty slots clean)
    for (int i = 0; i < IB_DEPTH; i++) begin
      ib_valid_next[i] = 1'b0;
      ib_pc_next[i] = 32'h0;
      ib_inst_data_next[i] = 72'h0;
      ib_inst_len_next[i] = 4'h0;
    end

    // Dequeue: explicit 0/1/2-entry shift with fixed-index moves.
    unique case (ib_deq_count)
      2'd0: begin
        ib_valid_next[0] = ib_valid[0]; ib_pc_next[0] = ib_pc[0];
        ib_inst_data_next[0] = ib_inst_data[0]; ib_inst_len_next[0] = ib_inst_len[0];
        ib_valid_next[1] = ib_valid[1]; ib_pc_next[1] = ib_pc[1];
        ib_inst_data_next[1] = ib_inst_data[1]; ib_inst_len_next[1] = ib_inst_len[1];
        ib_valid_next[2] = ib_valid[2]; ib_pc_next[2] = ib_pc[2];
        ib_inst_data_next[2] = ib_inst_data[2]; ib_inst_len_next[2] = ib_inst_len[2];
        ib_valid_next[3] = ib_valid[3]; ib_pc_next[3] = ib_pc[3];
        ib_inst_data_next[3] = ib_inst_data[3]; ib_inst_len_next[3] = ib_inst_len[3];
        ib_valid_next[4] = ib_valid[4]; ib_pc_next[4] = ib_pc[4];
        ib_inst_data_next[4] = ib_inst_data[4]; ib_inst_len_next[4] = ib_inst_len[4];
        ib_valid_next[5] = ib_valid[5]; ib_pc_next[5] = ib_pc[5];
        ib_inst_data_next[5] = ib_inst_data[5]; ib_inst_len_next[5] = ib_inst_len[5];
      end
      2'd1: begin
        ib_valid_next[0] = ib_valid[1]; ib_pc_next[0] = ib_pc[1];
        ib_inst_data_next[0] = ib_inst_data[1]; ib_inst_len_next[0] = ib_inst_len[1];
        ib_valid_next[1] = ib_valid[2]; ib_pc_next[1] = ib_pc[2];
        ib_inst_data_next[1] = ib_inst_data[2]; ib_inst_len_next[1] = ib_inst_len[2];
        ib_valid_next[2] = ib_valid[3]; ib_pc_next[2] = ib_pc[3];
        ib_inst_data_next[2] = ib_inst_data[3]; ib_inst_len_next[2] = ib_inst_len[3];
        ib_valid_next[3] = ib_valid[4]; ib_pc_next[3] = ib_pc[4];
        ib_inst_data_next[3] = ib_inst_data[4]; ib_inst_len_next[3] = ib_inst_len[4];
        ib_valid_next[4] = ib_valid[5]; ib_pc_next[4] = ib_pc[5];
        ib_inst_data_next[4] = ib_inst_data[5]; ib_inst_len_next[4] = ib_inst_len[5];
      end
      default: begin // Treat all non-zero/non-one as deq=2
        ib_valid_next[0] = ib_valid[2]; ib_pc_next[0] = ib_pc[2];
        ib_inst_data_next[0] = ib_inst_data[2]; ib_inst_len_next[0] = ib_inst_len[2];
        ib_valid_next[1] = ib_valid[3]; ib_pc_next[1] = ib_pc[3];
        ib_inst_data_next[1] = ib_inst_data[3]; ib_inst_len_next[1] = ib_inst_len[3];
        ib_valid_next[2] = ib_valid[4]; ib_pc_next[2] = ib_pc[4];
        ib_inst_data_next[2] = ib_inst_data[4]; ib_inst_len_next[2] = ib_inst_len[4];
        ib_valid_next[3] = ib_valid[5]; ib_pc_next[3] = ib_pc[5];
        ib_inst_data_next[3] = ib_inst_data[5]; ib_inst_len_next[3] = ib_inst_len[5];
      end
    endcase

    // Enqueue: explicit tail slot mapping.
    if (accept_count >= 2'd1) begin
      unique case (ib_count_after_deq)
        3'd0: begin
          ib_valid_next[0] = in0.valid;
          ib_pc_next[0] = in0.pc;
          ib_inst_data_next[0] = in0.inst_data;
          ib_inst_len_next[0] = in0.inst_len;
        end
        3'd1: begin
          ib_valid_next[1] = in0.valid;
          ib_pc_next[1] = in0.pc;
          ib_inst_data_next[1] = in0.inst_data;
          ib_inst_len_next[1] = in0.inst_len;
        end
        3'd2: begin
          ib_valid_next[2] = in0.valid;
          ib_pc_next[2] = in0.pc;
          ib_inst_data_next[2] = in0.inst_data;
          ib_inst_len_next[2] = in0.inst_len;
        end
        3'd3: begin
          ib_valid_next[3] = in0.valid;
          ib_pc_next[3] = in0.pc;
          ib_inst_data_next[3] = in0.inst_data;
          ib_inst_len_next[3] = in0.inst_len;
        end
        3'd4: begin
          ib_valid_next[4] = in0.valid;
          ib_pc_next[4] = in0.pc;
          ib_inst_data_next[4] = in0.inst_data;
          ib_inst_len_next[4] = in0.inst_len;
        end
        3'd5: begin
          ib_valid_next[5] = in0.valid;
          ib_pc_next[5] = in0.pc;
          ib_inst_data_next[5] = in0.inst_data;
          ib_inst_len_next[5] = in0.inst_len;
        end
        default: ;
      endcase
    end

    if (accept_count == 2'd2) begin
      unique case (ib_count_after_deq)
        3'd0: begin
          ib_valid_next[1] = in1.valid;
          ib_pc_next[1] = in1.pc;
          ib_inst_data_next[1] = in1.inst_data;
          ib_inst_len_next[1] = in1.inst_len;
        end
        3'd1: begin
          ib_valid_next[2] = in1.valid;
          ib_pc_next[2] = in1.pc;
          ib_inst_data_next[2] = in1.inst_data;
          ib_inst_len_next[2] = in1.inst_len;
        end
        3'd2: begin
          ib_valid_next[3] = in1.valid;
          ib_pc_next[3] = in1.pc;
          ib_inst_data_next[3] = in1.inst_data;
          ib_inst_len_next[3] = in1.inst_len;
        end
        3'd3: begin
          ib_valid_next[4] = in1.valid;
          ib_pc_next[4] = in1.pc;
          ib_inst_data_next[4] = in1.inst_data;
          ib_inst_len_next[4] = in1.inst_len;
        end
        3'd4: begin
          ib_valid_next[5] = in1.valid;
          ib_pc_next[5] = in1.pc;
          ib_inst_data_next[5] = in1.inst_data;
          ib_inst_len_next[5] = in1.inst_len;
        end
        default: ;
      endcase
    end

    // Keep valid bits clamped to the computed occupancy.
    unique case (ib_count_next)
      3'd0: begin
        ib_valid_next[0] = 1'b0;
        ib_valid_next[1] = 1'b0;
        ib_valid_next[2] = 1'b0;
        ib_valid_next[3] = 1'b0;
        ib_valid_next[4] = 1'b0;
        ib_valid_next[5] = 1'b0;
      end
      3'd1: begin
        ib_valid_next[1] = 1'b0;
        ib_valid_next[2] = 1'b0;
        ib_valid_next[3] = 1'b0;
        ib_valid_next[4] = 1'b0;
        ib_valid_next[5] = 1'b0;
      end
      3'd2: begin
        ib_valid_next[2] = 1'b0;
        ib_valid_next[3] = 1'b0;
        ib_valid_next[4] = 1'b0;
        ib_valid_next[5] = 1'b0;
      end
      3'd3: begin
        ib_valid_next[3] = 1'b0;
        ib_valid_next[4] = 1'b0;
        ib_valid_next[5] = 1'b0;
      end
      3'd4: begin
        ib_valid_next[4] = 1'b0;
        ib_valid_next[5] = 1'b0;
      end
      3'd5: begin
        ib_valid_next[5] = 1'b0;
      end
      default: ; // 6 entries valid
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst || flush) begin
      count <= '0;
      for (int i = 0; i < IB_DEPTH; i++) begin
        ib_valid[i] <= 1'b0;
      end
    end else begin
      for (int i = 0; i < IB_DEPTH; i++) begin
        ib_valid[i] <= ib_valid_next[i];
        ib_pc[i] <= ib_pc_next[i];
        ib_inst_data[i] <= ib_inst_data_next[i];
        ib_inst_len[i] <= ib_inst_len_next[i];
      end
      count <= ib_count_next;
    end
  end

  always_comb begin
    out0.valid = ib_valid[0];
    out0.pc = ib_pc[0];
    out0.inst_data = ib_inst_data[0];
    out0.inst_len = ib_inst_len[0];

    out1.valid = ib_valid[1];
    out1.pc = ib_pc[1];
    out1.inst_data = ib_inst_data[1];
    out1.inst_len = ib_inst_len[1];
    if (count == 0) begin
      out0.valid = 1'b0;
    end
    if (count <= 1) begin
      out1.valid = 1'b0;
    end
  end

endmodule : ib_queue
