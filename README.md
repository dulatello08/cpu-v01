# NeoCore16x32 CPU - SystemVerilog Implementation

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

## Overview

NeoCore16x32 is a dual-issue, in-order CPU implemented in SystemVerilog with:

- 7-stage pipeline: IF1 -> IF2 -> IB -> ID -> EX -> MEM -> WB
- 16-bit register datapath and 32-bit addressing
- Variable-length instructions (2 to 9 bytes)
- Big-endian instruction/data encoding
- Unified (Von Neumann) memory with separate IF and DATA ports

The project includes simulation-first workflows (`iverilog`/`vvp`) and an optional FPGA flow for ULX3S (ECP5).

## Quick Start

Run from repository root:

```bash
make check-tools
make unit-tests
make core-tests
make run_any PROGRAM=mem/test_mixed_lengths.hex
```

Useful extras:

```bash
make all-tests
make wave
make fpga
make prog
```

## Repository Layout

```text
rtl/                 RTL modules
tb/                  Testbenches
mem/                 Program hex images
MODULE_REFERENCE/    Per-module documentation
scripts/             Helper scripts (e.g. binary-to-hex conversion)
build/               Generated simulation artifacts (created by Makefile)
```

Directory guides:

- [rtl/README.md](rtl/README.md)
- [tb/README.md](tb/README.md)
- [mem/README.md](mem/README.md)

## Architecture Snapshot

- 16 x 16-bit general-purpose registers (R0-R15)
- Dual decode/issue path with hazard checks in `issue_unit`
- Forwarding and load-use stall handling in `hazard_unit`
- True dual-port unified memory:
  - IF port: 128-bit (16-byte) instruction fetch window
  - DATA port: byte/half/word load-store access
- Branches resolved in EX with front-end flush/redirect behavior

## Build and Test Targets

Primary targets in `Makefile`:

- `make check-tools`
- `make unit-tests`
- `make core-tests`
- `make all-tests`
- `make run_any PROGRAM=mem/<program>.hex`
- `make wave` / `make wave_alu`
- `make clean`

Per-test shortcuts:

- `make alu_test`
- `make mul_test`
- `make decode_test`
- `make fetch_test`
- `make branch_test`
- `make regfile_test`
- `make sim`

## FPGA Flow (Optional)

The ULX3S-oriented flow is:

```bash
make fpga   # build bitstream
make prog   # program board with openFPGALoader
```

Tools used by this flow include `sv2v`, `yosys`, `nextpnr-ecp5`, `ecppack`, and `openFPGALoader`.

## Documentation

Start at [DOCS_INDEX.md](DOCS_INDEX.md), then choose a path:

- Architecture spec: [ARCHITECTURE.md](ARCHITECTURE.md)
- Pipeline behavior: [PIPELINE.md](PIPELINE.md)
- RTL implementation detail: [MICROARCHITECTURE.md](MICROARCHITECTURE.md)
- ISA detail: [ISA_REFERENCE.md](ISA_REFERENCE.md)
- Memory model: [MEMORY_SYSTEM.md](MEMORY_SYSTEM.md)
- Testing workflow: [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- Contributor workflow: [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
- Module docs: [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)

## Notes

- Legacy instruction notes in [Instructions.md](Instructions.md) are deprecated. Use [ISA_REFERENCE.md](ISA_REFERENCE.md).
- If documentation conflicts with RTL behavior, treat RTL and `Makefile` as the current source of truth.

## License

This project is licensed under GPL-3.0. See [LICENSE](LICENSE).
