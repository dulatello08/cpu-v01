# Branch Unit Module Reference

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Overview

`branch_unit` evaluates branch decisions for branch and subroutine opcodes.

## Module: `branch_unit`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock (unused, retained for consistency) |
| `rst` | input | 1 | Reset (unused, retained for consistency) |
| `opcode` | input | `opcode_e` | Operation selector |
| `operand_a` | input | 16 | Comparison operand A |
| `operand_b` | input | 16 | Comparison operand B |
| `v_flag_in` | input | 1 | Overflow flag input (used by `BRO`) |
| `branch_target` | input | 32 | Computed target address |
| `branch_taken` | output | 1 | Branch decision |
| `branch_pc` | output | 32 | Output target PC (passthrough target) |

## Decision Rules

- Always taken: `OP_B`, `OP_JSR`
- Conditional compare:
  - `OP_BE`: `operand_a == operand_b`
  - `OP_BNE`: `operand_a != operand_b`
  - `OP_BLT`: `operand_a < operand_b` (unsigned)
  - `OP_BGT`: `operand_a > operand_b` (unsigned)
- Flag-based:
  - `OP_BRO`: `v_flag_in == 1`
- Default: not taken

## Implementation Notes

- `branch_pc` is assigned from `branch_target`.
- No internal sequential state; behavior is combinational.
- `clk/rst` are XOR-reduced to suppress unused warnings.

## Related Modules

- [execute_stage.md](execute_stage.md)
- [cpu_core.md](cpu_core.md)
- [../ISA_REFERENCE.md](../ISA_REFERENCE.md)
