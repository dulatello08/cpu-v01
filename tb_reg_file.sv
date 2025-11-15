/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 11/13/25
*/

`timescale 1ns/1ps

module tb_reg_file;
  // clock (not strictly needed for reads, but keeps the shape right)
  logic clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // DUT signals
  logic        we_a = 0, we_b = 0;
  logic [3:0]  wa = '0, wb = '0;
  logic [15:0] wd_a = '0, wd_b = '0;
  logic [1:0]  be_a = 2'b00, be_b = 2'b00;
  logic [3:0]  ra, rb;
  logic [15:0] rda, rdb;

  // instantiate your regfile (reads only)
  reg_file #(
    .DATA_WIDTH(16),
    .ADDR_WIDTH(4),
    .NUM_REGS  (15)
  ) dut (
    .clk   (clk),
    .we_a  (we_a), .wa(wa), .wd_a(wd_a), .be_a(be_a),
    .we_b  (we_b), .wb(wb), .wd_b(wd_b), .be_b(be_b),
    .ra    (ra),   .rda(rda),
    .rb    (rb),   .rdb(rdb)
  );

  initial begin
    // VCD
    $dumpfile("reg_file.vcd");
    $dumpvars(0, tb_reg_file.dut);

    // Start: read two regs
    ra = 4'd0;
    rb = 4'd5;
    @(negedge clk);
    // ---- Case 4: overlap lane -> A priority ----
    // Both write high byte; result should take A's high byte.
    we_a = 1; wa = 4'd0; wd_a = 16'hCC00; be_a = 2'b10;
    we_b = 1; wb = 4'd5; wd_b = 16'hEE00; be_b = 2'b10;
    @(posedge clk);
    @(negedge clk);
    we_a = 0; be_a = 2'b00;
    we_b = 0; be_b = 2'b00;
    repeat (2) @(posedge clk);

    $finish;
  end
  initial begin
    $monitor("[%0t] ra=%0d rda=%h  rb=%0d rdb=%h  we_a=%b we_b=%b",
             $time, ra, rda, rb, rdb, we_a, we_b);
  end

endmodule