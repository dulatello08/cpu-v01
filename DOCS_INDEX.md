# NeoCore16x32 Documentation Hub

This is the central entry point for project documentation.

## Start Here

- New to the project: [README.md](README.md)
- Implementing RTL changes: [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
- Running verification: [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
- Understanding ISA details: [ISA_REFERENCE.md](ISA_REFERENCE.md)

## Reading Paths

### Architecture-First Path
1. [ARCHITECTURE.md](ARCHITECTURE.md)
2. [PIPELINE.md](PIPELINE.md)
3. [MICROARCHITECTURE.md](MICROARCHITECTURE.md)
4. [MEMORY_SYSTEM.md](MEMORY_SYSTEM.md)
5. [ISA_REFERENCE.md](ISA_REFERENCE.md)

### Contributor Path
1. [README.md](README.md)
2. [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
3. [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md)
4. [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
5. [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md)

### RTL Deep-Dive Path
1. [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md)
2. [rtl/README.md](rtl/README.md)
3. [tb/README.md](tb/README.md)
4. [mem/README.md](mem/README.md)

## Documentation Map

### Project-Level Docs
- [README.md](README.md): High-level overview and quick start.
- [ARCHITECTURE.md](ARCHITECTURE.md): Programmer-visible architecture contract.
- [PIPELINE.md](PIPELINE.md): Pipeline behavior, hazards, and timing.
- [MICROARCHITECTURE.md](MICROARCHITECTURE.md): RTL-level implementation walkthrough.
- [MEMORY_SYSTEM.md](MEMORY_SYSTEM.md): Unified memory behavior and endianness.
- [ISA_REFERENCE.md](ISA_REFERENCE.md): Instruction definitions and encodings.
- [TESTING_AND_VERIFICATION.md](TESTING_AND_VERIFICATION.md): Test strategy and execution.
- [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md): Contributor workflow and coding guidance.
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md): Design rationale and tradeoffs.
- [MICROARCH_OPT.md](MICROARCH_OPT.md): Optimization notes and future ideas.
- [Instructions.md](Instructions.md): Deprecated legacy instruction notes.

### Module Docs
- [MODULE_REFERENCE/README.md](MODULE_REFERENCE/README.md): Module documentation index.

### Directory Guides
- [rtl/README.md](rtl/README.md): RTL file responsibilities.
- [tb/README.md](tb/README.md): Testbench map and execution notes.
- [mem/README.md](mem/README.md): Program image catalog and usage.

## Command Reference (Authoritative)

Run commands from the repository root.

```bash
make check-tools
make unit-tests
make core-tests
make all-tests
make run_any PROGRAM=mem/test_mixed_lengths.hex
make wave
make fpga
make prog
```

## Documentation Conventions

- File paths are repository-relative unless otherwise noted.
- Command examples assume `zsh`/`bash`.
- ISA behavior should be validated against `rtl/neocore_pkg.sv` and RTL modules if conflicts are found.
- If two docs disagree, trust:
  1. RTL (`rtl/*.sv`)
  2. `Makefile`
  3. `ISA_REFERENCE.md`

