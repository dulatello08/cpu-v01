# NeoCore 16x32 CPU - Makefile
# Build and test SystemVerilog RTL using Icarus Verilog
#
# Prerequisites:
#   - Icarus Verilog (iverilog, vvp)
#   - GTKWave (optional, for waveform viewing)
#
# Quick Start:
#   make check-tools    # Verify required tools are installed
#   make unit-tests     # Run all unit tests
#   make core-tests     # Run core integration tests
#   make all-tests      # Run everything
#   make clean          # Remove build artifacts
#
# For more information, see TESTING_AND_VERIFICATION.md

# Directories
RTL_DIR = rtl
TB_DIR = tb
BUILD_DIR = build

# Tools
IVERILOG = iverilog
VVP = vvp
GTKWAVE = surfer

# Compiler flags
IVFLAGS = -g2012 -Wall -Winfloop
IVFLAGS += -I$(RTL_DIR)

# ============================================================================
# Tool Verification
# ============================================================================

.PHONY: check-tools
check-tools:
	@echo "Checking for required tools..."
	@which $(IVERILOG) > /dev/null || (echo "ERROR: iverilog not found. Install with: sudo apt-get install iverilog" && exit 1)
	@which $(VVP) > /dev/null || (echo "ERROR: vvp not found. Install with: sudo apt-get install iverilog" && exit 1)
	@echo "✓ Icarus Verilog found: $$($(IVERILOG) -V | head -1)"
	@which $(GTKWAVE) > /dev/null && echo "✓ GTKWave found (optional)" || echo "  GTKWave not found (optional, for waveform viewing)"
	@echo "All required tools are available."

# Source files
PKG_SRC = $(RTL_DIR)/neocore_pkg.sv

RTL_SRCS = \
	$(PKG_SRC) \
	$(RTL_DIR)/alu.sv \
	$(RTL_DIR)/multiply_unit.sv \
	$(RTL_DIR)/branch_unit.sv \
	$(RTL_DIR)/register_file.sv \
	$(RTL_DIR)/decode_unit.sv \
	$(RTL_DIR)/fetch_unit.sv \
	$(RTL_DIR)/pipeline_regs.sv \
	$(RTL_DIR)/hazard_unit.sv \
	$(RTL_DIR)/issue_unit.sv \
	$(RTL_DIR)/execute_stage.sv \
	$(RTL_DIR)/memory_stage.sv \
	$(RTL_DIR)/writeback_stage.sv \
	$(RTL_DIR)/unified_memory.sv \
	$(RTL_DIR)/cpu_core.sv \
	$(RTL_DIR)/core_top.sv

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	@echo "Created build directory: $(BUILD_DIR)"

# ============================================================================
# Unit Tests
# ============================================================================

# ALU Testbench
alu_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s alu_tb \
		-o $(BUILD_DIR)/alu_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/alu.sv $(TB_DIR)/alu_tb.sv

run_alu_tb: alu_tb
	cd $(BUILD_DIR) && $(VVP) alu_tb.vvp

# Register File Testbench
register_file_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s register_file_tb \
		-o $(BUILD_DIR)/register_file_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/register_file.sv $(TB_DIR)/register_file_tb.sv

run_register_file_tb: register_file_tb
	cd $(BUILD_DIR) && $(VVP) register_file_tb.vvp

# Multiply Unit Testbench
multiply_unit_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s multiply_unit_tb \
		-o $(BUILD_DIR)/multiply_unit_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/multiply_unit.sv $(TB_DIR)/multiply_unit_tb.sv

run_multiply_unit_tb: multiply_unit_tb
	cd $(BUILD_DIR) && $(VVP) multiply_unit_tb.vvp

# Branch Unit Testbench
branch_unit_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s branch_unit_tb \
		-o $(BUILD_DIR)/branch_unit_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/branch_unit.sv $(TB_DIR)/branch_unit_tb.sv

run_branch_unit_tb: branch_unit_tb
	cd $(BUILD_DIR) && $(VVP) branch_unit_tb.vvp

# Decode Unit Testbench
decode_unit_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s decode_unit_tb \
		-o $(BUILD_DIR)/decode_unit_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/decode_unit.sv $(TB_DIR)/decode_unit_tb.sv

run_decode_unit_tb: decode_unit_tb
	cd $(BUILD_DIR) && $(VVP) decode_unit_tb.vvp

# Fetch Unit Testbench
fetch_unit_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s fetch_unit_tb \
		-o $(BUILD_DIR)/fetch_unit_tb.vvp \
		$(PKG_SRC) $(RTL_DIR)/fetch_unit.sv $(TB_DIR)/fetch_unit_tb.sv

run_fetch_unit_tb: fetch_unit_tb
	cd $(BUILD_DIR) && $(VVP) fetch_unit_tb.vvp

# Core Testbench (unified memory)
core_unified_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s core_unified_tb \
		-o $(BUILD_DIR)/core_unified_tb.vvp \
		$(RTL_SRCS) $(TB_DIR)/core_unified_tb.sv

run_core_unified_tb: core_unified_tb
	cd $(BUILD_DIR) && $(VVP) core_unified_tb.vvp

# Core Any Program Testbench (loads program from hex file)
core_any_tb: $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s core_any_tb \
		-o $(BUILD_DIR)/core_any_tb.vvp \
		$(RTL_SRCS) $(TB_DIR)/core_any_tb.sv 2>&1 | grep -v "sorry"

