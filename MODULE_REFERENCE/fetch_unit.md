# Fetch Unit Module Reference

## Overview
The Fetch Unit retrieves variable-length instructions from unified memory and presents up to two decoded instruction windows per cycle. It does **not** buffer instructions itself; the Instruction Buffer (IB) lives in `cpu_core`. Fetch advances only when the IB accepts instructions.

## Module: `fetch_unit`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Reset signal |
| `branch_taken` | input | 1 | Branch taken signal from execute stage |
| `branch_target` | input | 32 | Branch target address |
| `accept_count` | input | 2 | Number of instructions accepted into IB (0/1/2) |
| `mem_addr` | output | 32 | Memory address for instruction fetch |
| `mem_req` | output | 1 | Memory request signal |
| `mem_rdata` | input | 128 | 16 bytes of instruction data (big-endian) |
| `mem_ack` | input | 1 | Memory acknowledge signal |
| `inst_data_0` | output | 72 | First instruction bytes (up to 9 bytes, padded) |
| `inst_len_0` | output | 4 | First instruction length in bytes |
| `pc_0` | output | 32 | PC of first instruction |
| `valid_0` | output | 1 | First instruction valid |
| `inst_data_1` | output | 72 | Second instruction (for dual-issue) |
| `inst_len_1` | output | 4 | Second instruction length in bytes |
| `pc_1` | output | 32 | PC of second instruction |
| `valid_1` | output | 1 | Second instruction valid |

### Parameters
None.

### Big-Endian Memory Model

Instructions are stored in **big-endian format**:
- Byte at address N is **more significant** than byte at address N+1
- Buffer layout: bits[255:248] = byte 0, bits[247:240] = byte 1, etc.

### Instruction Format

Per the ISA specification (Instructions.md):
- **Byte 0**: Specifier
- **Byte 1**: Opcode
- **Bytes 2+**: Operands (varying length based on specifier)

Instruction lengths range from 2 to 9 bytes.

### Buffer Management

The fetch unit maintains a **two-block window**:

1. **HI buffer** (`buf_hi`): 16 bytes at `buf_base_addr`
2. **LO buffer** (`buf_lo`): next 16 bytes (`buf_base_addr + 16`)
3. **Extraction**: Extract up to 2 instructions from the 32-byte window
4. **Prefetch**: When a shift is predicted, prefetch the next block

### Critical Behavior: Advance on Accept

Fetch advances only when the IB accepts instructions (not when they are consumed by the backend). This decouples frontend progress from backend stalls.

### PC Update Logic

```systemverilog
if (branch_taken) begin
  pc_next = branch_target;  // Branch redirect
end else if (accept_count != 0) begin
  pc_next = pc + accept_len;  // Advance by accepted instruction lengths
end else begin
  pc_next = pc;  // No accept
end
```

### Buffer Shift Direction

The fetch unit does **not** shift an instruction FIFO. It maintains two 16‑byte buffers and moves `buf_lo` into `buf_hi` when `current_pc` crosses a 16‑byte boundary.

### Behavior

1. **Reset**: PC = 0x00000000, buffer empty
2. **Normal Operation**:
   - Fetch 16 bytes when buffer < 16 bytes valid
   - Extract up to 2 instructions from buffer
   - Compute instruction lengths from specifier
   - Output valid instructions to decode stage
3. **Branch**: Flush buffers, redirect PC
4. **No Accept**: Hold PC, keep buffers

### Usage Example

```systemverilog
fetch_unit fetch (
  .clk(clk),
  .rst(rst),
  .branch_taken(branch_taken),
  .branch_target(branch_target),
  .accept_count(accept_count),  // FROM IB
  .mem_addr(mem_if_addr),
  .mem_req(mem_if_req),
  .mem_rdata(mem_if_rdata),
  .mem_ack(mem_if_ack),
  .inst_data_0(fetch_inst_data_0),
  .inst_len_0(fetch_inst_len_0),
  .pc_0(fetch_pc_0),
  .valid_0(fetch_valid_0),
  .inst_data_1(fetch_inst_data_1),
  .inst_len_1(fetch_inst_len_1),
  .pc_1(fetch_pc_1),
  .valid_1(fetch_valid_1)
);
```

### Implementation Notes

1. **Buffer Integrity**: Pending LO prefetch is tracked to avoid mis-routing on block shifts
2. **Instruction Length Decoding**: Computed from specifier byte per ISA spec

### Known Limitations

None. All bugs related to byte consumption and PC advancement have been fixed.

### Related Modules
- `cpu_core.sv`: Instantiates fetch_unit and drives `accept_count` from the IB
- `issue_unit.sv`: Provides issue decisions consumed by the IB/decode pipeline
- `unified_memory.sv`: Provides instruction data
- `decode_unit.sv`: Receives fetched instructions
