//
// unified_memory.sv
// NeoCore 16x32 CPU - Unified Von Neumann Memory (BRAM-backed)
//
// Single unified memory for both instructions and data.
// Re-implemented using 16 interleaved memory banks via GENERATE blocks
// to force explicit Block RAM inference on ECP5.
//
// Organization:
//   16 Banks, interleaved by byte.
//   Bank 0 stores addresses 0, 16, 32...
//   Bank 1 stores addresses 1, 17, 33...

module unified_memory #(
    parameter MEM_SIZE_BYTES = 65536,  // 64 KB default
    parameter ADDR_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rst,

    // Instruction fetch port (Port A of BRAMs)
    input  logic [ADDR_WIDTH-1:0] if_addr,
    input  logic                  if_req,
    output logic [127:0]          if_rdata,
    output logic                  if_ack,

    // Data access port (Port B of BRAMs)
    input  logic [ADDR_WIDTH-1:0] data_addr,
    input  logic [31:0]           data_wdata,
    input  logic [1:0]            data_size,  // 00=byte, 01=half, 10=word
    input  logic                  data_we,
    input  logic                  data_req,
    output logic [31:0]           data_rdata,
    output logic                  data_ack
);

    localparam BANKS = 16;
    localparam BANK_DEPTH = MEM_SIZE_BYTES / BANKS;
    localparam BANK_ADDR_W = $clog2(BANK_DEPTH);
    localparam BANK_SEL_W = 4; // log2(16)

    // -------------------------------------------------------------------------
    // Address / Control Logic (Combinational)
    // -------------------------------------------------------------------------
    
    // -- Port A (Instruction) --
    logic [BANK_ADDR_W-1:0] if_row_base;
    logic [BANK_SEL_W-1:0]  if_offset;
    logic [BANK_SEL_W-1:0]  if_offset_reg;
    logic [BANK_ADDR_W-1:0] if_bank_addrs [0:BANKS-1];
    
    assign if_row_base = if_addr[ADDR_WIDTH-1 : BANK_SEL_W];
    assign if_offset   = if_addr[BANK_SEL_W-1 : 0];

    always_comb begin
        for (int i = 0; i < BANKS; i++) begin
            if (i < if_offset) 
                if_bank_addrs[i] = if_row_base + 1;
            else 
                if_bank_addrs[i] = if_row_base;
        end
    end

    // -- Port B (Data) --
    logic [BANK_ADDR_W-1:0] data_row_base;
    logic [BANK_SEL_W-1:0]  data_offset;
    logic [BANK_SEL_W-1:0]  data_offset_reg;
    logic [1:0]             data_size_reg;
    logic [BANK_ADDR_W-1:0] data_bank_addrs [0:BANKS-1];
    logic [BANKS-1:0]       data_bank_we;
    logic [7:0]             data_bank_wdata [0:BANKS-1];

    assign data_row_base = data_addr[ADDR_WIDTH-1 : BANK_SEL_W];
    assign data_offset   = data_addr[BANK_SEL_W-1 : 0];
    
    // Port B Address Calculation
    always_comb begin
        for (int i = 0; i < BANKS; i++) begin
            if (i < data_offset) 
                data_bank_addrs[i] = data_row_base + 1;
            else 
                data_bank_addrs[i] = data_row_base;
        end
    end

    // Port B Write Enable / Data Rotation Logic
    always_comb begin
        data_bank_we = '0;
        
        // 1. Write Enables
        if (data_we && data_req) begin
            logic [15:0] base_mask;
            case (data_size)
                2'b00: base_mask = 16'b0000_0000_0000_0001; // Byte
                2'b01: base_mask = 16'b0000_0000_0000_0011; // Half
                2'b10: base_mask = 16'b0000_0000_0000_1111; // Word
                default: base_mask = '0;
            endcase
            // Manual rotation for masks
            for (int i = 0; i < BANKS; i++) begin
                 int bit_idx;
                 bit_idx = (i - data_offset) & 4'hF;
                 if (bit_idx < 16)
                     data_bank_we[i] = base_mask[bit_idx];
                 else
                     data_bank_we[i] = 0;
            end
        end
        
        // 2. Write Data Rotation
        // Manual rotation to avoid dynamic shift issues in some tools
        for (int i = 0; i < BANKS; i++) begin
            logic [4:0] shift_idx; 
            // We want data_wdata[0] (LSB) to go to bank[data_offset]
            // So bank[i] gets byte from wdata corresponding to (i - offset) % 16
            // data_wdata is 32 bits (4 bytes).
            // Actually, let's stick to the previous logic but implementing it via mux logic per bank
            
            // logic [127:0] wdata_exp = {data_wdata, 96'h0};
            // The byte for bank 'i' comes from wdata byte 'k' such that (offset + k) % 16 = i
            // k = (i - offset) % 16
            
            // Wait, implementing the full barrel shifter logic explicitly:
            int src_byte_idx;
            // Handle wrap around: (i - data_offset) mod 16
            // arithmetic with 4-bit subtraction handles modulo 16 naturally
            src_byte_idx = (i - data_offset) & 4'hF; 
            
            if (src_byte_idx < 4) begin
                // data_wdata is [31:0], so bytes are 3, 2, 1, 0.
                // data_wdata[7:0] is byte 0? It's big endian or little?
                // Big-endian: MSB at lowest address. 
                // data_wdata[31:24] -> offset+0
                // data_wdata[23:16] -> offset+1
                
                // My previous logic was: wdata_exp = {data_wdata, 96'h0}; (padded at MSB)
                // then rotated.
                // If wdata = 0xAABBCCDD (32-bit). Byte 0 (MSB) = AA.
                // wdata_exp = AABBCCDD_00...
                // shift right by offset*8.
                // If offset=0: byte 0 (AA) -> byte 15 of 128-bit? No, indices.
                
                // Let's use the verified "double width" trick which is cleaner.
                logic [63:0] wdata_double; 
                wdata_double = {data_wdata, data_wdata}; 
                // We want to extract a 32-bit window, but mapped to banks.
                // Actually, let's just use the previous rotation logic but unroll it.
                
                // Re-implementation of the rotation:
                // wdata_rot[bank_i] = wdata_exp[bank_i rotated by offset]
                
                // Easier: Just select the byte based on the difference
                case (src_byte_idx)
                    0: data_bank_wdata[i] = data_wdata[31:24];
                    1: data_bank_wdata[i] = data_wdata[23:16];
                    2: data_bank_wdata[i] = data_wdata[15:8];
                    3: data_bank_wdata[i] = data_wdata[7:0];
                    default: data_bank_wdata[i] = 8'h00;
                endcase
            end else begin
                data_bank_wdata[i] = 8'h00;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Memory Generation
    // -------------------------------------------------------------------------
    
    // Wires to carry read data out of the generate block
    logic [7:0] if_bank_rdata [0:BANKS-1];
    logic [7:0] data_bank_rdata [0:BANKS-1];

    generate
        for (genvar i = 0; i < BANKS; i++) begin : bank_gen
            // Local memory array for this bank
            // (* ram_style = "block" *) // Optional hint for Yosys
            logic [7:0] mem [0:BANK_DEPTH-1];
            logic [7:0] rdata_a;
            logic [7:0] rdata_b;
            
            // Port A (Instruction Fetch) - Read Only
            always_ff @(posedge clk) begin
                rdata_a <= mem[if_bank_addrs[i]];
            end
            
            // Port B (Data Access) - Read / Write
            always_ff @(posedge clk) begin
                if (data_bank_we[i]) begin
                    mem[data_bank_addrs[i]] <= data_bank_wdata[i];
                end
                rdata_b <= mem[data_bank_addrs[i]];
            end
            
            assign if_bank_rdata[i] = rdata_a;
            assign data_bank_rdata[i] = rdata_b;

            // Memory Initialization for pure Verilog / Yosys
            // This allows us to use ecpbram or just load initial code
            // format: bank0.mem, bank1.mem ... bank15.mem
            initial begin
                // Optional: Initialize to zero or specific pattern if file missing
                // In simulation this might warn if file not found, which is fine.
                // For hardware, we want this to be picked up.
                $readmemh($sformatf("bank%0d.mem", i), mem); 
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Output Registers / Alignment Logic
    // -------------------------------------------------------------------------

    // Port A Output Control
    always_ff @(posedge clk) begin
        if (rst) begin
            if_ack <= 1'b0;
            if_offset_reg <= '0;
        end else begin
            if (if_req) begin
                if_offset_reg <= if_offset;
                if_ack <= 1'b1;
            end else begin
                if_ack <= 1'b0;
            end
        end
    end
    
    // Port A Alignment (Combinational)
    always_comb begin
        logic [127:0] rdata_raw;
        logic [127:0] rdata_aligned;
        
        for (int i = 0; i < BANKS; i++) begin
            rdata_raw[127 - (i*8) -: 8] = if_bank_rdata[i];
        end
        
        // Manual barrel shifter for read data
        // We want if_rdata[127:120] (Byte 0) to be rdata_raw corresponding to offset
        // Manual barrel shifter for read data
        for (int i = 0; i < 16; i++) begin
            int src_bank_idx;
            logic [7:0] byte_val;
            
            src_bank_idx = (i + if_offset_reg) & 4'hF;
            byte_val = if_bank_rdata[src_bank_idx];
            rdata_aligned[127 - (i*8) -: 8] = byte_val;
        end
        
        if_rdata = rdata_aligned;
    end

    // Port B Output Control
    always_ff @(posedge clk) begin
        if (rst) begin
            data_ack <= 1'b0;
            data_offset_reg <= '0;
            data_size_reg <= '0;
        end else begin
            if (data_req) begin
                data_offset_reg <= data_offset;
                data_size_reg <= data_size;
                data_ack <= 1'b1;
            end else begin
                data_ack <= 1'b0;
            end
        end
    end

    // Port B Alignment (Combinational)
    always_comb begin
        logic [127:0] rdata_raw;
        logic [127:0] rdata_aligned;
        
        for (int i = 0; i < BANKS; i++) begin
            rdata_raw[127 - (i*8) -: 8] = data_bank_rdata[i];
        end
        
        // Manual barrel shifter for data port
        for (int i = 0; i < 16; i++) begin
            int src_bank_idx;
            src_bank_idx = (i + data_offset_reg) & 4'hF;
            rdata_aligned[127 - (i*8) -: 8] = data_bank_rdata[src_bank_idx];
        end
        
        case (data_size_reg)
            2'b00: data_rdata = {24'h0, rdata_aligned[127:120]};
            2'b01: data_rdata = {16'h0, rdata_aligned[127:112]};
            2'b10: data_rdata = rdata_aligned[127:96];
            default: data_rdata = 32'h0;
        endcase
    end

endmodule : unified_memory
