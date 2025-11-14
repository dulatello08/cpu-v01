/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 10/24/25
*/
// btn_onepulse.sv
module btn_onepulse #(
  parameter int COOLDOWN_CYCLES = 250_000  // ~10ms @ 25MHz
) (
  input  logic clk,
  input  logic in,
  output logic pulse
);
  logic sync0, sync1, prev;
  int unsigned cd;

  always_ff @(posedge clk) begin
    // 2-FF sync
    sync0 <= in;
    sync1 <= sync0;

    // cooldown counter
    if (cd != 0) cd <= cd - 1;

    // rising-edge detect + cooldown → one pulse
    pulse <= 1'b0;
    if (sync1 && !prev && (cd == 0)) begin
      pulse <= 1'b1;
      cd    <= COOLDOWN_CYCLES;
    end

    prev <= sync1;
  end
endmodule