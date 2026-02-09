# Multiply Unit Module Reference

> [!TIP]
> Module Index: [README.md](README.md) | Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Overview

`multiply_unit` performs 16x16 multiplication and returns split 32-bit results (`hi`/`lo`).

## Module: `multiply_unit`

### Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock (unused, retained for consistency) |
| `rst` | input | 1 | Reset (unused, retained for consistency) |
| `operand_a` | input | 16 | Multiplicand |
| `operand_b` | input | 16 | Multiplier |
| `is_signed` | input | 1 | `1` signed multiply, `0` unsigned multiply |
| `result_lo` | output | 16 | Lower 16 bits of product |
| `result_hi` | output | 16 | Upper 16 bits of product |

## Behavior

- Signed mode (`is_signed=1`): operands are cast to signed 16-bit values before multiply.
- Unsigned mode (`is_signed=0`): zero-extended multiply is used.
- Product is computed combinationally and split into `result_hi`/`result_lo`.

## Notes

- This module has no internal state.
- `clk/rst` are kept for consistent module interfaces and warning suppression.

## Related Modules

- [execute_stage.md](execute_stage.md)
- [cpu_core.md](cpu_core.md)
- [../ISA_REFERENCE.md](../ISA_REFERENCE.md)
