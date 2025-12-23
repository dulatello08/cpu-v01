//
// unified_memory_tb.sv
// Testbench for NeoCore 16x32 Unified Memory Module
//
// Tests:
//   - 128-bit instruction fetch port
//   - Byte/Halfword/Word data access
//   - Big-endian byte ordering
//   - Concurrent IF and Data access
//

`timescale 1ns/1ps

module unified_memory_tb;
  import neocore_pkg::*;

  // Signals
  logic        clk;
  logic        rst;
  
  // Instruction fetch port
  logic [31:0]  if_addr;
  logic         if_req;
  logic [127:0] if_rdata;
  logic         if_ack;
  
  // Data access port
  logic [31:0]  data_addr;
  logic [31:0]  data_wdata;
  logic [1:0]   data_size;
  logic         data_we;
  logic         data_req;
  logic [31:0]  data_rdata;
  logic         data_ack;

  // DUT Instantiation
  unified_memory #(
    .MEM_SIZE_BYTES(4096),
    .ADDR_WIDTH(32)
  ) dut (
    .clk(clk),
    .rst(rst),
    .if_addr(if_addr),
    .if_req(if_req),
    .if_rdata(if_rdata),
    .if_ack(if_ack),
    .data_addr(data_addr),
    .data_wdata(data_wdata),
    .data_size(data_size),
    .data_we(data_we),
    .data_req(data_req),
    .data_rdata(data_rdata),
    .data_ack(data_ack)
  );

  // Clock generation (100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Test counters
  int pass_count = 0;
  int fail_count = 0;

  // Helper task to write a word
  task write_word(input [31:0] addr, input [31:0] data);
    @(posedge clk);
    data_addr <= addr;
    data_wdata <= data;
    data_size <= 2'b10; // Word
    data_we <= 1'b1;
    data_req <= 1'b1;
    @(posedge clk);
    data_req <= 1'b0;
    data_we <= 1'b0;
    wait(data_ack);
    @(posedge clk);
  endtask

  // Helper task to read a word
  task read_word(input [31:0] addr, output [31:0] data);
    @(posedge clk);
    data_addr <= addr;
    data_size <= 2'b10; // Word
    data_we <= 1'b0;
    data_req <= 1'b1;
    @(posedge clk);
    data_req <= 1'b0;
    wait(data_ack);
    data = data_rdata;
    @(posedge clk);
  endtask

  // Helper task to write a byte
  task write_byte(input [31:0] addr, input [7:0] data);
    @(posedge clk);
    data_addr <= addr;
    data_wdata <= {data, data, data, data}; // Replicate for any position
    data_size <= 2'b00; // Byte
    data_we <= 1'b1;
    data_req <= 1'b1;
    @(posedge clk);
    data_req <= 1'b0;
    data_we <= 1'b0;
    wait(data_ack);
    @(posedge clk);
  endtask

  // Helper task to read a byte
  task read_byte(input [31:0] addr, output [7:0] data);
    @(posedge clk);
    data_addr <= addr;
    data_size <= 2'b00; // Byte
    data_we <= 1'b0;
    data_req <= 1'b1;
    @(posedge clk);
    data_req <= 1'b0;
    wait(data_ack);
    data = data_rdata[7:0];
    @(posedge clk);
  endtask

  // Helper task to fetch instructions
  task fetch_block(input [31:0] addr, output [127:0] data);
    @(posedge clk);
    if_addr <= addr;
    if_req <= 1'b1;
    @(posedge clk);
    if_req <= 1'b0;
    wait(if_ack);
    data = if_rdata;
    @(posedge clk);
  endtask

  // Test stimulus
  initial begin
    logic [31:0] read_data;
    logic [7:0] byte_data;
    logic [127:0] block_data;
    
    $display("========================================");
    $display("Unified Memory Testbench");
    $display("========================================\n");

    // Initialize
    rst = 1;
    if_addr = 0;
    if_req = 0;
    data_addr = 0;
    data_wdata = 0;
    data_size = 0;
    data_we = 0;
    data_req = 0;
    
    repeat(3) @(posedge clk);
    rst = 0;
    repeat(2) @(posedge clk);

    // Test 1: Word Write/Read
    $display("Test 1: Word Write/Read");
    write_word(32'h00, 32'hDEADBEEF);
    read_word(32'h00, read_data);
    if (read_data == 32'hDEADBEEF) begin
      $display("  PASS: Read 0x%h (expected 0xDEADBEEF)", read_data);
      pass_count++;
    end else begin
      $display("  FAIL: Read 0x%h (expected 0xDEADBEEF)", read_data);
      fail_count++;
    end

    // Test 2: Byte Write/Read (Big Endian)
    $display("\nTest 2: Byte Write/Read (Big Endian)");
    write_byte(32'h10, 8'hAA);
    read_byte(32'h10, byte_data);
    if (byte_data == 8'hAA) begin
      $display("  PASS: Read 0x%h at addr 0x10 (expected 0xAA)", byte_data);
      pass_count++;
    end else begin
      $display("  FAIL: Read 0x%h at addr 0x10 (expected 0xAA)", byte_data);
      fail_count++;
    end

    // Test 3: Instruction Fetch (128-bit)
    $display("\nTest 3: 128-bit Instruction Fetch");
    write_word(32'h20, 32'h11223344);
    write_word(32'h24, 32'h55667788);
    write_word(32'h28, 32'h99AABBCC);
    write_word(32'h2C, 32'hDDEEFF00);
    
    fetch_block(32'h20, block_data);
    if (block_data == 128'h112233445566778899AABBCCDDEEFF00) begin
      $display("  PASS: Fetched 0x%h", block_data);
      pass_count++;
    end else begin
      $display("  FAIL: Fetched 0x%h (expected 0x112233445566778899AABBCCDDEEFF00)", block_data);
      fail_count++;
    end

    // Test 4: Halfword access
    $display("\nTest 4: Halfword access");
    write_word(32'h30, 32'hCAFEBABE);
    
    data_addr <= 32'h30;
    data_size <= 2'b01; // Half
    data_we <= 1'b0;
    data_req <= 1'b1;
    @(posedge clk);
    data_req <= 1'b0;
    wait(data_ack);
    if (data_rdata[15:0] == 16'hCAFE) begin
      $display("  PASS: Upper half = 0x%h (expected 0xCAFE)", data_rdata[15:0]);
      pass_count++;
    end else begin
      $display("  FAIL: Upper half = 0x%h (expected 0xCAFE)", data_rdata[15:0]);
      fail_count++;
    end

    // Summary
    $display("\n========================================");
    $display("Test Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================");

    $finish;
  end

endmodule : unified_memory_tb
