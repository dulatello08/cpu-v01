# Testbench Directory Guide

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Purpose

`tb/` contains unit and integration testbenches for the NeoCore16x32 RTL.

## Makefile-Integrated Testbenches

- `alu_tb.sv`
- `multiply_unit_tb.sv`
- `decode_unit_tb.sv`
- `fetch_unit_tb.sv`
- `branch_unit_tb.sv`
- `register_file_tb.sv`
- `core_unified_tb.sv`
- `core_any_tb.sv`

## Additional Testbenches

- `memory_stage_tb.sv`
- `unified_memory_tb.sv`
- `reproduce_fetch_perf.sv`

These can be compiled manually when needed and are not part of default `make unit-tests` / `make core-tests`.

## Typical Commands

```bash
make unit-tests
make core-tests
make run_any PROGRAM=mem/test_simple.hex
```

## Artifacts

Simulation outputs (`.vvp`, `.vcd`) are generated in `build/`.

## Related Docs

- [../TESTING_AND_VERIFICATION.md](../TESTING_AND_VERIFICATION.md)
- [../DEVELOPER_GUIDE.md](../DEVELOPER_GUIDE.md)
