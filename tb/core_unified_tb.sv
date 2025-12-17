//
// core_unified_tb.sv
// Testbench for NeoCore 16x32 Dual-Issue CPU Core with Unified Memory
//
// Tests the complete core with Von Neumann architecture and big-endian memory.
//

`timescale 1ns/1ps

module core_unified_tb;
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
  int dual_issue_count;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_count <= 0;
      dual_issue_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (dual_issue_active) begin
        dual_issue_count <= dual_issue_count + 1;
      end
    end
  end
  
  // VCD dump for waveform viewing
  initial begin
    $dumpfile("core_unified_tb.vcd");
    $dumpvars(0, core_unified_tb);
  end
  
  // Test stimulus
  initial begin
    $display("========================================");
    $display("NeoCore 16x32 Minimal Single Instruction Test");
    $display("Testing: MOV R1, #0x0005");
    $display("========================================\n");
    
    // Initialize
    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
    
    
    $display("Loading minimal test program into memory...");
    
    // Clear memory
    for (int i = 0; i < 65536; i++) begin
      write_byte(i, 8'h00);
    end

    // Absolute minimal test program (big-endian encoding):
    // 0x00: MOV R1, #0x0005       [00][09][01][00][05]
    // 0x05: MOV R2, R1            [02][09][02][01]
    // 0x09: HLT                   [00][12]

    // Load program (big-endian)
    
    // MOV R1, #0x0005 at 0x00
    write_byte(32'h00, 8'h00);  // MOV spec
    write_byte(32'h01, 8'h09);  // MOV op
    write_byte(32'h02, 8'h01);  // rd = R1
    write_byte(32'h03, 8'h00);  // imm high
    write_byte(32'h04, 8'h05);  // imm low

    // MOV R2, R1 at 0x05
    write_byte(32'h05, 8'h02);  // MOV spec (register)
    write_byte(32'h06, 8'h09);  // MOV op
    write_byte(32'h07, 8'h02);  // rd = R2
    write_byte(32'h08, 8'h01);  // rs = R1
    
    // HLT at 0x09
    write_byte(32'h09, 8'h00);  // HLT spec
    write_byte(32'h0A, 8'h12);  // HLT op
    
    $display("Program loaded:");
    $display("  0x00: MOV R1, #0x0005");
    $display("  0x05: MOV R2, R1");
    $display("  0x09: HLT");
    $display("Starting execution...\n");
    
    // Run until halt or timeout
    fork
      begin
        wait(halted);
        // Wait a couple more cycles for pipeline to drain
        repeat(3) @(posedge clk);
        
        $display("\n========================================");
        $display("Program halted at PC = 0x%08h", current_pc);
        $display("Total cycles: %0d", cycle_count);
        $display("========================================");
        
        // Check register R1 and R2 values
        $display("\nChecking results:");
        $display("  R1 = 0x%04h (expected 0x0005)", dut.regfile.registers[1]);
        $display("  R2 = 0x%04h (expected 0x0005)", dut.regfile.registers[2]);
        
        if (dut.regfile.registers[1] == 16'h0005 && dut.regfile.registers[2] == 16'h0005) begin
          $display("\n✓ TEST PASSED: R1 and R2 have correct values");
        end else begin
          $display("\n✗ TEST FAILED: Wrong register values!");
          $display("  R1 Expected: 0x0005, Got: 0x%04h", dut.regfile.registers[1]);
          $display("  R2 Expected: 0x0005, Got: 0x%04h", dut.regfile.registers[2]);
        end
        
        $finish;
      end
      begin
        repeat(1000) @(posedge clk);
        $display("\n========================================");
        $display("ERROR: Test timeout after %0d cycles", cycle_count);
        $display("PC = 0x%08h, Halted = %b", current_pc, halted);
        $display("========================================");
        $display("\nRegister state at timeout:");
        $display("  R1 = 0x%04h (expected 0x0005)", dut.regfile.registers[1]);
        $display("  R2 = 0x%04h (expected 0x0005)", dut.regfile.registers[2]);
        $finish;
      end
    join_any
  end
  
  // Monitor key signals with detailed pipeline and fetch buffer state
  always @(posedge clk) begin
    if (!rst && cycle_count < 20) begin
      $display("Cycle %3d: PC=0x%08h Halt=%b", 
               cycle_count, current_pc, halted);
      $display("          Memory@PC: [0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h]",
               read_byte(current_pc), read_byte(current_pc+1),
               read_byte(current_pc+2), read_byte(current_pc+3),
               read_byte(current_pc+4), read_byte(current_pc+5),
               read_byte(current_pc+6));
//      $display("          FetchState: state=%d current_pc=0x%h consumed=%d",
//               dut.fetch.state, dut.fetch.current_pc, dut.fetch.consumed_count);
//      $display("                    block[1:0]=0x%02h%02h spec_0=0x%02h op_0=0x%02h len0=%d",
//               dut.fetch.current_block[1], dut.fetch.current_block[0], dut.fetch.spec_0, dut.fetch.op_0, dut.fetch.inst_len_0);
//      $display("                    spec_1=0x%02h op_1=0x%02h len1=%d",
//               dut.fetch.spec_1, dut.fetch.op_1, dut.fetch.inst_len_1);
      $display("          Fetch: valid0=%b valid1=%b dual_issue=%b",
               dut.fetch_valid_0, dut.fetch_valid_1, dut.dual_issue_active);
      $display("          IF/ID0: valid=%b pc=0x%h opcode=0x%02h spec=0x%02h",
               dut.if_id_out_0.valid, dut.if_id_out_0.pc,
               dut.if_id_out_0.inst_data[63:56], dut.if_id_out_0.inst_data[71:64]);
      $display("          IF/ID1: valid=%b pc=0x%h opcode=0x%02h spec=0x%02h",
               dut.if_id_out_1.valid, dut.if_id_out_1.pc,
               dut.if_id_out_1.inst_data[63:56], dut.if_id_out_1.inst_data[71:64]);
      $display("          ID/EX0: valid=%b pc=0x%h is_halt=%b rd_addr=%d rd_we=%b",
               dut.id_ex_out_0.valid, dut.id_ex_out_0.pc, dut.id_ex_out_0.is_halt,
               dut.id_ex_out_0.rd_addr, dut.id_ex_out_0.rd_we);
      $display("          ID/EX1: valid=%b pc=0x%h is_halt=%b",
               dut.id_ex_out_1.valid, dut.id_ex_out_1.pc, dut.id_ex_out_1.is_halt);
      $display("          EX/MEM0: valid=%b is_halt=%b alu_result=0x%h",
               dut.ex_mem_out_0.valid, dut.ex_mem_out_0.is_halt, dut.ex_mem_out_0.alu_result);
      $display("          MEM/WB0: valid=%b is_halt=%b wb_data=0x%h rd_addr=%d rd_we=%b",
               dut.mem_wb_out_0.valid, dut.mem_wb_out_0.is_halt, dut.mem_wb_out_0.wb_data,
               dut.mem_wb_out_0.rd_addr, dut.mem_wb_out_0.rd_we);
    end
  end

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

  // Helper function to read a byte from unified memory (for debug)
  function logic [7:0] read_byte(input [31:0] addr);
    logic [3:0] bank_sel;
    logic [31:0] bank_addr;
    begin
      bank_sel = addr[3:0];
      bank_addr = addr[31:4];
      
      case (bank_sel)
        4'h0: return memory.bank_gen[0].mem[bank_addr];
        4'h1: return memory.bank_gen[1].mem[bank_addr];
        4'h2: return memory.bank_gen[2].mem[bank_addr];
        4'h3: return memory.bank_gen[3].mem[bank_addr];
        4'h4: return memory.bank_gen[4].mem[bank_addr];
        4'h5: return memory.bank_gen[5].mem[bank_addr];
        4'h6: return memory.bank_gen[6].mem[bank_addr];
        4'h7: return memory.bank_gen[7].mem[bank_addr];
        4'h8: return memory.bank_gen[8].mem[bank_addr];
        4'h9: return memory.bank_gen[9].mem[bank_addr];
        4'hA: return memory.bank_gen[10].mem[bank_addr];
        4'hB: return memory.bank_gen[11].mem[bank_addr];
        4'hC: return memory.bank_gen[12].mem[bank_addr];
        4'hD: return memory.bank_gen[13].mem[bank_addr];
        4'hE: return memory.bank_gen[14].mem[bank_addr];
        4'hF: return memory.bank_gen[15].mem[bank_addr];
        default: return 8'h00;
      endcase
    end
  endfunction

endmodule : core_unified_tb
