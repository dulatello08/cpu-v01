//
// core_replay_tb.sv
// Testbench to reproduce instruction replay behavior
//
// This test forces a dual-issue split (dependency) and checks if a replay (branch) occurs.
//

`timescale 1ns/1ps

module core_replay_tb;
  import neocore_pkg::*;

  // Testbench signals
  logic        clk;
  logic        rst;
  
  // Unified memory interface signals
  logic [31:0]  mem_if_addr;
  logic         mem_if_req;
  logic [127:0] mem_if_rdata;
  logic         mem_if_ack;
  logic [31:0]  mem_data_addr;
  logic [31:0]  mem_data_wdata;
  logic [1:0]   mem_data_size;
  logic         mem_data_we;
  logic         mem_data_req;
  logic [31:0]  mem_data_rdata;
  logic         mem_data_ack;
  
  logic        halted;
  logic [31:0] current_pc;
  logic        dual_issue_active;
  
  // Unified memory instance
  unified_memory #(
    .MEM_SIZE_BYTES(65536),
    .ADDR_WIDTH(32)
  ) memory (
    .clk(clk),
    .rst(rst),
    .if_addr(mem_if_addr),
    .if_req(mem_if_req),
    .if_rdata(mem_if_rdata),
    .if_ack(mem_if_ack),
    .data_addr(mem_data_addr),
    .data_wdata(mem_data_wdata),
    .data_size(mem_data_size),
    .data_we(mem_data_we),
    .data_req(mem_data_req),
    .data_rdata(mem_data_rdata),
    .data_ack(mem_data_ack)
  );
  
  // Core instance
  core_top dut (
    .clk(clk),
    .rst(rst),
    .mem_if_addr(mem_if_addr),
    .mem_if_req(mem_if_req),
    .mem_if_rdata(mem_if_rdata),
    .mem_if_ack(mem_if_ack),
    .mem_data_addr(mem_data_addr),
    .mem_data_wdata(mem_data_wdata),
    .mem_data_size(mem_data_size),
    .mem_data_we(mem_data_we),
    .mem_data_req(mem_data_req),
    .mem_data_rdata(mem_data_rdata),
    .mem_data_ack(mem_data_ack),
    .halted(halted),
    .current_pc(current_pc),
    .dual_issue_active(dual_issue_active)
  );
  
  // Clock generation (100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Cycle counter
  int cycle_count;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end
  
  // VCD dump
  initial begin
    $dumpfile("core_replay_tb.vcd");
    $dumpvars(0, core_replay_tb);
  end
  
  // Test stimulus
  initial begin
    $display("========================================");
    $display("NeoCore Replay Reproduction Test");
    $display("========================================\n");
    
    // Initialize
    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
    
    // Initialize memory
    for (int i = 0; i < 256; i++) begin
      memory.mem[i] = 8'h00;
    end
    
    // Program:
    // 0x00: MOV R1, #0x0005       [00][09][01][00][05] (5 bytes)
    // 0x05: MOV R2, R1            [02][09][02][01]     (4 bytes) - Dependent!
    // 0x09: HLT                   [00][12]             (2 bytes)
    
    // 0x00: MOV R1, #0x0005
    memory.mem[32'h00] = 8'h00;
    memory.mem[32'h01] = 8'h09;
    memory.mem[32'h02] = 8'h01;
    memory.mem[32'h03] = 8'h00;
    memory.mem[32'h04] = 8'h05;
    
    // 0x05: MOV R2, R1
    memory.mem[32'h05] = 8'h02;
    memory.mem[32'h06] = 8'h09;
    memory.mem[32'h07] = 8'h02;
    memory.mem[32'h08] = 8'h01;
    
    // 0x09: HLT
    memory.mem[32'h09] = 8'h00;
    memory.mem[32'h0A] = 8'h12;
    
    // Run until halt
    wait(halted);
    repeat(5) @(posedge clk);
    $finish;
  end
  
  // Monitor Replay
  // In the current architecture, 'branch_taken' is asserted during replay.
  // We want to see this happen now, and NOT happen after the fix.
  always @(posedge clk) begin
    if (!rst) begin
      // Access internal signal via hierarchy
      // Note: This relies on the internal name 'real_branch_taken' or 'replay_inst1' in core_top
      // Since we can't easily access internal signals in all simulators without setup,
      // we'll look at the behavior: PC jumping back or staying same when it should move.
      
      // Better yet, let's look at the 'replay_inst1' signal if possible, or infer it.
      // In core_top.sv: assign replay_inst1 = decode_valid_1 && !issue_inst1 && !branch_taken;
      
      // We will print the internal state if the simulator allows, otherwise we rely on visual inspection or
      // adding a spy signal. For this test, we'll just print the PC trace.
      
      $display("Cycle %3d: PC=0x%08h Valid0=%b Valid1=%b Issue0=%b Issue1=%b Dual=%b Consumed=%d", 
               cycle_count, current_pc, 
               dut.decode_valid_0, dut.decode_valid_1,
               dut.issue_inst0, dut.issue_inst1, dut.dual_issue, dut.consumed_count);
               
      // Check for correction
      // If we see Consumed=1 when Valid0=1 and Valid1=1, we expect PC to be corrected next cycle.
      if (dut.decode_valid_0 && dut.decode_valid_1 && dut.consumed_count == 1) begin
         $display(">>> PARTIAL CONSUMPTION DETECTED (Split Issue) <<<");
      end
    end
  end

endmodule
