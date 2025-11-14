/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 10/17/25
*/

module reg_file #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4,
    parameter int NUM_REGS   = 15
) (
    input  logic                     clk,

    // write port A
    input  logic                     we_a,
    input  logic [ADDR_WIDTH-1:0]    wa,
    input  logic [DATA_WIDTH-1:0]    wd_a,
    input  logic [1:0]               be_a,     // [1]=high byte, [0]=low byte

    // write port B
    input  logic                     we_b,
    input  logic [ADDR_WIDTH-1:0]    wb,
    input  logic [DATA_WIDTH-1:0]    wd_b,
    input  logic [1:0]               be_b,

    // read port A
    input  logic [ADDR_WIDTH-1:0]    ra,
    output logic [DATA_WIDTH-1:0]    rda,

    // read port B
    input  logic [ADDR_WIDTH-1:0]    rb,
    output logic [DATA_WIDTH-1:0]    rdb
);

    logic [DATA_WIDTH-1:0] regs [NUM_REGS]; // regs[0..14]
    initial begin
       for (int i = 0; i < NUM_REGS; i++) begin
           regs[i] = {i,i};
       end
    end

    function automatic logic in_range(input logic [ADDR_WIDTH-1:0] a);
      return (a < NUM_REGS[ADDR_WIDTH-1:0]);
    endfunction

    // READS (OLD data, defined oob behavior)
    assign rda = in_range(ra) ? regs[ra] : '0;
    assign rdb = in_range(rb) ? regs[rb] : '0;

    // WRITES (sketch you’ll fill in)
    always_ff @(posedge clk) begin
      logic conflict;
      conflict = we_a && we_b &&
                   in_range(wa) && in_range(wb) &&
                   (wa == wb);
      if (conflict) begin
        logic [15:0] old, next;
        old  = regs[wa];     // old contents at that register
        next = old;

        // low byte: A has priority, then B, else keep old
        if (be_a[0])      next[7:0]  = wd_a[7:0];
        else if (be_b[0]) next[7:0]  = wd_b[7:0];

        // high byte: A has priority, then B, else keep old
        if (be_a[1])      next[15:8] = wd_a[15:8];
        else if (be_b[1]) next[15:8] = wd_b[15:8];

        regs[wa] <= next;   // one combined write
      end else if (we_a && in_range(wa)) begin
        logic [15:0] next_a;

        // start from old value
        next_a = regs[wa];

        // apply byte enables
        if (be_a[0]) next_a[7:0]  = wd_a[7:0];    // low byte
        if (be_a[1]) next_a[15:8] = wd_a[15:8];   // high byte

        regs[wa] <= next_a;
      end
      if (we_b && in_range(wb)) begin
        logic [15:0] next_b;

        // start from old value
        next_b = regs[wb];

        // apply byte enables
        if (be_b[0]) next_b[7:0]  = wd_b[7:0];    // low byte
        if (be_b[1]) next_b[15:8] = wd_b[15:8];   // high byte

        regs[wb] <= next_b;
      end

    end

endmodule