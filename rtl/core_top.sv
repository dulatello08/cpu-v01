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
  
  always_ff @(posedge clk_25mhz) begin
    led[7]   <= rst;                       // LED[7]: Reset Status (ON = in reset)
    led[6]   <= heartbeat[24];             // LED[6]: Heartbeat (toggle approx 0.6s)
    led[5]   <= cpu_halted;                // LED[5]: CPU Halted
    led[4]   <= cpu_dual_issue_active;     // LED[4]: Dual Issue Active
    led[3:0] <= cpu_current_pc[5:2];       // LED[3:0]: PC bits [5:2] (fast toggle)
  end

endmodule : core_top
