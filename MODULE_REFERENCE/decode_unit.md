# Decode Unit Module Reference

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Overview

`decode_unit` decodes one variable-length instruction window (`inst_data`) and emits control, register, and immediate/address fields for downstream issue/execute stages.

In `cpu_core`, two instances are used (slot 0 and slot 1).

## Module: `decode_unit`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst` | input | 1 | Reset |
| `inst_data` | input | 72 | Up to 9 instruction bytes (big-endian packed) |
| `inst_len` | input | 4 | Instruction length (bytes) |
| `pc` | input | 32 | Instruction PC |
| `valid_in` | input | 1 | Input validity |
| `valid_out` | output | 1 | Output validity |
| `opcode` | output | `opcode_e` | Decoded opcode |
| `specifier` | output | 8 | Specifier byte |
| `itype` | output | `itype_e` | Instruction class |
| `alu_op` | output | `alu_op_e` | ALU operation mapping |
| `rs1_addr` | output | 4 | Source register 1 |
| `rs2_addr` | output | 4 | Source register 2 |
| `rd_addr` | output | 4 | Destination register |
| `rd2_addr` | output | 4 | Secondary destination register |
| `immediate` | output | 32 | Immediate value |
| `mem_addr` | output | 32 | Absolute memory address (where applicable) |
| `branch_target` | output | 32 | Decoded branch target address |
| `mov_byte_hi` | output | 1 | MOV byte-high selector |
| `rd_we` | output | 1 | Destination write enable |
| `rd2_we` | output | 1 | Secondary destination write enable |
| `mem_read` | output | 1 | Memory read operation |
| `mem_write` | output | 1 | Memory write operation |
| `mem_size` | output | `mem_size_e` | Access width |
| `is_branch` | output | 1 | Branch operation indicator |
| `is_jsr` | output | 1 | JSR indicator |
| `is_rts` | output | 1 | RTS indicator |
| `is_halt` | output | 1 | HLT indicator |

## Byte Layout Assumption

`inst_data` is interpreted big-endian:

- `inst_data[71:64]` -> byte 0 (specifier)
- `inst_data[63:56]` -> byte 1 (opcode)
- remaining operand bytes follow in order

## Output Intent

- Decodes opcode/specifier into `itype`/`alu_op` via package helpers.
- Extracts register operands and write targets based on opcode + specifier.
- Builds immediate/address/branch-target values in big-endian byte order.
- Emits control bits consumed by issue/execute/memory/writeback paths.

## Notes

- This block is combinational decode logic around package-defined enums/helpers.
- R0 is a normal general-purpose register (not hardwired to zero).

## Related Modules

- [fetch_unit.md](fetch_unit.md)
- [issue_unit.md](issue_unit.md)
- [execute_stage.md](execute_stage.md)
- [neocore_pkg.md](neocore_pkg.md)
