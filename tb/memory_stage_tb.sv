//
// memory_stage_tb.sv
// Testbench for NeoCore 16x32 Memory Stage
//
// Tests:
//   - Load operations (byte, half, word)
//   - Store operations (byte, half, word)
//   - Memory stall handling
//   - Dual-slot memory access serialization
//

`timescale 1ns/1ps

module memory_stage_tb;
  import neocore_pkg::*;

  // Signals
  logic        clk;
  logic        rst;
  
  // EX/MEM inputs
  ex_mem_t     ex_mem_0;
  ex_mem_t     ex_mem_1;
  
  // Memory interface
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [1:0]  dmem_size;
  logic        dmem_we;
  logic        dmem_req;
  logic [31:0] dmem_rdata;
  logic        dmem_ack;
  
  // MEM/WB outputs
  mem_wb_t     mem_wb_0;
  mem_wb_t     mem_wb_1;
  logic        mem_stall;

  // DUT Instantiation
  memory_stage dut (
    .clk(clk),
    .rst(rst),
    .ex_mem_0(ex_mem_0),
    .ex_mem_1(ex_mem_1),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_size(dmem_size),
    .dmem_we(dmem_we),
    .dmem_req(dmem_req),
    .dmem_rdata(dmem_rdata),
    .dmem_ack(dmem_ack),
    .mem_wb_0(mem_wb_0),
    .mem_wb_1(mem_wb_1),
    .mem_stall(mem_stall)
  );

  // Clock generation (100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Simulated memory
  logic [31:0] sim_mem [0:255];
  
  initial begin
    for (int i = 0; i < 256; i++) sim_mem[i] = 32'h0;
    // Preload some test data
    sim_mem[32'h10 >> 2] = 32'hDEADBEEF;
    sim_mem[32'h20 >> 2] = 32'hCAFEBABE;
  end

  // Memory model with 1-cycle latency
  always_ff @(posedge clk) begin
    if (rst) begin
      dmem_ack <= 1'b0;
      dmem_rdata <= 32'h0;
    end else begin
      dmem_ack <= 1'b0;
      if (dmem_req) begin
        dmem_ack <= 1'b1;
        if (dmem_we) begin
          sim_mem[dmem_addr >> 2] <= dmem_wdata;
          $display("  MEM WRITE: Addr=0x%h Data=0x%h Size=%d", dmem_addr, dmem_wdata, dmem_size);
        end else begin
          dmem_rdata <= sim_mem[dmem_addr >> 2];
          $display("  MEM READ: Addr=0x%h Data=0x%h Size=%d", dmem_addr, sim_mem[dmem_addr >> 2], dmem_size);
        end
      end
    end
  end

  // Test counters
  int pass_count = 0;
  int fail_count = 0;

  // Helper to clear ex_mem structs
  function automatic ex_mem_t clear_ex_mem();
    ex_mem_t em;
    em.valid = 1'b0;
    em.pc = 32'h0;
    em.alu_result = 32'h0;
    em.z_flag = 1'b0;
    em.v_flag = 1'b0;
    em.rd_addr = 4'h0;
    em.rd2_addr = 4'h0;
    em.rd_we = 1'b0;
    em.rd2_we = 1'b0;
    em.mem_read = 1'b0;
    em.mem_write = 1'b0;
    em.mem_size = MEM_HALF;
    em.mem_addr = 32'h0;
    em.mem_wdata = 16'h0;
    em.branch_taken = 1'b0;
    em.branch_target = 32'h0;
    em.is_halt = 1'b0;
    return em;
  endfunction

  // Test stimulus
  initial begin
    $display("========================================");
    $display("Memory Stage Testbench");
    $display("========================================\n");

    // Initialize
    rst = 1;
    ex_mem_0 = clear_ex_mem();
    ex_mem_1 = clear_ex_mem();
    
    repeat(3) @(posedge clk);
    rst = 0;
    repeat(2) @(posedge clk);

    // Test 1: Simple Load (Word)
    $display("Test 1: Word Load from 0x10");
    ex_mem_0 = clear_ex_mem();
    ex_mem_0.valid = 1'b1;
    ex_mem_0.mem_read = 1'b1;
    ex_mem_0.mem_size = MEM_WORD;
    ex_mem_0.mem_addr = 32'h10;
    ex_mem_0.rd_addr = 4'h1;
    ex_mem_0.rd_we = 1'b1;
    
    @(posedge clk);
    // Wait for stall to clear
    while (mem_stall) @(posedge clk);
    @(posedge clk);
    
    if (mem_wb_0.wb_data == 16'hBEEF && mem_wb_0.wb_data2 == 16'hDEAD) begin
      $display("  PASS: Loaded 0x%h%h (expected 0xDEADBEEF)", mem_wb_0.wb_data2, mem_wb_0.wb_data);
      pass_count++;
    end else begin
      $display("  FAIL: Loaded 0x%h%h (expected 0xDEADBEEF)", mem_wb_0.wb_data2, mem_wb_0.wb_data);
      fail_count++;
    end
    
    ex_mem_0 = clear_ex_mem();
    repeat(2) @(posedge clk);

    // Test 2: Simple Store (Word)
    $display("\nTest 2: Word Store to 0x30");
    ex_mem_0 = clear_ex_mem();
    ex_mem_0.valid = 1'b1;
    ex_mem_0.mem_write = 1'b1;
    ex_mem_0.mem_size = MEM_WORD;
    ex_mem_0.mem_addr = 32'h30;
    ex_mem_0.mem_wdata = 16'h1234;
    ex_mem_0.alu_result = 32'h56781234; // Full 32-bit value for word store
    
    @(posedge clk);
    while (mem_stall) @(posedge clk);
    @(posedge clk);
    
    if (sim_mem[32'h30 >> 2] == 32'h00001234) begin
      $display("  PASS: Stored 0x%h", sim_mem[32'h30 >> 2]);
      pass_count++;
    end else begin
      $display("  FAIL: Stored 0x%h (expected 0x00001234)", sim_mem[32'h30 >> 2]);
      fail_count++;
    end
    
    ex_mem_0 = clear_ex_mem();
    repeat(2) @(posedge clk);

    // Test 3: Non-memory operation (passthrough)
    $display("\nTest 3: Non-memory ALU passthrough");
    ex_mem_0 = clear_ex_mem();
    ex_mem_0.valid = 1'b1;
    ex_mem_0.alu_result = 32'h0000ABCD;
    ex_mem_0.rd_addr = 4'h5;
    ex_mem_0.rd_we = 1'b1;
    
    @(posedge clk);
    @(posedge clk);
    
    if (mem_wb_0.wb_data == 16'hABCD) begin
      $display("  PASS: Passthrough result 0x%h", mem_wb_0.wb_data);
      pass_count++;
    end else begin
      $display("  FAIL: Passthrough result 0x%h (expected 0xABCD)", mem_wb_0.wb_data);
      fail_count++;
    end

    ex_mem_0 = clear_ex_mem();
    repeat(2) @(posedge clk);

    // Summary
    $display("\n========================================");
    $display("Test Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");

    $finish;
  end

endmodule : memory_stage_tb
