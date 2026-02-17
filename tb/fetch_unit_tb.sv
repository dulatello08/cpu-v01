//
// fetch_unit_tb.sv
// Testbench for Refactored Fetch Unit
//

module fetch_unit_tb;
  import neocore_pkg::*;

  // Signals
  logic        clk;
  logic        rst;
  logic        branch_taken;
  logic [31:0] branch_target;
  
  logic [31:0] mem_addr;
  logic        mem_req;
  logic [127:0] mem_rdata;
  logic        mem_ack;
  
  logic [71:0] inst_data_0;
  logic [3:0]   inst_len_0;
  logic [31:0]  pc_0;
  logic         valid_0;
  
  logic [71:0] inst_data_1;
  logic [3:0]   inst_len_1;
  logic [31:0]  pc_1;
  logic         valid_1;
  
  // Feedback from IB stage (acceptance)
  logic [1:0]   accept_count;

  // DUT Instantiation
  fetch_unit dut (
    .clk(clk),
    .rst(rst),
    .branch_taken(branch_taken),
    .branch_target(branch_target),
    .mem_addr(mem_addr),
    .mem_req(mem_req),
    .mem_rdata(mem_rdata),
    .mem_ack(mem_ack),
    .inst_data_0(inst_data_0),
    .inst_len_0(inst_len_0),
    .pc_0(pc_0),
    .valid_0(valid_0),
    .inst_data_1(inst_data_1),
    .inst_len_1(inst_len_1),
    .pc_1(pc_1),
    .valid_1(valid_1),
    .accept_count(accept_count)
  );

  // Clock Generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Memory Simulation
  // Byte array memory model to support unaligned access
  logic [7:0] test_mem [0:1023];
  
  initial begin
    // Initialize memory with 0s
    for (int i=0; i<1024; i++) test_mem[i] = 8'h00;
    
    // 00-0F: 8 NOPs (2 bytes each)
    // Already 0s
    
    // 10-1F: 
    // 10: ADD r1, r2, r3 (5 bytes) -> Spec=00, Op=01 (ADD) -> 00 01 01 02 03
    test_mem[32'h10] = 8'h00; test_mem[32'h11] = 8'h01; test_mem[32'h12] = 8'h01; test_mem[32'h13] = 8'h02; test_mem[32'h14] = 8'h03;
    
    // 15: ADD r4, r5, r6 (5 bytes) -> Spec=00, Op=01 (ADD) -> 00 01 04 05 06
    test_mem[32'h15] = 8'h00; test_mem[32'h16] = 8'h01; test_mem[32'h17] = 8'h04; test_mem[32'h18] = 8'h05; test_mem[32'h19] = 8'h06;
    
    // 1A: NOP (2 bytes) -> 00 00
    // 1C: NOP (2 bytes) -> 00 00
    // 1E: NOP (2 bytes) -> 00 00
  end

  // Debug Monitor
  always @(posedge clk) begin
    if (mem_req) begin
      $display("Time %0t: MEM REQ Addr=%h", $time, mem_addr);
    end
    if (mem_ack) begin
      $display("Time %0t: MEM ACK Data=%h", $time, mem_rdata);
    end
  end

  // Accept everything the fetch unit presents (no IB capacity modeling here)
  always_comb begin
    accept_count = {1'b0, valid_0} + {1'b0, valid_1};
  end

  always @(posedge clk) begin
    mem_ack <= 0;
    if (mem_req) begin
      mem_ack <= 1;
      // Return 16 bytes starting at mem_addr
      if (mem_addr < 1024-16) begin
        for (int i=0; i<16; i++) begin
           mem_rdata[(15-i)*8 +: 8] <= test_mem[mem_addr + i];
        end
      end else begin
        mem_rdata <= 128'h0;
      end
    end
  end

  // Test Sequence
  initial begin
    // Initialize
    rst = 1;
    branch_taken = 0;
    branch_target = 0;
    accept_count = 2'd0;
    
    // Reset
    #20;
    rst = 0;
    
    // Wait for initialization (fetch of first block)
    wait(valid_0);
    $display("Time %0t: Initial fetch complete. PC0=%h", $time, pc_0);
    
    // Test 1: Sequential Execution of NOPs (2 bytes each)
    // We expect to see PC increment by 2 (or 4 if dual issue)
    
    repeat(4) begin
      @(posedge clk);
      if (valid_0) begin
        $display("Time %0t: PC0=%h Valid0=%b PC1=%h Valid1=%b", $time, pc_0, valid_0, pc_1, valid_1);
        if (valid_0 && valid_1) $display("  -> Dual Issue NOPs");
      end
      // Wait for next valid if needed
      while (!valid_0) @(posedge clk);
    end
    
    // Test 2: Branch to 0x10
    $display("Time %0t: Branching to 0x10", $time);
    
    @(posedge clk);
    branch_taken <= 1;
    branch_target <= 32'h0000_0010;
    
    @(posedge clk);
    branch_taken <= 0;
    
    // Wait for valid data at 0x10
    @(posedge clk);
    while (!valid_0) @(posedge clk);
    
    $display("Time %0t: After Branch. PC0=%h", $time, pc_0);
    
    // At 0x10 we have:
    // Inst 1: ADD (5 bytes)
    // Inst 2: ADD (5 bytes)
    // Inst 3: NOP (2 bytes)
    
    // Cycle 1: Should see Inst 1 (ADD) and Inst 2 (ADD). Total 10 bytes.
    if (pc_0 == 32'h10 && valid_0 && valid_1) begin
        $display("PASS: Dual issue of 5-byte instructions. PC0=%h, PC1=%h", pc_0, pc_1);
    end else begin
        $display("FAIL: Expected PC=10 with Dual Issue. Got PC0=%h Valid0=%b Valid1=%b", pc_0, valid_0, valid_1);
    end
    
    // Step to next instruction
    @(posedge clk);
    while (!valid_0) @(posedge clk);
    
    // Cycle 2: Should be at 0x1A (NOP)
    $display("Time %0t: Cycle 2. PC0=%h", $time, pc_0);
    if (pc_0 == 32'h1A) $display("PASS: PC advanced correctly by 10 bytes to 1A");
    else $display("FAIL: Expected PC=1A, got %h", pc_0);
    
    // Step to next
    @(posedge clk);
    while (!valid_0) @(posedge clk);
    
    // Cycle 3: Should be at 0x1E (NOP) (since 1A and 1C were dual issued)
    $display("Time %0t: Cycle 3. PC0=%h", $time, pc_0);
    if (pc_0 == 32'h1E) $display("PASS: PC advanced to 1E");
    else $display("FAIL: Expected PC=1E, got %h", pc_0);
    
    // Step to next
    @(posedge clk);
    while (!valid_0) @(posedge clk);
    
    // Cycle 4: With deeper prefetch, boundary dual-issue can proceed without
    // an extra bubble. Expect advancement by 4 bytes.
    $display("Time %0t: Cycle 4. PC0=%h", $time, pc_0);
    if (pc_0 == 32'h22) $display("PASS: Boundary-crossed dual issue reached PC=0x22");
    else $display("FAIL: Expected PC=22, got %h", pc_0);

    // Cycle 5: Continue dual-issue advancement.
    @(posedge clk);
    while (!valid_0) @(posedge clk);
    $display("Time %0t: Cycle 5. PC0=%h", $time, pc_0);
    if (pc_0 == 32'h26) $display("PASS: Dual issue advanced to PC=0x26");
    else $display("FAIL: Expected PC=26, got %h", pc_0);
    
    $finish;
  end

endmodule
