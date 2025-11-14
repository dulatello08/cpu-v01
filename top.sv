/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 10/17/25
*/
module top #(
  parameter integer CLK_HZ      = 25_000_000,
  parameter integer DEBOUNCE_US = 10_000
) (
  input  logic       clk_25mhz,
  input  logic [6:0] btn,
  output logic [7:0] led
);
  localparam integer COOLDOWN = (CLK_HZ/1_000_000) * DEBOUNCE_US;

  // --- one-pulse buttons ---
  logic p_inc, p_dec, p_page, p_show, p_edit, p_rst;
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_inc  (.clk(clk), .in(btn[2]), .pulse(p_inc));
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_dec  (.clk(clk), .in(btn[3]), .pulse(p_dec));
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_page (.clk(clk), .in(btn[1]), .pulse(p_page));
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_show (.clk(clk), .in(btn[4]), .pulse(p_show));
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_edit (.clk(clk), .in(btn[5]), .pulse(p_edit));
  btn_onepulse #(.COOLDOWN_CYCLES(COOLDOWN)) u_rst  (.clk(clk), .in(btn[6]), .pulse(p_rst));

  // --- UI state ---
  localparam int ADDR_W   = 4;
  localparam int NUM_REGS = 15;

  logic [ADDR_W-1:0] addr_a, addr_b;
  logic page_hi, show_b, edit_b;

  // power-up defaults (ok for sim; on FPGA you can also hit btn5)
  initial begin
    addr_a = '0; addr_b = '0;
    page_hi = 1'b0; show_b = 1'b0; edit_b = 1'b0;
  end

  // address wrap helpers in-line (no functions, no ternary-in-return)
  always_ff @(posedge clk) begin
    if (p_rst) begin
      addr_a <= '0;
      addr_b <= '0;
      page_hi <= 1'b0;
      show_b  <= 1'b0;
      edit_b  <= 1'b0;
    end else begin
      if (p_edit) edit_b <= ~edit_b;
      if (p_page) page_hi <= ~page_hi;
      if (p_show) show_b  <= ~show_b;

      if (edit_b) begin
        if (p_inc) begin
          if (addr_b == NUM_REGS-1) addr_b <= '0; else addr_b <= addr_b + 1;
        end
        if (p_dec) begin
          if (addr_b == '0) addr_b <= NUM_REGS-1; else addr_b <= addr_b - 1;
        end
      end else begin
        if (p_inc) begin
          if (addr_a == NUM_REGS-1) addr_a <= '0; else addr_a <= addr_a + 1;
        end
        if (p_dec) begin
          if (addr_a == '0) addr_a <= NUM_REGS-1; else addr_a <= addr_a - 1;
        end
      end
    end
  end

  // --- regfile (writes disabled for now) ---
  logic [15:0] rda, rdb;

  reg_file #(
    .DATA_WIDTH(16),
    .ADDR_WIDTH(4),
    .NUM_REGS  (15)
  ) u_rf (
    .clk(clk),

    .we_a(1'b0), .wa('0), .wd_a('0), .be_a(2'b00),
    .we_b(1'b0), .wb('0), .wd_b('0), .be_b(2'b00),

    .ra(addr_a), .rda(rda),
    .rb(addr_b), .rdb(rdb)
  );

  // selected byte → LEDs (use if/else instead of "?:" to appease strict parsers)
  logic [7:0] byte_a, byte_b;
  always_comb begin
    if (page_hi) begin
      byte_a = rda[15:8];
      byte_b = rdb[15:8];
    end else begin
      byte_a = rda[7:0];
      byte_b = rdb[7:0];
    end

    if (show_b) led = byte_b; else led = byte_a;
  end
endmodule