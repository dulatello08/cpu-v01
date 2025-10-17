# ===== ULX3S 85F Makefile (yosys + nextpnr-ecp5 + ecppack + openFPGALoader) =====

# ---- Project ----
TOP       ?= top
SRC       := $(wildcard *.v *.sv)
LPF       ?= ulx3s_85f.lpf

# ---- Device (ULX3S 85F = LFE5U-85F-6-CABGA381) ----
DEVICE_OPTS := --85k --package CABGA381 --speed 6

# ---- Tools (override on cmdline if needed) ----
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
ECPPACK   ?= ecppack
PROG      ?= openFPGALoader
PROG_FLAGS?= -b ulx3s

# ---- Build artifacts ----
BUILD     := build
JSON      := $(BUILD)/$(TOP).json
CFG       := $(BUILD)/$(TOP).config
BIT_SRAM  := $(BUILD)/$(TOP)_sram.bit

.PHONY: all bit sram svf prog flash clean dirs

all: bit

dirs:
	@mkdir -p $(BUILD)

# 1) Synthesis
$(JSON): $(SRC) $(LPF) | dirs
	$(YOSYS) -p 'read_verilog -sv $(SRC); synth_ecp5 -top $(TOP) -json $(JSON)'

# 2) Place & Route
$(CFG): $(JSON) $(LPF)
	$(NEXTPNR) --json $(JSON) --lpf $(LPF) $(DEVICE_OPTS) --textcfg $(CFG)

# 3) Bitstreams
$(BIT_SRAM): $(CFG)
	$(ECPPACK) $(CFG) $(BIT_SRAM)

$(SVF): $(CFG)
	$(ECPPACK) --svf $(SVF) $(CFG)

# Convenience aliases
bit: $(BIT_SRAM)
sram: $(BIT_SRAM)

# 4) Program to SRAM (volatile)
prog: $(BIT_SRAM)
	$(PROG) $(PROG_FLAGS) $(BIT_SRAM)

# 5) Program Flash (persistent across reboots)
flash: $(BIT_SRAM)
	$(PROG) $(PROG_FLAGS) -f $(BIT_SRAM) --unprotect-flash

clean:
	rm -rf $(BUILD)