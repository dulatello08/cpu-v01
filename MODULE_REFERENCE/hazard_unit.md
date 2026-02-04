# Hazard Unit Module Reference

## Overview
The Hazard Unit detects data hazards and generates stall/forwarding controls. It separates **load‑use** detection (ID vs EX loads) from **forwarding** (EX/MEM/WB results).

## Module: `hazard_unit`

### Ports

Key inputs:
- **ID stage** source registers (`id_stage_*`) for load‑use detection
- **EX stage loads** (`ex_*` with `mem_read`) for load‑use detection
- **EX/MEM forwarding sources** (`fwd_ex_*`) for forwarding
- **MEM/WB forwarding sources** (`mem_*`, `wb_*`) for forwarding

Key outputs:
- `stall`, `flush_id`, `flush_ex`
- `forward_a_*`, `forward_b_*` (0/1 slots)

### Hazard Types Detected

1. **Load‑Use Hazard**: ID instruction needs a value from a load currently in EX
2. **RAW Forwarding**: Forward most recent value from EX/MEM/WB to EX

### Stall Logic

The hazard unit stalls when a load in EX will be used by an instruction in ID.

### Forwarding Detection

Forwarding priority: **EX/MEM > MEM/WB > WB** (newest to oldest).

### Usage Example

```systemverilog
hazard_unit hazards (
  .clk(clk),
  .rst(rst),
  // ID/EX for forwarding (current EX consumers)
  .id_rs1_addr_0(id_ex_out_0.rs1_addr),
  .id_rs2_addr_0(id_ex_out_0.rs2_addr),
  .id_valid_0(id_ex_out_0.valid),
  // EX loads for load‑use
  .ex_rd_addr_0(id_ex_out_0.rd_addr),
  .ex_rd_we_0(id_ex_out_0.rd_we),
  .ex_mem_read_0(id_ex_out_0.mem_read),
  .ex_valid_0(id_ex_out_0.valid),
  // EX/MEM for forwarding
  .fwd_ex_rd_addr_0(ex_mem_out_0.rd_addr),
  .fwd_ex_rd_we_0(ex_mem_out_0.rd_we),
  .fwd_ex_valid_0(ex_mem_out_0.valid),
  // MEM/WB + WB forwarding inputs ...
  .stall(hazard_stall),
  .forward_a_0(forward_a_0),
  .forward_b_0(forward_b_0)
);
```

### Implementation Notes

1. **Dual‑Issue Aware**: Checks hazards for both instruction slots
2. **Forwarding Priority**: Correctly selects most recent value if multiple stages write to same register

### Related Modules
- `core_top.sv`: Uses hazard_stall in stall_pipeline logic
- `issue_unit.sv`: Prevents dual-issue when hazards exist
- `execute_stage.sv`: May use forwarding signals