run_core_any_tb: core_any_tb
	@if [ -z "$(PROGRAM)" ]; then \
		echo "ERROR: PROGRAM variable not set."; \
		echo "Usage: make run_core_any_tb PROGRAM=path/to/program.hex"; \
		exit 1; \
	fi
	@if [ ! -f "$(PROGRAM)" ]; then \
		echo "ERROR: Program file '$(PROGRAM)' not found."; \
		exit 1; \
	fi
	@echo "Running program: $(PROGRAM)"
	cd $(BUILD_DIR) && $(VVP) core_any_tb.vvp +PROGRAM=../$(PROGRAM) $(VVPARGS)

# Shortcut: run_any with PROGRAM variable
run_any: run_core_any_tb

# ============================================================================
# Run all tests
# ============================================================================

# Individual test runners with VCD
alu_test: run_alu_tb
mul_test: run_multiply_unit_tb  
decode_test: run_decode_unit_tb
fetch_test: run_fetch_unit_tb
branch_test: run_branch_unit_tb
regfile_test: run_register_file_tb
sim: run_core_unified_tb

# Run all unit tests
.PHONY: unit-tests
unit-tests: run_alu_tb run_register_file_tb run_multiply_unit_tb run_branch_unit_tb run_decode_unit_tb run_fetch_unit_tb
	@echo ""
	@echo "========================================"
	@echo "All unit tests completed successfully!"
	@echo "========================================"

# Run core integration tests
.PHONY: core-tests
core-tests: run_core_unified_tb
	@echo ""
	@echo "========================================"
	@echo "Core integration tests passed!"
	@echo "========================================"



# Run all tests
.PHONY: all-tests
all-tests: unit-tests core-tests
	@echo ""
	@echo "========================================"
	@echo "ALL TESTS PASSED!"
	@echo "========================================"



# Default target
.PHONY: default
default: check-tools
	@echo "NeoCore16x32 CPU Build System"
	@echo "============================="
	@echo ""
	@echo "Available targets:"
	@echo "  make check-tools     - Verify required tools are installed"
	@echo "  make unit-tests      - Run all unit tests (ALU, registers, etc.)"
	@echo "  make core-tests      - Run core integration tests"
	@echo "  make all-tests       - Run all standard tests"

	@echo "  make clean           - Remove build artifacts"
	@echo ""
	@echo "Individual unit tests:"
	@echo "  make alu_test        - ALU testbench"
	@echo "  make mul_test        - Multiply unit testbench"
	@echo "  make decode_test     - Decode unit testbench"
	@echo "  make fetch_test      - Fetch unit testbench"
	@echo "  make branch_test     - Branch unit testbench"
	@echo "  make regfile_test    - Register file testbench"
	@echo ""
	@echo "Integration tests:"
	@echo "  make sim             - Run core unified testbench"
	@echo "  make run_any PROGRAM=file.hex - Run any program from hex file"
	@echo ""
	@echo "Waveform viewing:"
	@echo "  make wave            - View core unified test waveforms"
	@echo "  make wave_alu        - View ALU test waveforms"
	@echo ""
	@echo "For more information, see TESTING_AND_VERIFICATION.md"

# View waveforms with GTKWave
wave: $(BUILD_DIR)/core_unified_tb.vcd
	$(GTKWAVE) $(BUILD_DIR)/core_unified_tb.vcd &

wave_alu: $(BUILD_DIR)/alu_tb.vcd
	$(GTKWAVE) $(BUILD_DIR)/alu_tb.vcd &

# ============================================================================
# Clean
# ============================================================================



# ============================================================================
# FPGA Implementation (Lattice ECP5 - ULX3S)
# ============================================================================

# Convert SystemVerilog to Verilog using sv2v
# We combine everything into one file to handle packages/interfaces correctly
build/*.v: $(RTL_SRCS)
	@mkdir -p $(BUILD_DIR)
	sv2v -w $(BUILD_DIR) $(RTL_SRCS)
# Synthesis (Yosys) using the converted Verilog file
core_top.json: build/*.v
	yosys -p "read_verilog build/*.v; synth_ecp5 -top core_top -json core_top.json"

# Place and Route (Nextpnr)
core_top.config: core_top.json ulx3s-85f-min.lpf
	nextpnr-ecp5 --85k --package CABGA381 --json $< --lpf ulx3s-85f-min.lpf --textcfg $@ --threads 12

# Bitstream Generation (Ecppack)
core_top.bit: core_top.config
	ecppack $< $@

# Upload to FPGA
prog: core_top.bit
	openFPGALoader --board ulx3s $<

# Build Bitstream only
fpga: core_top.bit

clean:
	rm -rf $(BUILD_DIR) *.json *.config *.bit *.svf

.PHONY: default check-tools clean \
        unit-tests core-tests all-tests \
        alu_test mul_test decode_test fetch_test branch_test regfile_test sim run_any \
        wave wave_alu \
        alu_tb run_alu_tb register_file_tb run_register_file_tb \
        multiply_unit_tb run_multiply_unit_tb branch_unit_tb run_branch_unit_tb \
        decode_unit_tb run_decode_unit_tb fetch_unit_tb run_fetch_unit_tb core_unified_tb run_core_unified_tb \
        core_any_tb run_core_any_tb \
        fpga prog
