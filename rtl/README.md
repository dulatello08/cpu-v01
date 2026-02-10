# RTL Directory Guide

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Purpose

`rtl/` contains synthesizable SystemVerilog modules for NeoCore16x32.

## File Map

- `neocore_pkg.sv`: Shared enums, structs, and helper functions.
- `cpu_core.sv`: Main CPU implementation (pipeline, control, and stage integration).
- `core_top.sv`: FPGA top-level wrapper (board IO + memory/core wiring).
- `fetch_unit.sv`: Variable-length instruction fetch frontend.
- `decode_unit.sv`: Instruction decode and control extraction.
- `issue_unit.sv`: Dual-issue eligibility and pairing checks.
- `hazard_unit.sv`: Stall/flush/forwarding control.
- `execute_stage.sv`: ALU/multiply/branch execution path.
- `memory_stage.sv`: Data-memory request/response handling.
- `writeback_stage.sv`: Register/flag commit and halt signaling.
- `register_file.sv`: 16x16 register file with multi-port access.
- `unified_memory.sv`: Dual-port unified memory model.
- `pipeline_regs.sv`: Pipeline register modules.
- `alu.sv`, `multiply_unit.sv`, `branch_unit.sv`: Primitive execution units.

## Related Docs

- [../MODULE_REFERENCE/README.md](../MODULE_REFERENCE/README.md)
- [../MICROARCHITECTURE.md](../MICROARCHITECTURE.md)
- [../PIPELINE.md](../PIPELINE.md)
