# Module Reference Documentation

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

This directory contains module-level references for the NeoCore16x32 RTL.

## Core Integration

- [cpu_core.sv](cpu_core.md): Main pipeline/core implementation.
- [core_top.sv](core_top.md): Synthesis wrapper and board-level integration.

## Frontend and Control

- [fetch_unit.sv](fetch_unit.md): Variable-length instruction fetch.
- [ib_queue.sv](ib_queue.md): Instruction buffer between fetch and decode.
- [decode_unit.sv](decode_unit.md): Instruction decode and control extraction.
- [issue_unit.sv](issue_unit.md): Dual-issue eligibility logic.
- [hazard_unit.sv](hazard_unit.md): Stall/flush/forward controls.

## Pipeline Stages

- [execute_stage.sv](execute_stage.md)
- [memory_stage.sv](memory_stage.md)
- [writeback_stage.sv](writeback_stage.md)
- [pipeline_regs.sv](pipeline_regs.md)

## Execution Units

- [alu.sv](alu.md)
- [multiply_unit.sv](multiply_unit.md)
- [branch_unit.sv](branch_unit.md)

## Storage and Shared Definitions

- [register_file.sv](register_file.md)
- [unified_memory.sv](unified_memory.md)
- [neocore_pkg.sv](neocore_pkg.md)

## Hierarchy Snapshot

```text
core_top
└── cpu_core
    ├── fetch_unit
    ├── ib_queue
    ├── decode_unit x2
    ├── issue_unit
    ├── register_file
    ├── hazard_unit
    ├── execute_stage
    │   ├── alu x2
    │   ├── multiply_unit x2
    │   └── branch_unit x2
    ├── memory_stage
    ├── writeback_stage
    ├── pipeline_regs (id_ex/ex_mem/mem_wb x2)
    └── unified_memory (instantiated in core_top)
```

## Related Project Docs

- [../README.md](../README.md)
- [../ARCHITECTURE.md](../ARCHITECTURE.md)
- [../MICROARCHITECTURE.md](../MICROARCHITECTURE.md)
- [../PIPELINE.md](../PIPELINE.md)
