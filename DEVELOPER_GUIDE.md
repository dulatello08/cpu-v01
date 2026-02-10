# NeoCore16x32 Developer Guide

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

## Purpose

This guide is the contributor-facing workflow for changing RTL and verification code in this repository.

## Tooling

### Required for Simulation

- `iverilog`
- `vvp`

### Optional for Waveforms

- `surfer` (default in `Makefile`) or GTKWave-compatible viewer

### Optional for FPGA Build

- `sv2v`
- `yosys`
- `nextpnr-ecp5`
- `ecppack`
- `openFPGALoader`

## Project Layout

```text
rtl/                 CPU RTL modules
  neocore_pkg.sv     shared enums/types/helpers
  cpu_core.sv        main pipeline/core integration
  core_top.sv        synth wrapper + board IO
tb/                  testbenches
mem/                 .hex programs for integration/program tests
MODULE_REFERENCE/    per-module technical docs
scripts/             utility scripts (e.g., bin2hex)
build/               generated simulation files
```

## Core Commands

Run from repository root.

```bash
make check-tools
make unit-tests
make core-tests
make all-tests
make run_any PROGRAM=mem/test_mixed_lengths.hex
```

Useful target shortcuts:

```bash
make alu_test
make mul_test
make decode_test
make fetch_test
make branch_test
make regfile_test
make sim
```

## Daily Workflow

1. Sync and inspect local changes.
2. Edit RTL/tests/docs.
3. Run targeted test(s) for changed area.
4. Run `make unit-tests` and `make core-tests` before commit.
5. Update docs when ISA, pipeline, memory behavior, or interfaces change.

## Coding Conventions

- SystemVerilog, 2-space indentation, no tabs.
- `snake_case` for module/signal names.
- `UPPER_CASE` for parameters/constants.
- Type aliases end with `_t`.
- Active-low signals end with `_n`.
- Keep instruction/data byte ordering big-endian across decode/fetch/memory paths.

## Changing the ISA

When adding/changing instructions, update all relevant layers:

1. `rtl/neocore_pkg.sv`
- Opcode enum
- Instruction type classification
- `get_inst_length()`
- `opcode_to_alu_op()` when needed

2. `rtl/decode_unit.sv`
- Decode fields, control bits, register/immediate extraction

3. `rtl/execute_stage.sv`, `rtl/memory_stage.sv`, `rtl/writeback_stage.sv`
- Execution semantics and writeback/flag behavior

4. Tests
- Add/extend unit and integration coverage in `tb/`
- Add/extend `mem/*.hex` programs if needed

5. Documentation
- [ISA_REFERENCE.md](ISA_REFERENCE.md)
- [ARCHITECTURE.md](ARCHITECTURE.md) if programmer-visible behavior changes
- [MODULE_REFERENCE/](MODULE_REFERENCE/README.md) for affected modules

## Debugging Guidance

### Fast Checks

- Confirm opcode/specifier/length consistency in `neocore_pkg.sv`.
- Verify decode outputs match instruction bytes (big-endian order).
- Verify stall/flush behavior around branch/load-use cases.

### Waveform Signals to Watch

- Frontend: `mem_if_addr`, `mem_if_req`, `mem_if_ack`
- Decode/issue: decoded opcodes, `dual_issue_active`, issue decisions
- Hazards: stall/flush/forward controls
- Memory: `mem_data_addr`, `mem_data_req`, `mem_data_we`, `mem_data_ack`
- Writeback: register write enables/addresses/data, `halted`

## FPGA Notes

Build and program:

```bash
make fpga
make prog
```

`core_top.sv` is the synthesis top and maps board signals (buttons/LEDs/wifi control).

## Pre-Commit Checklist

- [ ] Targeted tests for changed module(s) pass.
- [ ] `make unit-tests` passes.
- [ ] `make core-tests` passes.
- [ ] Docs updated for interface/behavior changes.
- [ ] No generated artifacts committed unintentionally.

## Related Docs

- [README.md](README.md)
- [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md)
