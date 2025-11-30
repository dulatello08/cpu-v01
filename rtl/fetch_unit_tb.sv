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
  logic        stall;
  logic        dual_issue;
  
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

  // DUT Instantiation
  fetch_unit dut (
    .clk(clk),
    .rst(rst),
    .branch_taken(branch_taken),
    .branch_target(branch_target),
    .stall(stall),
    .dual_issue(dual_issue),
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
    .valid_1(valid_1)
  );

  // Clock Generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Memory Simulation
  // Simple memory model that returns data based on address
  always @(posedge clk) begin
    mem_ack <= 0;
    if (mem_req) begin
      mem_ack <= 1;
      // Generate some recognizable pattern based on address
      // Addr 0x00: NOP (00 00)
      // Addr 0x10: ADD (00 01 01 02 03) - 5 bytes
      case (mem_addr)
        32'h0000_0000: begin
          // 00-0F: 8 NOPs (2 bytes each)
          // 00 00 | 00 00 | 00 00 | 00 00 | 00 00 | 00 00 | 00 00 | 00 00
          mem_rdata <= {8{16'h0000}}; 
        end
        32'h0000_0010: begin
          // 10-1F: 
          // 10: ADD r1, r2, r3 (5 bytes) -> Spec=00, Op=01 (ADD) -> 00 01 01 02 03
          // 15: ADD r4, r5, r6 (5 bytes) -> Spec=00, Op=01 (ADD) -> 00 01 04 05 06
          // 1A: NOP (2 bytes) -> 00 00
          // 1C: NOP (2 bytes) -> 00 00
          // 1E: NOP (2 bytes) -> 00 00
          mem_rdata <= {
            8'h00, 8'h01, 8'h01, 8'h02, 8'h03, // Inst 1 (5B)
            8'h00, 8'h01, 8'h04, 8'h05, 8'h06, // Inst 2 (5B)
            8'h00, 8'h00,                      // Inst 3 (2B)
            8'h00, 8'h00,                      // Inst 4 (2B)
            8'h00, 8'h00                       // Inst 5 (2B)
          };
        end
        32'h0000_0020: begin
            // 20-2F: All NOPs
            mem_rdata <= {8{16'h0000}};
        end
        default: mem_rdata <= 128'h0;
      endcase
    end
  end

  // Test Sequence
  initial begin
    // Initialize
    rst = 1;
    branch_taken = 0;
    branch_target = 0;
    stall = 0;
    dual_issue = 1; // Enable dual issue
    
    // Reset
    #20;
    rst = 0;
    
    // Wait for initialization (fetch of first block)
    wait(valid_0);
    $display("Time %0t: Initial fetch complete. PC0=%h", $time, pc_0);
    
    // Test 1: Sequential Execution of NOPs (2 bytes each)
    // We expect to see PC increment by 2 (or 4 if dual issue)
    
    for (int i=0; i<4; i++) begin
      @(posedge clk);
      #1;
      $display("Time %0t: PC0=%h Valid0=%b PC1=%h Valid1=%b", $time, pc_0, valid_0, pc_1, valid_1);
      if (valid_0 && valid_1) $display("  -> Dual Issue NOPs");
    end
    
    // Test 2: Branch to 0x10
    $display("Time %0t: Branching to 0x10", $time);
    
    // Use non-blocking assignment to avoid races
    @(posedge clk);
    branch_taken <= 1;
    branch_target <= 32'h0000_0010;
    
    @(posedge clk);
    branch_taken <= 0;
    
    // Wait for fetch
    // INIT -> WAIT -> NORMAL
    // We want to catch the FIRST cycle of NORMAL.
    // INIT (1 cycle) -> WAIT (1 cycle) -> NORMAL (starts)
    
    @(posedge clk); // INIT
    @(posedge clk); // WAIT
    #1; // Just after NORMAL starts
    
    $display("Time %0t: After Branch. PC0=%h", $time, pc_0);
    
    // At 0x10 we have:
    // Inst 1: ADD (5 bytes)
    // Inst 2: ADD (5 bytes)
    // Inst 3: NOP (2 bytes)
    
    // Cycle 1: Should see Inst 1 (ADD) and Inst 2 (ADD). Total 10 bytes.
    if (valid_0 && valid_1) begin
        $display("PASS: Dual issue of 5-byte instructions. PC0=%h, PC1=%h", pc_0, pc_1);
    end else begin
        $display("FAIL: Expected dual issue. Valid0=%b Valid1=%b", valid_0, valid_1);
    end
    
    @(posedge clk);
    #1;
    // Cycle 2: Should be at 0x1A (NOP)
    // PC should be 0x1A.
    $display("Time %0t: Cycle 2. PC0=%h", $time, pc_0);
    if (pc_0 == 32'h1A) $display("PASS: PC advanced correctly by 10 bytes");
    else $display("FAIL: Expected PC=1A, got %h", pc_0);
    
    // Test 3: Straddling
    // We are at 0x1A. NOP (2B) -> 0x1C. NOP (2B) -> 0x1E. NOP (2B) -> 0x20.
    // 0x1E is the last instruction in the 0x10 block.
    // 0x20 starts the next block.
    
    // Let's consume 0x1A and 0x1C (Dual NOPs)
    @(posedge clk);
    #1;
    $display("Time %0t: Cycle 3. PC0=%h", $time, pc_0);
    // Should be 0x1E.
    
    // Now at 0x1E. Next instruction is NOP at 0x1E (2 bytes).
    // It ends at 0x20.
    // The fetch unit should have prefetched 0x20 block by now.
    
    if (pc_0 == 32'h1E) $display("PASS: Reached end of block");
    
    @(posedge clk);
    #1;
    $display("Time %0t: Cycle 4. PC0=%h", $time, pc_0);
    // Should be 0x20.
    if (pc_0 == 32'h20) $display("PASS: Crossed 16-byte boundary to 0x20");
    else $display("FAIL: Expected PC=20, got %h", pc_0);
    
    $finish;
  end

endmodule
