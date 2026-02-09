# NeoCore16x32 Testing and Verification Guide

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

## Scope

This guide documents the current, repository-backed verification workflow.
All commands assume repository root.

## Prerequisites

Required:

- `iverilog`
- `vvp`

Optional:

- `surfer` (used by `make wave` / `make wave_alu`)

Quick check:

```bash
make check-tools
```

## Standard Test Flow

```bash
make unit-tests
make core-tests
make all-tests
```

Run an arbitrary memory program in `core_any_tb`:

```bash
make run_any PROGRAM=mem/test_mixed_lengths.hex
```

## Test Targets

### Unit Tests (Makefile integrated)

- `make alu_test`
- `make mul_test`
- `make decode_test`
- `make fetch_test`
- `make branch_test`
- `make regfile_test`

Batch target:

- `make unit-tests`

### Integration Tests (Makefile integrated)

- `make sim` (alias for `core_unified_tb` run)
- `make core-tests`
- `make run_any PROGRAM=mem/<file>.hex` (via `core_any_tb`)

### Additional Testbenches in `tb/`

These benches exist but are not wired into default Make targets:

- `tb/memory_stage_tb.sv`
- `tb/unified_memory_tb.sv`
- `tb/reproduce_fetch_perf.sv`

Use manual compile/run when needed.

## Artifacts and Waveforms

Generated files are placed under `build/`.

Open recent waveforms:

```bash
make wave
make wave_alu
```

Clean generated artifacts:

```bash
make clean
```

## Verification Strategy

The project currently uses:

1. Unit-level validation per major functional block.
2. Integrated core validation (`core_unified_tb`).
3. Program-image execution checks (`core_any_tb` + `mem/*.hex`).

Recommended pre-merge minimum:

1. `make unit-tests`
2. `make core-tests`
3. At least one `make run_any PROGRAM=...` case relevant to your change

## Failure Triage

When a test fails, check in this order:

1. Opcode/specifier length consistency in `rtl/neocore_pkg.sv`
2. Decode outputs and operand extraction in `rtl/decode_unit.sv`
3. Hazard/forwarding controls in `rtl/hazard_unit.sv`
4. Memory-stage request/ack handshake in `rtl/memory_stage.sv`
5. Program image endianness and encoding in `mem/*.hex`

## CI Example (Reference)

```yaml
name: NeoCore16x32 CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Icarus Verilog
        run: sudo apt-get update && sudo apt-get install -y iverilog
      - name: Run project tests
        run: |
          make check-tools
          make all-tests
```

## Related Docs

- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
- [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
- [PIPELINE.md](PIPELINE.md)
