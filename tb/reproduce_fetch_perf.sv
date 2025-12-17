//
// reproduce_fetch_perf.sv
// Reproduce fetch unit performance issues using test_mixed_lengths.hex
//

`timescale 1ns/1ps

module reproduce_fetch_perf;
  import neocore_pkg::*;

  // Testbench signals
  logic        clk;
  logic        rst;
  
  // Unified memory interface signals
  logic [31:0]  mem_if_addr;
  logic         mem_if_req;
  logic [127:0] mem_if_rdata;
  logic         mem_if_ack;
  logic [31:0]  mem_data_addr;
  logic [31:0]  mem_data_wdata;
  logic [1:0]   mem_data_size;
  logic         mem_data_we;
  logic         mem_data_req;
  logic [31:0]  mem_data_rdata;
  logic         mem_data_ack;
  
  logic        halted;
  logic [31:0] current_pc;
  logic        dual_issue_active;
  
  // Unified memory instance
  unified_memory #(
    .MEM_SIZE_BYTES(65536),
    .ADDR_WIDTH(32)
  ) memory (
    .clk(clk),
    .rst(rst),
    .if_addr(mem_if_addr),
    .if_req(mem_if_req),
    .if_rdata(mem_if_rdata),
    .if_ack(mem_if_ack),
    .data_addr(mem_data_addr),
    .data_wdata(mem_data_wdata),
    .data_size(mem_data_size),
    .data_we(mem_data_we),
    .data_req(mem_data_req),
    .data_rdata(mem_data_rdata),
    .data_ack(mem_data_ack)
  );
  
  // Core instance
  cpu_core dut (
    .clk(clk),
    .rst(rst),
    .mem_if_addr(mem_if_addr),
    .mem_if_req(mem_if_req),
    .mem_if_rdata(mem_if_rdata),
    .mem_if_ack(mem_if_ack),
    .mem_data_addr(mem_data_addr),
    .mem_data_wdata(mem_data_wdata),
    .mem_data_size(mem_data_size),
    .mem_data_we(mem_data_we),
    .mem_data_req(mem_data_req),
    .mem_data_rdata(mem_data_rdata),
    .mem_data_ack(mem_data_ack),
    .halted(halted),
    .current_pc(current_pc),
    .dual_issue_active(dual_issue_active)
  );
  
  // Clock generation (100 MHz)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // Cycle counter
  int cycle_count;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end
  
  logic [7:0] file_data [0:65535];

  // Helper task to write a byte to unified memory
  task write_byte(input [31:0] addr, input [7:0] data);
    logic [3:0] bank_sel;
    logic [31:0] bank_addr;
    begin
      bank_sel = addr[3:0];
      bank_addr = addr[31:4]; // addr / 16
      
      // Access the specific bank's memory array using hierarchical reference
      case (bank_sel)
        4'h0: memory.bank_gen[0].mem[bank_addr] = data;
        4'h1: memory.bank_gen[1].mem[bank_addr] = data;
        4'h2: memory.bank_gen[2].mem[bank_addr] = data;
        4'h3: memory.bank_gen[3].mem[bank_addr] = data;
        4'h4: memory.bank_gen[4].mem[bank_addr] = data;
        4'h5: memory.bank_gen[5].mem[bank_addr] = data;
        4'h6: memory.bank_gen[6].mem[bank_addr] = data;
        4'h7: memory.bank_gen[7].mem[bank_addr] = data;
        4'h8: memory.bank_gen[8].mem[bank_addr] = data;
        4'h9: memory.bank_gen[9].mem[bank_addr] = data;
        4'hA: memory.bank_gen[10].mem[bank_addr] = data;
        4'hB: memory.bank_gen[11].mem[bank_addr] = data;
        4'hC: memory.bank_gen[12].mem[bank_addr] = data;
        4'hD: memory.bank_gen[13].mem[bank_addr] = data;
        4'hE: memory.bank_gen[14].mem[bank_addr] = data;
        4'hF: memory.bank_gen[15].mem[bank_addr] = data;
      endcase
    end
  endtask
  
  // Test stimulus
  initial begin
    $display("Loading mem/test_mixed_lengths.hex execution...");
    
    // Clear memory
    for (int i = 0; i < 65536; i++) begin
        file_data[i] = 8'h00;
        write_byte(i, 8'h00);
    end

    // Load hex file
    $readmemh("mem/test_mixed_lengths.hex", file_data);
    
    // Write to memory banks
    for (int i=0; i<65536; i++) begin
       if (file_data[i] !== 8'hxx) 
           write_byte(i, file_data[i]);
    end

    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
    
    // Run until halt or timeout
    fork
      begin
        wait(halted);
        repeat(5) @(posedge clk);
        $display("\nDONE: Program halted at PC = 0x%08h", current_pc);
        $display("Total cycles: %0d", cycle_count);
        $finish;
      end
      begin
        repeat(500) @(posedge clk);
        $display("\nTIMEOUT: Limit reached");
        $display("Total cycles: %0d", cycle_count);
        $finish;
      end
    join_any
  end
  
  initial begin
    $dumpfile("reproduce.vcd");
    $dumpvars(0, reproduce_fetch_perf);
  end

endmodule
