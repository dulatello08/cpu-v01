# CPU Core Module Reference

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Overview

`cpu_core` is the primary NeoCore16x32 implementation module. It integrates fetch, decode, issue, execute, memory, and writeback behavior with a dual-issue, in-order pipeline.

Pipeline shape:

`IF1 -> IF2 -> IB -> ID -> EX -> MEM -> WB`

## Module: `cpu_core`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Core clock |
| `rst` | input | 1 | Synchronous reset |
| `mem_if_addr` | output | 32 | Instruction fetch address |
| `mem_if_req` | output | 1 | Instruction fetch request |
| `mem_if_rdata` | input | 128 | Instruction fetch return data (16 bytes) |
| `mem_if_ack` | input | 1 | Instruction fetch acknowledge |
| `mem_data_addr` | output | 32 | Data port address |
| `mem_data_wdata` | output | 32 | Data port write data |
| `mem_data_size` | output | 2 | Data access size (`MEM_BYTE/HALF/WORD`) |
| `mem_data_we` | output | 1 | Data write enable |
| `mem_data_req` | output | 1 | Data access request |
| `mem_data_rdata` | input | 32 | Data port read data |
| `mem_data_ack` | input | 1 | Data access acknowledge |
| `halted` | output | 1 | Core halted state |
| `current_pc` | output | 32 | Current frontend PC |
| `dual_issue_active` | output | 1 | High when two instructions issue in cycle |

## Internal Responsibilities

- Tracks architectural flags (`z_flag`, `v_flag`) with updates from WB.
- Instantiates the instruction buffer queue (`ib_queue`, depth 6).
- Instantiates decode path x2 and issue arbitration.
- Instantiates hazard detection and forwarding control.
- Instantiates execute/memory/writeback stages for slot 0 and slot 1.
- Generates branch redirect/flush behavior for frontend recovery.

## IB Queue Behavior

- Fetch can produce up to two instructions per cycle.
- IB enqueues based on free slots and branch/halt/stall conditions.
- Dequeue is driven by consumed issue count (`consumed_count`).
- Branch-taken clears queue state to prevent wrong-path issue.

## Control Highlights

- `stall_pipeline` and `stall_frontend` coordinate backpressure.
- Hazard unit controls load-use stalls and forwarding selections.
- Issue unit determines whether slot 1 may issue this cycle.
- Branch in EX triggers frontend redirect and appropriate flushing.

## Related Modules

- [fetch_unit.md](fetch_unit.md)
- [decode_unit.md](decode_unit.md)
- [issue_unit.md](issue_unit.md)
- [hazard_unit.md](hazard_unit.md)
- [execute_stage.md](execute_stage.md)
- [memory_stage.md](memory_stage.md)
- [writeback_stage.md](writeback_stage.md)
- [core_top.md](core_top.md)
