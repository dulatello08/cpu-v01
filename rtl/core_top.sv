//
// core_top.sv
// NeoCore 16x32 CPU - Synthesizable Top Level
//
// Wraps the CPU Core and Unified Memory for physical implementation.
// Maps basic IO (LEDs, Buttons) to memory addresses or status registers.
//

module core_top (
  input  logic       clk_25mhz,      // 25 MHz system clock
  input  logic [6:0] btn,            // Buttons (vector to match LPF)
  output logic [7:0] led,            // onboard LEDs
  output logic       wifi_en         // WiFi Enable (Active High) - Drive Low to disable ESP32
);

  // ==========================================================================
  // WiFi Control
  // ==========================================================================
  // Disable ESP32 to prevent pin interference
  assign wifi_en = 1'b0;

  // ==========================================================================
  // Reset Generation
  // ==========================================================================
  
  logic rst;
  assign rst = ~btn[0]; // Invert active-low button to active-high internal reset

`ifdef FPGA_ECP5
  // Route button reset onto the dedicated global set/reset network.
  // This reduces pressure on regular routing resources for high-fanout reset.
  GSR global_set_reset (
    .GSR(rst)
  );
`endif

  // ==========================================================================
  // Internal Wires
  // ==========================================================================

  // CPU -> Memory Interface
  logic [31:0]  cpu_if_addr;
  logic         cpu_if_req;
  logic [127:0] cpu_if_rdata;
  logic         cpu_if_ack;

  logic [31:0]  cpu_data_addr;
  logic [31:0]  cpu_data_wdata;
  logic [1:0]   cpu_data_size;
  logic         cpu_data_we;
  logic         cpu_data_req;
  logic [31:0]  cpu_data_rdata;
  logic         cpu_data_ack;

  // CPU Status
  logic        cpu_halted;
  logic [31:0] cpu_current_pc;
  logic        cpu_dual_issue_active;
  logic        led_mmio_ffff;

  // ==========================================================================
  // Heartbeat Counter
  // ==========================================================================
  logic [24:0] heartbeat;
  always_ff @(posedge clk_25mhz) begin
    heartbeat <= heartbeat + 1;
  end

  // ==========================================================================
  // CPU Core Instance
  // ==========================================================================

  cpu_core core (
    .clk(clk_25mhz),
    .rst(rst),
    
    // Instruction Fetch
    .mem_if_addr(cpu_if_addr),
    .mem_if_req(cpu_if_req),
    .mem_if_rdata(cpu_if_rdata),
    .mem_if_ack(cpu_if_ack),
    
    // Data Access
    .mem_data_addr(cpu_data_addr),
    .mem_data_wdata(cpu_data_wdata),
    .mem_data_size(cpu_data_size),
    .mem_data_we(cpu_data_we),
    .mem_data_req(cpu_data_req),
    .mem_data_rdata(cpu_data_rdata),
    .mem_data_ack(cpu_data_ack),
    
    // Status
    .halted(cpu_halted),
    .current_pc(cpu_current_pc),
    .dual_issue_active(cpu_dual_issue_active)
  );

  // ==========================================================================
  // Unified Memory Instance
  // ==========================================================================

  unified_memory #(
    .MEM_SIZE_BYTES(65536) // 64 KB
  ) mem (
    .clk(clk_25mhz),
    .rst(rst),
    
    // Port A: Instruction Fetch
    .if_addr(cpu_if_addr),
    .if_req(cpu_if_req),
    .if_rdata(cpu_if_rdata),
    .if_ack(cpu_if_ack),
    
    // Port B: Data Access
    .data_addr(cpu_data_addr),
    .data_wdata(cpu_data_wdata),
    .data_size(cpu_data_size),
    .data_we(cpu_data_we),
    .data_req(cpu_data_req),
    .data_rdata(cpu_data_rdata),
    .data_ack(cpu_data_ack)
  );
  // ==========================================================================
  // LED Logic
  // ==========================================================================

  // LED MMIO register at byte address 0xFFFF:
  // any non-zero write to that byte turns LED on; zero turns it off.
  always_ff @(posedge clk_25mhz) begin
    if (rst) begin
      led_mmio_ffff <= 1'b0;
    end else if (cpu_data_req && cpu_data_we) begin
      logic [3:0] be;

      be = 4'b0000;
      case (cpu_data_size)
        2'b00: begin
          case (cpu_data_addr[1:0])
            2'b00: be = 4'b1000;
            2'b01: be = 4'b0100;
            2'b10: be = 4'b0010;
            2'b11: be = 4'b0001;
          endcase
        end
        2'b01: begin
          if (cpu_data_addr[1] == 1'b0) be = 4'b1100;
          else                          be = 4'b0011;
        end
        2'b10: begin
          be = 4'b1111;
        end
        default: be = 4'b0000;
      endcase

      if ((cpu_data_addr[15:2] == 14'h3FFF) && be[0]) begin
        led_mmio_ffff <= (cpu_data_wdata[7:0] != 8'h00);
      end
    end
  end
  
  always_ff @(posedge clk_25mhz) begin
    led[7]   <= rst;                       // LED[7]: Reset Status (ON = in reset)
    led[6]   <= heartbeat[24];             // LED[6]: Heartbeat (toggle approx 0.6s)
    led[5]   <= cpu_halted;                // LED[5]: CPU Halted
    led[4]   <= cpu_dual_issue_active;     // LED[4]: Dual Issue Active
    led[3:1] <= cpu_current_pc[3:1];       // LED[3:1]: PC bits [3:1] (fast toggle)
    led[0]   <= led_mmio_ffff;             // LED[0]: MMIO byte at 0xFFFF (!=0 => ON)
  end

endmodule : core_top
