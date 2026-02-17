# NeoCore16x32

> [!TIP]
> Docs Home: [DOCS_INDEX.md](DOCS_INDEX.md)

NeoCore16x32 is a dual-issue, in-order CPU written in SystemVerilog.
It is built to be understandable, testable, and surprisingly fast for a small FPGA-friendly core.

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

## Main Flexes

Numbers below are from your `dhrystone.s`-style compact kernel run
(5 iterations, inline flow, no `jsr`/`rts`; so this is not an official Dhrystone score).

- **0.912 issued IPC**
  - ~45.6% of 2-wide theoretical peak
  - ~62,024 instructions issued over 68,009 cycles
- **22.8 MIPS @ 25 MHz** (rounded to **23 MIPS**)
- **Dual-issue hit rate: 28.0% of cycles**
  - Dual issue contributes ~30.6% of all issued instructions
- **Front-end feed is strong**
  - Fetch dual-valid: 63.2%
  - IB dual-valid: 60.3%
- **Main issue limiter is dependencies, not multiply**
  - Issue rejects: data dependency 59.1%, write conflict 36.4%, mem conflict 4.5%
  - `mul restrict`: 0.0%
- **Stalls are mostly memory-side**
  - Stall cycles: memory 10.3%, hazard 1.5%
  - Memory is 87.5% of total stall cycles

LinkedIn-safe headline (with caveat):

- **~23 MIPS at 25 MHz** on a Dhrystone-like kernel
- **~0.825 dMIPS-equivalent** if treated as Dhrystone (non-standard, not official)

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
