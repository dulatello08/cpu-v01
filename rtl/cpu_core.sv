//
// cpu_core.sv
// NeoCore 16x32 CPU - CPU Core Implementation
//
// Integrates all pipeline stages for a dual-issue, 6-stage pipelined CPU.
// Implements hazard detection, forwarding, and branch handling.
//
// Von Neumann Architecture:
//   - Single unified memory for instructions and data
//   - Big-endian byte ordering
//   - 128-bit instruction fetch port (16 bytes per cycle)
//   - 32-bit data access port
//
// Pipeline stages: IF -> IB -> ID -> EX -> MEM -> WB
// Dual-issue: Up to 2 instructions can be issued per cycle.
//

module cpu_core
  import neocore_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  
  // Unified memory interface - Instruction fetch port
  output logic [31:0]  mem_if_addr,
  output logic         mem_if_req,
  input  logic [127:0] mem_if_rdata,   // 16 bytes for variable-length instructions
  input  logic         mem_if_ack,
  
  // Unified memory interface - Data access port
  output logic [31:0] mem_data_addr,
  output logic [31:0] mem_data_wdata,
  output logic [1:0]  mem_data_size,
  output logic        mem_data_we,
  output logic        mem_data_req,
  input  logic [31:0] mem_data_rdata,
  input  logic        mem_data_ack,
  
  // Status signals
  output logic        halted,
  output logic [31:0] current_pc,
  output logic        dual_issue_active
);

  // ==========================================================================
  // CPU State Registers
  // ==========================================================================
  
  logic        z_flag, v_flag;
  logic        z_flag_next, v_flag_next;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      z_flag <= 1'b0;
      v_flag <= 1'b0;
    end else begin
      if (wb_z_flag_update) z_flag <= wb_z_flag_value;
      if (wb_v_flag_update) v_flag <= wb_v_flag_value;
    end
  end
  
  // ==========================================================================
  // Pipeline Control Signals
  // ==========================================================================
  
  logic stall_pipeline;
  logic stall_frontend;
  logic [1:0] consumed_count; // Forward declaration
  logic flush_if, flush_id, flush_ex;
  logic branch_taken;
  logic [31:0] branch_target;
  
  // ==========================================================================
  // Fetch Stage
  // ==========================================================================
  
  logic [71:0]  fetch_inst_data_0;  // 9 bytes max (padded to 72 bits)
  logic [3:0]   fetch_inst_len_0;
  logic [31:0]  fetch_pc_0;
  logic         fetch_valid_0;
  
  logic [71:0]  fetch_inst_data_1;  // 9 bytes max (padded to 72 bits)
  logic [3:0]   fetch_inst_len_1;
  logic [31:0]  fetch_pc_1;
  logic         fetch_valid_1;

  // IB (Instruction Buffer) Stage
  localparam int IB_DEPTH = 6;
  localparam int IB_COUNT_W = $clog2(IB_DEPTH + 1);
  
  logic [IB_COUNT_W-1:0] ib_count;
  
  if_id_t ib_out_0, ib_out_1;
  if_id_t ib_in_0, ib_in_1;
  logic [1:0] accept_count;
  
  // Combined Branch Control
  logic        real_branch_taken;
  logic [31:0] real_branch_target;
  
  assign real_branch_taken = branch_taken;
  assign real_branch_target = branch_target;

  fetch_unit fetch (
    .clk(clk),
    .rst(rst),
    .branch_taken(real_branch_taken),
    .branch_target(real_branch_target),
    .mem_addr(mem_if_addr),
    .mem_req(mem_if_req),
    .mem_rdata(mem_if_rdata),
    .mem_ack(mem_if_ack),
    .inst_data_0(fetch_inst_data_0),
    .inst_len_0(fetch_inst_len_0),
    .pc_0(fetch_pc_0),
    .valid_0(fetch_valid_0),
    .inst_data_1(fetch_inst_data_1),
    .inst_len_1(fetch_inst_len_1),
    .pc_1(fetch_pc_1),
    .valid_1(fetch_valid_1),
    .accept_count(accept_count)
  );
  
  // ==========================================================================
  // IB Stage (Instruction Buffer)
  // ==========================================================================
  
  always_comb begin
    ib_in_0.valid = fetch_valid_0;
    ib_in_0.pc = fetch_pc_0;
    ib_in_0.inst_data = fetch_inst_data_0;
    ib_in_0.inst_len = fetch_inst_len_0;
    
    ib_in_1.valid = fetch_valid_1;
    ib_in_1.pc = fetch_pc_1;
    ib_in_1.inst_data = fetch_inst_data_1;
    ib_in_1.inst_len = fetch_inst_len_1;
  end

  ib_queue ibq (
    .clk(clk),
    .rst(rst),
    .flush(branch_taken),
    .stall(stall_frontend),
    .halted(halted),
    .in0(ib_in_0),
    .in1(ib_in_1),
    .consume_count(consumed_count),
    .accept_count(accept_count),
    .out0(ib_out_0),
    .out1(ib_out_1),
    .count(ib_count)
  );
  
  // ==========================================================================
  // Decode Stage
  // ==========================================================================
  
  // Decode outputs for instruction 0
  logic        decode_valid_0;
  opcode_e     decode_opcode_0;
  logic [7:0]  decode_specifier_0;
  itype_e      decode_itype_0;
  alu_op_e     decode_alu_op_0;
  logic [3:0]  decode_rs1_addr_0, decode_rs2_addr_0;
  logic [3:0]  decode_rd_addr_0, decode_rd2_addr_0;
  logic [31:0] decode_immediate_0, decode_mem_addr_0, decode_branch_target_0;
  logic        decode_mov_byte_hi_0;
  logic        decode_rd_we_0, decode_rd2_we_0;
  logic        decode_mem_read_0, decode_mem_write_0;
  mem_size_e   decode_mem_size_0;
  logic        decode_is_branch_0, decode_is_jsr_0, decode_is_rts_0, decode_is_halt_0;
  
  decode_unit decode_0 (
    .clk(clk),
    .rst(rst),
    .inst_data(ib_out_0.inst_data),
    .inst_len(ib_out_0.inst_len),
    .pc(ib_out_0.pc),
    .valid_in(ib_out_0.valid),
    .valid_out(decode_valid_0),
    .opcode(decode_opcode_0),
    .specifier(decode_specifier_0),
    .itype(decode_itype_0),
    .alu_op(decode_alu_op_0),
    .rs1_addr(decode_rs1_addr_0),
    .rs2_addr(decode_rs2_addr_0),
    .rd_addr(decode_rd_addr_0),
    .rd2_addr(decode_rd2_addr_0),
    .immediate(decode_immediate_0),
    .mem_addr(decode_mem_addr_0),
    .branch_target(decode_branch_target_0),
    .mov_byte_hi(decode_mov_byte_hi_0),
    .rd_we(decode_rd_we_0),
    .rd2_we(decode_rd2_we_0),
    .mem_read(decode_mem_read_0),
    .mem_write(decode_mem_write_0),
    .mem_size(decode_mem_size_0),
    .is_branch(decode_is_branch_0),
    .is_jsr(decode_is_jsr_0),
    .is_rts(decode_is_rts_0),
    .is_halt(decode_is_halt_0)
  );
  
  // Decode outputs for instruction 1
  logic        decode_valid_1;
  opcode_e     decode_opcode_1;
  logic [7:0]  decode_specifier_1;
  itype_e      decode_itype_1;
  alu_op_e     decode_alu_op_1;
  logic [3:0]  decode_rs1_addr_1, decode_rs2_addr_1;
  logic [3:0]  decode_rd_addr_1, decode_rd2_addr_1;
  logic [31:0] decode_immediate_1, decode_mem_addr_1, decode_branch_target_1;
  logic        decode_mov_byte_hi_1;
  logic        decode_rd_we_1, decode_rd2_we_1;
  logic        decode_mem_read_1, decode_mem_write_1;
  mem_size_e   decode_mem_size_1;
  logic        decode_is_branch_1, decode_is_jsr_1, decode_is_rts_1, decode_is_halt_1;
  
  decode_unit decode_1 (
    .clk(clk),
    .rst(rst),
    .inst_data(ib_out_1.inst_data),
    .inst_len(ib_out_1.inst_len),
    .pc(ib_out_1.pc),
    .valid_in(ib_out_1.valid),
    .valid_out(decode_valid_1),
    .opcode(decode_opcode_1),
    .specifier(decode_specifier_1),
    .itype(decode_itype_1),
    .alu_op(decode_alu_op_1),
    .rs1_addr(decode_rs1_addr_1),
    .rs2_addr(decode_rs2_addr_1),
    .rd_addr(decode_rd_addr_1),
    .rd2_addr(decode_rd2_addr_1),
    .immediate(decode_immediate_1),
    .mem_addr(decode_mem_addr_1),
    .branch_target(decode_branch_target_1),
    .mov_byte_hi(decode_mov_byte_hi_1),
    .rd_we(decode_rd_we_1),
    .rd2_we(decode_rd2_we_1),
    .mem_read(decode_mem_read_1),
    .mem_write(decode_mem_write_1),
    .mem_size(decode_mem_size_1),
    .is_branch(decode_is_branch_1),
    .is_jsr(decode_is_jsr_1),
    .is_rts(decode_is_rts_1),
    .is_halt(decode_is_halt_1)
  );
  
  // ==========================================================================
  // Issue Unit (Dual-Issue Control)
  // ==========================================================================
  
  logic issue_inst0, issue_inst1, dual_issue;
  
  issue_unit issue (
    .clk(clk),
    .rst(rst),
    .inst0_valid(decode_valid_0),
    .inst0_type(decode_itype_0),
    .inst0_mem_read(decode_mem_read_0),
    .inst0_mem_write(decode_mem_write_0),
    .inst0_is_branch(decode_is_branch_0),
    .inst0_is_halt(decode_is_halt_0),
    .inst0_rd_addr(decode_rd_addr_0),
    .inst0_rd_we(decode_rd_we_0),
    .inst0_rd2_addr(decode_rd2_addr_0),
    .inst0_rd2_we(decode_rd2_we_0),
    .inst1_valid(decode_valid_1),
    .inst1_type(decode_itype_1),
    .inst1_mem_read(decode_mem_read_1),
    .inst1_mem_write(decode_mem_write_1),
    .inst1_is_branch(decode_is_branch_1),
    .inst1_is_halt(decode_is_halt_1),
    .inst1_rs1_addr(decode_rs1_addr_1),
    .inst1_rs2_addr(decode_rs2_addr_1),
    .inst1_rd_addr(decode_rd_addr_1),
    .inst1_rd_we(decode_rd_we_1),
    .inst1_rd2_addr(decode_rd2_addr_1),
    .inst1_rd2_we(decode_rd2_we_1),
    .issue_inst0(issue_inst0),
    .issue_inst1(issue_inst1),
    .dual_issue(dual_issue),
    .consumed_count(consumed_count)
  );

  assign dual_issue_active = dual_issue;
  
  // ==========================================================================
  // Register File
  // ==========================================================================
  
  logic [15:0] rf_rs1_data_0, rf_rs2_data_0;
  logic [15:0] rf_rs1_data_1, rf_rs2_data_1;
  logic [3:0]  rf_wr_addr_0, rf_wr_addr_1;
  logic [15:0] rf_wr_data_0, rf_wr_data_1;
  logic        rf_wr_en_0, rf_wr_en_1;
  
  register_file regfile (
    .clk(clk),
    .rst(rst),
    .rs1_addr_0(decode_rs1_addr_0),
    .rs2_addr_0(decode_rs2_addr_0),
    .rs1_data_0(rf_rs1_data_0),
    .rs2_data_0(rf_rs2_data_0),
    .rs1_addr_1(decode_rs1_addr_1),
    .rs2_addr_1(decode_rs2_addr_1),
    .rs1_data_1(rf_rs1_data_1),
    .rs2_data_1(rf_rs2_data_1),
    .rd_addr_0(rf_wr_addr_0),
    .rd_data_0(rf_wr_data_0),
    .rd_we_0(rf_wr_en_0),
    .rd_addr_1(rf_wr_addr_1),
    .rd_data_1(rf_wr_data_1),
    .rd_we_1(rf_wr_en_1)
  );
  
  // ==========================================================================
  // ID/EX Pipeline Register
  // ==========================================================================
  
  id_ex_t id_ex_in_0, id_ex_out_0;
  id_ex_t id_ex_in_1, id_ex_out_1;
  
  always_comb begin
    // Defaults: bubble (prevents unissued instructions from triggering side effects)
    id_ex_in_0.valid = 1'b0;
    id_ex_in_0.pc = 32'h0;
    id_ex_in_0.opcode = OP_NOP;
    id_ex_in_0.specifier = 8'h00;
    id_ex_in_0.itype = ITYPE_CTRL;
    id_ex_in_0.alu_op = ALU_NOP;
    id_ex_in_0.rs1_addr = 4'h0;
    id_ex_in_0.rs2_addr = 4'h0;
    id_ex_in_0.rs1_data = 16'h0;
    id_ex_in_0.rs2_data = 16'h0;
    id_ex_in_0.immediate = 32'h0;
    id_ex_in_0.mov_byte_hi = 1'b0;
    id_ex_in_0.rd_addr = 4'h0;
    id_ex_in_0.rd2_addr = 4'h0;
    id_ex_in_0.rd_we = 1'b0;
    id_ex_in_0.rd2_we = 1'b0;
    id_ex_in_0.mem_read = 1'b0;
    id_ex_in_0.mem_write = 1'b0;
    id_ex_in_0.mem_size = MEM_HALF;
    id_ex_in_0.mem_addr = 32'h0;
    id_ex_in_0.is_branch = 1'b0;
    id_ex_in_0.is_jsr = 1'b0;
    id_ex_in_0.is_rts = 1'b0;
    id_ex_in_0.is_halt = 1'b0;
    
    id_ex_in_1.valid = 1'b0;
    id_ex_in_1.pc = 32'h0;
    id_ex_in_1.opcode = OP_NOP;
    id_ex_in_1.specifier = 8'h00;
    id_ex_in_1.itype = ITYPE_CTRL;
    id_ex_in_1.alu_op = ALU_NOP;
    id_ex_in_1.rs1_addr = 4'h0;
    id_ex_in_1.rs2_addr = 4'h0;
    id_ex_in_1.rs1_data = 16'h0;
    id_ex_in_1.rs2_data = 16'h0;
    id_ex_in_1.immediate = 32'h0;
    id_ex_in_1.mov_byte_hi = 1'b0;
    id_ex_in_1.rd_addr = 4'h0;
    id_ex_in_1.rd2_addr = 4'h0;
    id_ex_in_1.rd_we = 1'b0;
    id_ex_in_1.rd2_we = 1'b0;
    id_ex_in_1.mem_read = 1'b0;
    id_ex_in_1.mem_write = 1'b0;
    id_ex_in_1.mem_size = MEM_HALF;
    id_ex_in_1.mem_addr = 32'h0;
    id_ex_in_1.is_branch = 1'b0;
    id_ex_in_1.is_jsr = 1'b0;
    id_ex_in_1.is_rts = 1'b0;
    id_ex_in_1.is_halt = 1'b0;

    // Instruction 0
    if (issue_inst0) begin
      id_ex_in_0.valid = 1'b1;
      id_ex_in_0.pc = ib_out_0.pc;
      id_ex_in_0.opcode = decode_opcode_0;
      id_ex_in_0.specifier = decode_specifier_0;
      id_ex_in_0.itype = decode_itype_0;
      id_ex_in_0.alu_op = decode_alu_op_0;
      id_ex_in_0.rs1_addr = decode_rs1_addr_0;
      id_ex_in_0.rs2_addr = decode_rs2_addr_0;
      id_ex_in_0.rs1_data = rf_rs1_data_0;
      id_ex_in_0.rs2_data = rf_rs2_data_0;
      id_ex_in_0.immediate = decode_immediate_0;
      id_ex_in_0.mov_byte_hi = decode_mov_byte_hi_0;
      id_ex_in_0.rd_addr = decode_rd_addr_0;
      id_ex_in_0.rd2_addr = decode_rd2_addr_0;
      id_ex_in_0.rd_we = decode_rd_we_0;
      id_ex_in_0.rd2_we = decode_rd2_we_0;
      id_ex_in_0.mem_read = decode_mem_read_0;
      id_ex_in_0.mem_write = decode_mem_write_0;
      id_ex_in_0.mem_size = decode_mem_size_0;
      id_ex_in_0.mem_addr = decode_mem_addr_0;
      id_ex_in_0.is_branch = decode_is_branch_0;
      id_ex_in_0.is_jsr = decode_is_jsr_0;
      id_ex_in_0.is_rts = decode_is_rts_0;
      id_ex_in_0.is_halt = decode_is_halt_0;
    end
    
    // Instruction 1
    if (issue_inst1) begin
      id_ex_in_1.valid = 1'b1;
      id_ex_in_1.pc = ib_out_1.pc;
      id_ex_in_1.opcode = decode_opcode_1;
      id_ex_in_1.specifier = decode_specifier_1;
      id_ex_in_1.itype = decode_itype_1;
      id_ex_in_1.alu_op = decode_alu_op_1;
      id_ex_in_1.rs1_addr = decode_rs1_addr_1;
      id_ex_in_1.rs2_addr = decode_rs2_addr_1;
      id_ex_in_1.rs1_data = rf_rs1_data_1;
      id_ex_in_1.rs2_data = rf_rs2_data_1;
      id_ex_in_1.immediate = decode_immediate_1;
      id_ex_in_1.mov_byte_hi = decode_mov_byte_hi_1;
      id_ex_in_1.rd_addr = decode_rd_addr_1;
      id_ex_in_1.rd2_addr = decode_rd2_addr_1;
      id_ex_in_1.rd_we = decode_rd_we_1;
      id_ex_in_1.rd2_we = decode_rd2_we_1;
      id_ex_in_1.mem_read = decode_mem_read_1;
      id_ex_in_1.mem_write = decode_mem_write_1;
      id_ex_in_1.mem_size = decode_mem_size_1;
      id_ex_in_1.mem_addr = decode_mem_addr_1;
      id_ex_in_1.is_branch = decode_is_branch_1;
      id_ex_in_1.is_jsr = decode_is_jsr_1;
      id_ex_in_1.is_rts = decode_is_rts_1;
      id_ex_in_1.is_halt = decode_is_halt_1;
    end
  end
  
  id_ex_reg id_ex_reg_0 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(flush_ex || branch_taken),
    .data_in(id_ex_in_0),
    .data_out(id_ex_out_0)
  );
  
  id_ex_reg id_ex_reg_1 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(flush_ex || branch_taken),
    .data_in(id_ex_in_1),
    .data_out(id_ex_out_1)
  );
  
  // ==========================================================================
  // Hazard Detection Unit
  // ==========================================================================
  
  logic [2:0] forward_a_0, forward_b_0;
  logic [2:0] forward_a_1, forward_b_1;
  logic hazard_stall;
  
  hazard_unit hazard (
    .clk(clk),
    .rst(rst),
    .id_rs1_addr_0(id_ex_out_0.rs1_addr),
    .id_rs2_addr_0(id_ex_out_0.rs2_addr),
    .id_valid_0(id_ex_out_0.valid),
    .id_rs1_addr_1(id_ex_out_1.rs1_addr),
    .id_rs2_addr_1(id_ex_out_1.rs2_addr),
    .id_valid_1(id_ex_out_1.valid),
    .fwd_ex_rd_addr_0(ex_mem_out_0.rd_addr),
    .fwd_ex_rd_we_0(ex_mem_out_0.rd_we),
    .fwd_ex_valid_0(ex_mem_out_0.valid),
    .fwd_ex_rd_addr_1(ex_mem_out_1.rd_addr),
    .fwd_ex_rd_we_1(ex_mem_out_1.rd_we),
    .fwd_ex_valid_1(ex_mem_out_1.valid),
    .id_stage_rs1_addr_0(decode_rs1_addr_0),
    .id_stage_rs2_addr_0(decode_rs2_addr_0),
    .id_stage_valid_0(decode_valid_0),
    .id_stage_rs1_addr_1(decode_rs1_addr_1),
    .id_stage_rs2_addr_1(decode_rs2_addr_1),
    .id_stage_valid_1(decode_valid_1),
    .ex_rd_addr_0(id_ex_out_0.rd_addr),
    .ex_rd_we_0(id_ex_out_0.rd_we),
    .ex_mem_read_0(id_ex_out_0.mem_read),
    .ex_rd_addr_1(id_ex_out_1.rd_addr),
    .ex_rd_we_1(id_ex_out_1.rd_we),
    .ex_mem_read_1(id_ex_out_1.mem_read),
    .ex_valid_0(id_ex_out_0.valid),
    .ex_valid_1(id_ex_out_1.valid),
    .mem_rd_addr_0(mem_wb_out_0.rd_addr),
    .mem_rd_we_0(mem_wb_out_0.rd_we),
    .mem_rd_addr_1(mem_wb_out_1.rd_addr),
    .mem_rd_we_1(mem_wb_out_1.rd_we),
    .mem_valid_0(mem_wb_out_0.valid),
    .mem_valid_1(mem_wb_out_1.valid),
    .wb_rd_addr_0(rf_wr_addr_0),
    .wb_rd_we_0(rf_wr_en_0),
    .wb_rd_addr_1(rf_wr_addr_1),
    .wb_rd_we_1(rf_wr_en_1),
    .wb_valid_0(1'b1),  // WB is always valid if address is being written
    .wb_valid_1(1'b1),
    .forward_a_0(forward_a_0),
    .forward_b_0(forward_b_0),
    .forward_a_1(forward_a_1),
    .forward_b_1(forward_b_1),
    .stall(hazard_stall),
    .flush_id(flush_id),
    .flush_ex(flush_ex)
  );
  
  // ==========================================================================
  // Execute Stage
  // ==========================================================================
  
  ex_mem_t ex_mem_in_0, ex_mem_in_1;
  
  execute_stage execute (
    .clk(clk),
    .rst(rst),
    .id_ex_0(id_ex_out_0),
    .id_ex_1(id_ex_out_1),
    .ex_fwd_data_0(ex_mem_out_0.alu_result[15:0]),  // FIX: Use pipeline register output
    .ex_fwd_data_1(ex_mem_out_1.alu_result[15:0]),  // FIX: Use pipeline register output
    .mem_fwd_data_0(mem_wb_out_0.wb_data),
    .mem_fwd_data_1(mem_wb_out_1.wb_data),
    .wb_fwd_data_0(rf_wr_data_0),
    .wb_fwd_data_1(rf_wr_data_1),
    .forward_a_0(forward_a_0),
    .forward_b_0(forward_b_0),
    .forward_a_1(forward_a_1),
    .forward_b_1(forward_b_1),
    .z_flag(z_flag),
    .v_flag(v_flag),
    .ex_mem_0(ex_mem_in_0),
    .ex_mem_1(ex_mem_in_1),
    .branch_taken(branch_taken),
    .branch_target(branch_target)
  );
  
  // ==========================================================================
  // EX/MEM Pipeline Register
  // ==========================================================================
  
  ex_mem_t ex_mem_out_0, ex_mem_out_1;
  
  ex_mem_reg ex_mem_reg_0 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(1'b0),
    .data_in(ex_mem_in_0),
    .data_out(ex_mem_out_0)
  );
  
  ex_mem_reg ex_mem_reg_1 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(1'b0),
    .data_in(ex_mem_in_1),
    .data_out(ex_mem_out_1)
  );
  
  // ==========================================================================
  // Memory Stage
  // ==========================================================================
  
  mem_wb_t mem_wb_in_0, mem_wb_in_1;
  logic mem_stall;
  
  memory_stage memory (
    .clk(clk),
    .rst(rst),
    .ex_mem_0(ex_mem_out_0),
    .ex_mem_1(ex_mem_out_1),
    .dmem_addr(mem_data_addr),
    .dmem_wdata(mem_data_wdata),
    .dmem_size(mem_data_size),
    .dmem_we(mem_data_we),
    .dmem_req(mem_data_req),
    .dmem_rdata(mem_data_rdata),
    .dmem_ack(mem_data_ack),
    .mem_wb_0(mem_wb_in_0),
    .mem_wb_1(mem_wb_in_1),
    .mem_stall(mem_stall)
  );
  
  // ==========================================================================
  // MEM/WB Pipeline Register
  // ==========================================================================
  
  mem_wb_t mem_wb_out_0, mem_wb_out_1;
  
  mem_wb_reg mem_wb_reg_0 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(1'b0),
    .data_in(mem_wb_in_0),
    .data_out(mem_wb_out_0)
  );
  
  mem_wb_reg mem_wb_reg_1 (
    .clk(clk),
    .rst(rst),
    .stall(stall_pipeline),
    .flush(1'b0),
    .data_in(mem_wb_in_1),
    .data_out(mem_wb_out_1)
  );
  
  // ==========================================================================
  // Write-Back Stage
  // ==========================================================================
  
  logic wb_z_flag_update, wb_v_flag_update;
  logic wb_z_flag_value, wb_v_flag_value;
  
  writeback_stage writeback (
    .clk(clk),
    .rst(rst),
    .mem_wb_0(mem_wb_out_0),
    .mem_wb_1(mem_wb_out_1),
    .rf_wr_addr_0(rf_wr_addr_0),
    .rf_wr_data_0(rf_wr_data_0),
    .rf_wr_en_0(rf_wr_en_0),
    .rf_wr_addr_1(rf_wr_addr_1),
    .rf_wr_data_1(rf_wr_data_1),
    .rf_wr_en_1(rf_wr_en_1),
    .z_flag_update(wb_z_flag_update),
    .z_flag_value(wb_z_flag_value),
    .v_flag_update(wb_v_flag_update),
    .v_flag_value(wb_v_flag_value),
    .halted(halted)
  );
  
  // ==========================================================================
  // Pipeline Stall Control
  // ==========================================================================
  
  // Detect HLT in pipeline to stop fetching new instructions
  // But allow pipeline to continue draining until HLT reaches WB
  logic halt_in_pipeline;
  assign halt_in_pipeline = (id_ex_out_0.valid && id_ex_out_0.is_halt) ||
                            (id_ex_out_1.valid && id_ex_out_1.is_halt) ||
                            (ex_mem_out_0.valid && ex_mem_out_0.is_halt) ||
                            (ex_mem_out_1.valid && ex_mem_out_1.is_halt);
  
  // Stall entire pipeline only for hazards, memory stalls, or once fully halted
  assign stall_frontend = hazard_stall || mem_stall || halted;
  assign stall_pipeline = mem_stall || halted;
  
  // ==========================================================================
  // Current PC Reporting
  // ==========================================================================
  
  // When halted or halt in pipeline, report PC of the halt instruction, not fetch PC
  // Find the halt instruction PC from the pipeline
  logic [31:0] halt_pc;
  always_comb begin
    if (mem_wb_out_0.valid && mem_wb_out_0.is_halt) begin
      halt_pc = mem_wb_out_0.pc;
    end else if (mem_wb_out_1.valid && mem_wb_out_1.is_halt) begin
      halt_pc = mem_wb_out_1.pc;
    end else if (ex_mem_out_0.valid && ex_mem_out_0.is_halt) begin
      halt_pc = ex_mem_out_0.pc;
    end else if (ex_mem_out_1.valid && ex_mem_out_1.is_halt) begin
      halt_pc = ex_mem_out_1.pc;
    end else if (id_ex_out_0.valid && id_ex_out_0.is_halt) begin
      halt_pc = id_ex_out_0.pc;
    end else if (id_ex_out_1.valid && id_ex_out_1.is_halt) begin
      halt_pc = id_ex_out_1.pc;
    end else begin
      halt_pc = fetch_pc_0;
    end
  end
  
  assign current_pc = (halt_in_pipeline || halted) ? halt_pc : fetch_pc_0;

endmodule : cpu_core
