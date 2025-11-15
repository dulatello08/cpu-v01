/*
* Copyright (c) 2025. All rights reserved.
* Created by dulat, 11/14/25
*/

module alu (
    input  logic [3:0]  op,

    input  logic [15:0] input_a,
    input  logic [15:0] input_b,

    output logic [15:0] output_lo,
    output logic [15:0] output_hi,

    output logic        flag_zero,
    output logic        flag_negative,
    output logic        flag_carry,
    output logic        flag_overflow
);

    localparam logic [3:0]
        ALU_OP_ADD   = 4'd0,
        ALU_OP_SUB   = 4'd1,
        ALU_OP_AND   = 4'd2,
        ALU_OP_OR    = 4'd3,
        ALU_OP_XOR   = 4'd4,
        ALU_OP_LSH   = 4'd5,
        ALU_OP_RSH   = 4'd6,
        ALU_OP_MUL16 = 4'd7,   // 16x16 -> low 16 bits (for `mul`)
        ALU_OP_UMULL = 4'd8,   // unsigned 16x16 -> 32 bits (for `umull`)
        ALU_OP_SMULL = 4'd9,   // signed   16x16 -> 32 bits (for `smull`)
        ALU_OP_PASSA = 4'd10;  // pass-through A (handy for some mov forms)

    // Temporaries
    logic [31:0]        mul_u;
    logic signed [15:0] a_s, b_s;
    logic signed [31:0] mul_s;
    logic [16:0]        add_ext;
    logic [16:0]        sub_ext;

    always_comb begin
        // defaults
        output_lo      = 16'h0000;
        output_hi      = 16'h0000;
        flag_zero      = 1'b0;
        flag_negative  = 1'b0;
        flag_carry     = 1'b0;
        flag_overflow  = 1'b0;

        mul_u   = 32'd0;
        mul_s   = 32'sd0;
        add_ext = 17'd0;
        sub_ext = 17'd0;

        a_s = input_a;
        b_s = input_b;

        case (op)
            ALU_OP_ADD: begin
                // 17-bit extended add so we can get carry
                add_ext     = {1'b0, input_a} + {1'b0, input_b};
                output_lo   = add_ext[15:0];
                flag_carry  = add_ext[16]; // carry-out

                // 2's complement overflow: a and b same sign, result different sign
                flag_overflow = (input_a[15] == input_b[15]) &&
                                (output_lo[15] != input_a[15]);
            end

            ALU_OP_SUB: begin
                // 17-bit extended subtract
                sub_ext     = {1'b0, input_a} - {1'b0, input_b};
                output_lo   = sub_ext[15:0];

                // For subtraction, "carry = 1" usually means "no borrow"
                flag_carry  = ~sub_ext[16];

                // 2's complement overflow: a and b different sign, result sign != a
                flag_overflow = (input_a[15] != input_b[15]) &&
                                (output_lo[15] != input_a[15]);
            end

            ALU_OP_AND: begin
                output_lo = input_a & input_b;
            end

            ALU_OP_OR: begin
                output_lo = input_a | input_b;
            end

            ALU_OP_XOR: begin
                output_lo = input_a ^ input_b;
            end

            ALU_OP_LSH: begin
                // logical left shift; use low 4 bits of input_b as shift amount 0–15
                output_lo = input_a << input_b[3:0];
            end

            ALU_OP_RSH: begin
                // logical right shift; if you want arithmetic, change to >>>
                output_lo = input_a >> input_b[3:0];
            end

            ALU_OP_MUL16: begin
                // truncated 16-bit multiply (for `mul`)
                mul_u     = input_a * input_b;
                output_lo = mul_u[15:0];   // low 16 bits
                // overflow/carry not defined here for now
            end

            ALU_OP_UMULL: begin
                // unsigned 16x16 = 32-bit product
                mul_u     = input_a * input_b;
                output_lo = mul_u[15:0];    // low 16 -> rd
                output_hi = mul_u[31:16];   // high 16 -> rn1
            end

            ALU_OP_SMULL: begin
                // signed 16x16 = 32-bit product
                mul_s     = a_s * b_s;
                output_lo = mul_s[15:0];
                output_hi = mul_s[31:16];
            end

            ALU_OP_PASSA: begin
                output_lo = input_a;
            end

            default: begin
                // keep defaults (all zeros)
            end
        endcase

        // Common flags from output_lo (for branches etc.)
        flag_zero     = (output_lo == 16'h0000);
        flag_negative = output_lo[15];
        // flag_carry / flag_overflow already set where they matter (add/sub)
    end

endmodule