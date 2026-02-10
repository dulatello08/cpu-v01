# Program Image Directory Guide

> [!TIP]
> Docs Home: [../DOCS_INDEX.md](../DOCS_INDEX.md)

## Purpose

`mem/` stores `.hex` program images used by integration/program-level simulations.

## Running a Program Image

```bash
make run_any PROGRAM=mem/test_mixed_lengths.hex
```

`core_any_tb` loads the selected file and executes it through the full core/memory path.

## Current Image Set

Representative files in this directory include:

- `test_simple.hex`
- `test_mixed_lengths.hex`
- `test_loop_simple.hex`
- `fib_coretest.hex`
- `do_nothing_coretest.hex`

Additional images are available for instruction-length and movement-path experiments.

## Generation Utility

Use [../scripts/bin2hex.py](../scripts/bin2hex.py) to convert a binary image into `.hex` format.

## Related Docs

- [../TESTING_AND_VERIFICATION.md](../TESTING_AND_VERIFICATION.md)
- [../ISA_REFERENCE.md](../ISA_REFERENCE.md)
