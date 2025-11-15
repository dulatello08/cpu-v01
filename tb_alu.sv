/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 11/14/25
*/

`timescale 1ns/1ps

module tb_alu;

    // DUT signals
    logic [3:0]  op;
    logic [15:0] input_a;
    logic [15:0] input_b;

    logic [15:0] output_lo;
    logic [15:0] output_hi;

    logic        flag_zero;
    logic        flag_negative;
    logic        flag_carry;
    logic        flag_overflow;

    // Instantiate DUT
    alu dut (
        .op           (op),
        .input_a      (input_a),
        .input_b      (input_b),
        .output_lo    (output_lo),
        .output_hi    (output_hi),
        .flag_zero    (flag_zero),
        .flag_negative(flag_negative),
        .flag_carry   (flag_carry),
        .flag_overflow(flag_overflow)
    );

    // Mirror the ALU operation encodings
    localparam logic [3:0]
        ALU_OP_ADD   = 4'd0,
        ALU_OP_SUB   = 4'd1,
        ALU_OP_AND   = 4'd2,
        ALU_OP_OR    = 4'd3,
        ALU_OP_XOR   = 4'd4,
        ALU_OP_LSH   = 4'd5,
        ALU_OP_RSH   = 4'd6,
        ALU_OP_MUL16 = 4'd7,
        ALU_OP_UMULL = 4'd8,
        ALU_OP_SMULL = 4'd9,
        ALU_OP_PASSA = 4'd10;

    // Simple stimulus task
    task automatic run_case(
        input logic [3:0]  t_op,
        input logic [15:0] a,
        input logic [15:0] b
    );
    begin
        op      = t_op;
        input_a = a;
        input_b = b;

        #1; // 1ns between vectors

        // Useful trace in the console, while VCD holds waveforms
        $display("%0t ns : op=%0d a=0x%04h b=0x%04h | lo=0x%04h hi=0x%04h Z=%0b N=%0b C=%0b V=%0b",
                 $time, op, input_a, input_b,
                 output_lo, output_hi,
                 flag_zero, flag_negative, flag_carry, flag_overflow);
    end
    endtask

    integer i, j;
    logic [15:0] a_pat, b_pat;

    initial begin
        // VCD dumping for Icarus + GTKWave
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, tb_alu);

        // Init
        op      = '0;
        input_a = '0;
        input_b = '0;

        #5;

        // ---------------------------------------------------------------------
        // Directed edge-case tests (good for debugging flags)
        // ---------------------------------------------------------------------
        run_case(ALU_OP_ADD  , 16'h0000, 16'h0000);
        run_case(ALU_OP_ADD  , 16'h7FFF, 16'h0001); // + overflow
        run_case(ALU_OP_ADD  , 16'h8000, 16'hFFFF); // - overflow
        run_case(ALU_OP_SUB  , 16'h8000, 16'h0001);
        run_case(ALU_OP_SUB  , 16'h0000, 16'h0001); // borrow case
        run_case(ALU_OP_AND  , 16'hFFFF, 16'h0F0F);
        run_case(ALU_OP_OR   , 16'hF0F0, 16'h0F0F);
        run_case(ALU_OP_XOR  , 16'hFFFF, 16'hAAAA);
        run_case(ALU_OP_LSH  , 16'h0001, 16'h000F);
        run_case(ALU_OP_RSH  , 16'h8000, 16'h000F);
        run_case(ALU_OP_MUL16, 16'hFFFF, 16'h0002);
        run_case(ALU_OP_UMULL, 16'hFFFF, 16'hFFFF);
        run_case(ALU_OP_SMULL, 16'h8000, 16'h0002);
        run_case(ALU_OP_PASSA, 16'h1234, 16'hABCD);

        // ---------------------------------------------------------------------
        // "A lot of values": double loop hitting many patterns per op
        // 16 x 16 x (ops) => thousands of vectors, still quick to sim
        // ---------------------------------------------------------------------
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                // Pattern generator: repeats nibbles to tickle different bits
                a_pat = {i[3:0], j[3:0], i[3:0], j[3:0]};
                b_pat = {j[3:0], i[3:0], j[3:0], i[3:0]};

                // add/sub
                run_case(ALU_OP_ADD , a_pat, b_pat);
                run_case(ALU_OP_SUB , a_pat, b_pat);

                // logic ops
                run_case(ALU_OP_AND , a_pat, b_pat);
                run_case(ALU_OP_OR  , a_pat, b_pat);
                run_case(ALU_OP_XOR , a_pat, b_pat);

                // shifts (use low nibble of j as shift amount)
                run_case(ALU_OP_LSH , a_pat, {12'd0, j[3:0]});
                run_case(ALU_OP_RSH , a_pat, {12'd0, j[3:0]});

                // 16-bit truncated multiply
                run_case(ALU_OP_MUL16,
                         {12'd0, i[3:0]},
                         {12'd0, j[3:0]});

                // unsigned full-width multiply
                run_case(ALU_OP_UMULL,
                         {8'd0,  i[3:0], j[3:0]},
                         {8'd0,  j[3:0], i[3:0]});

                // signed multiply: mix negative and positive values
                run_case(ALU_OP_SMULL,
                         {12'hFFF, i[3:0]},   // negative (top bits = 1)
                         {12'h000, j[3:0]});  // small positive

                // pass-through
                run_case(ALU_OP_PASSA, a_pat, b_pat);
            end
        end

        #10;
        $finish;
    end

endmodule