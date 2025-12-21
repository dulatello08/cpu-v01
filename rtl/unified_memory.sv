//
// unified_memory.sv
// NeoCore 16x32 CPU - Unified Von Neumann Memory (BRAM-backed)
//
// Single unified memory for both instructions and data.
// Re-implemented using 4 interleaved 32-bit memory banks.
//
// Organization:
//   4 Banks, interleaved by Word (32-bit).
//   Bank 0 stores Words 0, 4, 8...  (Addr 0x00, 0x10, 0x20...)
//   Bank 1 stores Words 1, 5, 9...  (Addr 0x04, 0x14, 0x24...)
//   Bank 2 stores Words 2, 6, 10... (Addr 0x08, 0x18, 0x28...)
//   Bank 3 stores Words 3, 7, 11... (Addr 0x0C, 0x1C, 0x2C...)
//
//   Address mapping from Byte Address (A):
//   Global Word Index = A >> 2
//   Bank Index        = (A >> 2) & 3  (i.e., A[3:2])
//   Row Index         = A >> 4        (i.e., A[ADDR_WIDTH-1:4])
//

module unified_memory #(
    parameter MEM_SIZE_BYTES = 65536,  // 64 KB default
    parameter ADDR_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rst,

    // Instruction fetch port (Port A of BRAMs) - Read Only, 128-bit aligned
    input  logic [ADDR_WIDTH-1:0] if_addr,
    input  logic                  if_req,
    output logic [127:0]          if_rdata,
    output logic                  if_ack,

    // Data access port (Port B of BRAMs) - R/W, 32-bit
    input  logic [ADDR_WIDTH-1:0] data_addr,
    input  logic [31:0]           data_wdata,
    input  logic [1:0]            data_size,  // 00=byte, 01=half, 10=word
    input  logic                  data_we,
    input  logic                  data_req,
    output logic [31:0]           data_rdata,
    output logic                  data_ack
);

    localparam BANKS = 4;
    localparam BANK_WIDTH = 32;
    localparam BANK_BYTES = MEM_SIZE_BYTES / BANKS; 
    // Depth in words (32-bit) per bank = Bytes / 4
    localparam BANK_DEPTH = BANK_BYTES / 4; 
    localparam BANK_ADDR_W = $clog2(BANK_DEPTH);

    // -------------------------------------------------------------------------
    // Address Decoding
    // -------------------------------------------------------------------------
    
    // -- Port A (Instruction) --
    // Always reads a full 128-bit row (all 4 banks at the same Row Index)
    logic [BANK_ADDR_W-1:0] if_row_addr;
    assign if_row_addr = if_addr[15:4]; // 16-bit physical addr space inside 64KB
                                        // or ADDR_WIDTH... let's be safe:
                                        // if_addr is byte address.
                                        // Row is 16 bytes (128 bits).
                                        // Row Index = if_addr / 16.
                                        
    // -- Port B (Data) --
    logic [BANK_ADDR_W-1:0] data_row_addr;
    logic [1:0]             data_bank_sel;
    
    assign data_row_addr = data_addr[15:4];
    assign data_bank_sel = data_addr[3:2];

    // -------------------------------------------------------------------------
    // Data Port Write Enables (Byte Enables)
    // -------------------------------------------------------------------------
    logic [3:0] data_bank_we [0:BANKS-1]; 
    // Each bank has 4 byte-enables [3:0] corresponding to its own 32-bit word.
    
    always_comb begin
        for (int i=0; i<BANKS; i++) data_bank_we[i] = 4'b0000;

        if (data_we && data_req) begin
            logic [3:0] be;
            // Decode size and low bits [1:0] to get Byte Enable within the 32-bit word
            case (data_size)
                2'b00: begin // Byte
                    case (data_addr[1:0])
                        2'b00: be = 4'b1000; // Big Endian: Byte 0 is MSB [31:24]
                        2'b01: be = 4'b0100;
                        2'b10: be = 4'b0010;
                        2'b11: be = 4'b0001;
                    endcase
                end
                2'b01: begin // Half
                    // Aligned halfwords
                    if (data_addr[1] == 1'b0) be = 4'b1100; // Upper half
                    else                      be = 4'b0011; // Lower half
                end
                2'b10: begin // Word
                    be = 4'b1111;
                end
                default: be = 4'b0000;
            endcase
            
            // Activate WE for the selected bank
            data_bank_we[data_bank_sel] = be;
        end
    end

    // -------------------------------------------------------------------------
    // Memory Generation
    // -------------------------------------------------------------------------
    logic [31:0] if_bank_rdata [0:BANKS-1];
    logic [31:0] data_bank_rdata_raw [0:BANKS-1];

    generate
        for (genvar i = 0; i < BANKS; i++) begin : bank_gen
            // Infer 32-bit wide BRAM with Byte Enables
            // Standard idiom for ECP5 / Gowin / Xilinx
            
            logic [31:0] mem [0:BANK_DEPTH-1];
            logic [31:0] rdata_a;
            logic [31:0] rdata_b;
            
            // Port A (Instruction) - Read Only
            always_ff @(posedge clk) begin
                rdata_a <= mem[if_row_addr];
            end
            
            // Port B (Data) - Read / Write with Byte Enables
            always_ff @(posedge clk) begin
                if (data_bank_we[i][3]) mem[data_row_addr][31:24] <= data_wdata[31:24];
                if (data_bank_we[i][2]) mem[data_row_addr][23:16] <= data_wdata[23:16];
                if (data_bank_we[i][1]) mem[data_row_addr][15:8]  <= data_wdata[15:8];
                if (data_bank_we[i][0]) mem[data_row_addr][7:0]   <= data_wdata[7:0];
                rdata_b <= mem[data_row_addr];
            end
            
            assign if_bank_rdata[i] = rdata_a;
            assign data_bank_rdata_raw[i] = rdata_b;

            // Initial load
            initial begin
                $readmemh($sformatf("bank%0d_32.mem", i), mem); 
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Output Logic
    // -------------------------------------------------------------------------

    // -- Port A Output --
    // Concatenate banks to form 128-bit row.
    // Big Endian: Bank 0 is at offset 0 (MSBytes of the 128-bit block).
    // if_rdata[127:0] = {Bank0, Bank1, Bank2, Bank3}
    assign if_rdata = {if_bank_rdata[0], if_bank_rdata[1], if_bank_rdata[2], if_bank_rdata[3]};

    always_ff @(posedge clk) begin
        if (rst) if_ack <= 1'b0;
        else     if_ack <= if_req;
    end

    // -- Port B Output --
    // Mux the read data based on bank select
    logic [31:0] data_rdata_comb;
    logic [1:0]  data_bank_sel_reg;
    logic [1:0]  data_addr_low_reg; // For sub-word alignment [1:0]
    logic [1:0]  data_size_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            data_ack <= 1'b0;
            data_bank_sel_reg <= '0;
            data_addr_low_reg <= '0;
            data_size_reg <= '0;
        end else begin
            data_ack <= data_req;
            if (data_req) begin
                data_bank_sel_reg <= data_bank_sel;
                data_addr_low_reg <= data_addr[1:0];
                data_size_reg     <= data_size;
            end
        end
    end

    assign data_rdata_comb = data_bank_rdata_raw[data_bank_sel_reg];

    // Sub-word alignment for Read
    always_comb begin
        data_rdata = 32'h0;
        case (data_size_reg)
            2'b00: begin // Byte
                case (data_addr_low_reg)
                    2'b00: data_rdata = {24'h0, data_rdata_comb[31:24]};
                    2'b01: data_rdata = {24'h0, data_rdata_comb[23:16]};
                    2'b10: data_rdata = {24'h0, data_rdata_comb[15:8]};
                    2'b11: data_rdata = {24'h0, data_rdata_comb[7:0]};
                endcase
            end
            2'b01: begin // Half
                if (data_addr_low_reg[1] == 1'b0) data_rdata = {16'h0, data_rdata_comb[31:16]};
                else                              data_rdata = {16'h0, data_rdata_comb[15:0]};
            end
            2'b10: begin // Word
                data_rdata = data_rdata_comb;
            end
            default: data_rdata = 32'h0;
        endcase
    end

endmodule : unified_memory
