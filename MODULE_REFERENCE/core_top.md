# core_top.sv - Synthesis Top Wrapper

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Overview

`core_top` is the FPGA-oriented top-level wrapper.

It instantiates:

- `cpu_core`
- `unified_memory`

and maps board IO (buttons/LEDs/wifi enable).

## Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_25mhz` | input | 1 | Board/system clock |
| `btn` | input | 7 | Button inputs (`btn[0]` used for reset) |
| `led` | output | 8 | Status LEDs |
| `wifi_en` | output | 1 | ESP32 enable control (driven low to disable WiFi side) |

## Key Behavior

### Reset

- Internal reset signal: `rst = ~btn[0]`
- Active-high reset is fed into both `cpu_core` and `unified_memory`

### Memory/Core Wiring

`core_top` directly wires the instruction/data interfaces between `cpu_core` and `unified_memory`.

### LED Mapping

- `led[7]`: reset status
- `led[6]`: heartbeat bit (`heartbeat[24]`)
- `led[5]`: `cpu_halted`
- `led[4]`: `cpu_dual_issue_active`
- `led[3:0]`: `cpu_current_pc[3:0]`

### WiFi Control

- `wifi_en` is hard-driven to `1'b0` to avoid board pin interference from ESP32 on ULX3S.

## Notes

- Clock is currently consumed directly as `clk_25mhz`.
- Memory size is parameterized at 64 KiB in this wrapper (`MEM_SIZE_BYTES=65536`).

## Related Modules

- [cpu_core.md](cpu_core.md)
- [unified_memory.md](unified_memory.md)
- [../DEVELOPER_GUIDE.md](../DEVELOPER_GUIDE.md)
