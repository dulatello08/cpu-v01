# NeoCore16x32

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

NeoCore16x32 is a dual-issue, in-order CPU written in SystemVerilog.
It is built to be understandable, testable, and fast enough to punch above its area class on FPGA.

## What It Is

- 7-stage pipeline: `IF1 -> IF2 -> IB -> ID -> EX -> MEM -> WB`
- 16-bit register datapath with 32-bit addressing
- Variable-length instructions (`2` to `9` bytes)
- Big-endian instruction and data model
- Unified (Von Neumann) memory with true dual-port access:
  - IF port: 128-bit (16-byte) fetch window
  - DATA port: byte/half/word load-store

## Quick Start

Run from repo root:

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

## Why This Core is fast

Measured on a Dhrystone-style compact kernel (`1000` iterations, inline flow, no `jsr`/`rts`):

- **~23 MIPS at just 25 MHz**  
  Efficient, clean in-order dual-issue that converts modest clock into real throughput.
- **Dual-issue that actually shows up in silicon math**  
  Nearly a third of issued work comes from slot 2, not theoretical marketing IPC.
- **Frontend and execute path stay aggressive under load**  
  Fetch/IB keep dual-valid rates high while multiply restrictions stay at zero.
- **NeoCore16x32 delivers ~23 MIPS @ 25 MHz and ~0.825 dMIPS-equivalent on a Dhrystone-like kernel**  
  (non-standard run, so treated as directional performance, not official Dhrystone certification)

## Repo Layout

```text
rtl/                 RTL modules
tb/                  Testbenches
mem/                 Program hex images
MODULE_REFERENCE/    Per-module docs
scripts/             Helpers (e.g. bin2hex)
build/               Generated sim artifacts
```

Directory guides:

- [rtl/README.md](rtl/README.md)
- [tb/README.md](tb/README.md)
- [mem/README.md](mem/README.md)

## Docs Map

Start here: [DOCS_INDEX.md](DOCS_INDEX.md)

- Architecture contract: [ARCHITECTURE.md](ARCHITECTURE.md)
- Pipeline behavior: [PIPELINE.md](PIPELINE.md)
- RTL walk-through: [MICROARCHITECTURE.md](MICROARCHITECTURE.md)
- ISA reference: [ISA_REFERENCE.md](ISA_REFERENCE.md)
- Memory model: [MEMORY_SYSTEM.md](MEMORY_SYSTEM.md)
- Test flow: [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- Contributor guide: [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
- Module docs: [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)

## Notes

- Legacy notes in [Instructions.md](Instructions.md) are deprecated. Use [ISA_REFERENCE.md](ISA_REFERENCE.md).
- If docs and behavior ever disagree, trust RTL and the `Makefile`.

## License

GPL-3.0. See [LICENSE](LICENSE).
