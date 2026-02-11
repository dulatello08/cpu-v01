# Instruction Buffer Queue Module Reference

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)


## Overview
`ib_queue` provides a small FIFO between fetch and decode. It accepts up to two
instructions per cycle and dequeues up to two per cycle, decoupling the frontend
from backend stalls.

## Module: `ib_queue`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Reset signal |
| `flush` | input | 1 | Flush the queue (taken branch) |
| `stall` | input | 1 | Frontend stall (prevents dequeue) |
| `halted` | input | 1 | Halt condition (prevents enqueue) |
| `in0` | input | `if_id_t` | First fetched instruction |
| `in1` | input | `if_id_t` | Second fetched instruction |
| `consume_count` | input | 2 | Number of instructions to dequeue (0/1/2) |
| `accept_count` | output | 2 | Number of instructions accepted (0/1/2) |
| `out0` | output | `if_id_t` | Oldest instruction |
| `out1` | output | `if_id_t` | Next instruction |
| `count` | output | 3 | Current occupancy (0-6) |

### Behavior

- **Enqueue**: Accepts up to two instructions if space is available and `flush/ halted` are deasserted.
- **Dequeue**: Provides up to two instructions when not stalled; respects `consume_count`.
- **Flush**: Clears all entries on branch redirects.
- **Occupancy**: `count` reflects number of valid entries; `accept_count` is 0 if the queue lacks space.

### Notes

- Depth is fixed at 6 entries.
- FIFO behavior is implemented as explicit shift logic (no RAM).
- `accept_count` drives fetch advancement, keeping the frontend aligned with IB capacity.

### Related Modules
- `fetch_unit.sv`: Supplies `in0/in1` and consumes `accept_count`
- `decode_unit.sv`: Receives instructions from `out0/out1`
- `cpu_core.sv`: Instantiates and wires the IB queue
