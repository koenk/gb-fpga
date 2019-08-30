#
# This makefile can build for 3 different targets: simulation using verilator,
# simulation using iverilog, and synthesis for ice40.
#
# Interesting targets are:
#  - run: Run simulation using verilator.
#  - prog: Upload code to an ice40 device.
#  - icarus-run: Run simulation using Icarus.
#
# And for compilation only (implied by the above):
#  - sim: Build verilator simulation. [default]
#  - bit: Synthesize for ice40 device.
#  - icarus: Build icarus simulation.
#
# Output is normally silenced/summarized. For full output, specify V=1 (e.g.,
# `make bit V=1`).
#

BITTOP = syn_top
SIMTOP = main
ICARUSTOP = icarus_top

SOURCES = main.v cpu.v bootrom.v lram.v ram.v cart.v ppu.v
SIM_SOURCES = sim_main.cpp

BOOTROM = dmg_boot.hex
ROM = build/halt.hex
ROMDIR = roms

DEV = hx1k
PINS = icestick.pcf
#DEV = up5k
#PINS = icebreaker.pcf

SYN = yosys
PNR = nextpnr-ice40
ICEPACK = icepack
ICEPROG = iceprog
VERILATOR = verilator
IVERILOG = iverilog
ICARUS_RUN = vvp
RM = rm

BUILDDIR = build
BITDIR = $(BUILDDIR)/bit
SIMDIR = $(BUILDDIR)/sim

SYN_FLAGS = -DSYNTHESIS
PNR_FLAGS = --$(DEV)
VERILATOR_FLAGS = --Mdir $(SIMDIR) -Wall -O2 --cc --top-module $(SIMTOP) -DROMFILE="$(ROM)"
IVERILOG_FLAGS = -DROMFILE="$(ROM)"

VERILATOR_DIR = /usr/share/verilator/include
CXXFLAGS := -I. -I$(SIMDIR) -I$(VERILATOR_DIR) -I$(VERILATOR_DIR)/vltstd \
		   -DVL_PRINTF=printf -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TRACE=0 \
		   -MMD -faligned-new -O2 -Wall -Wno-sign-compare -Wno-uninitialized \
		   -Wno-unused-but-set-variable -Wno-unused-parameter \
		   -Wno-unused-variable -Wno-shadow \
		   $(shell pkg-config gtkmm-2.4 --cflags)
LDLIBS = -lm -lstdc++ $(shell pkg-config gtkmm-2.4 --libs)

BIT_SOURCES := $(BITTOP).v $(SOURCES)
SIM_OBJS := $(patsubst %.cpp,$(SIMDIR)/%.o,$(SIM_SOURCES))


# Verbosity control
#ifneq ($(filter %s s%,$(MAKEFLAGS)),)
ifndef V
	LOG=@printf "\e[1;32m%s\e[0m $@\n"
	SYN_FLAGS += -q
	PNR_FLAGS += -q
	MAKEFLAGS += --silent
else
	LOG=@true
endif

.SECONDARY: # Don't remove intermediate files
.SUFFIXES: # Disable builtin rules
.PHONY: all sim bit icarus run prog icarus-run clean test-cpu

all: sim
bit: $(BITDIR)/$(BITTOP).bin
sim: $(SIMDIR)/V$(SIMTOP)
icarus: $(BUILDDIR)/icarus

run: sim
	-$(SIMDIR)/V$(SIMTOP)
prog: bit
	$(LOG) [PROG]
	$(ICEPROG) $(BITDIR)/$(BITTOP).bin
icarus-run: icarus
	$(ICARUS_RUN) $(BUILDDIR)/icarus

test-cpu:
	$(MAKE) -C test_instructions run

#
# Verilator simulation
#
# Verilator doesn't like nested directories, so we build the exe ourselves too.
#
$(SIMDIR)/V$(SIMTOP)__ALL.a: $(SIMTOP).v $(SOURCES) $(BOOTROM) $(ROM) | $(SIMDIR)
	$(LOG) [VERILATOR]
	$(VERILATOR) $(VERILATOR_FLAGS) $<
	$(MAKE) -C $(SIMDIR) -B -f V$(SIMTOP).mk
$(SIMDIR)/%.o: %.cpp $(SIMDIR)/V$(SIMTOP)__ALL.a
	$(LOG) [CXX]
	$(CXX) $(CXXFLAGS) -c -o $@ $<
$(SIMDIR)/verilated.o: $(VERILATOR_DIR)/verilated.cpp
	$(LOG) [CXX]
	$(CXX) $(CXXFLAGS) -c -o $@ $<
$(SIMDIR)/V$(SIMTOP): $(SIM_OBJS) $(SIMDIR)/verilated.o $(SIMDIR)/V$(SIMTOP)__ALL.a | $(SIMDIR)
	$(LOG) [LINK]
	$(CXX) $^ -o $@ $(LDLIBS)

#
# Synthesis for ice40
#
$(BITDIR)/$(BITTOP).json: $(BIT_SOURCES) $(BOOTROM) $(ROM) | $(BITDIR)
	$(LOG) [SYN]
	$(SYN) $(SYN_FLAGS) -p "synth_ice40 -top $(BITTOP) -json $@" $<
$(BITDIR)/$(BITTOP).asc: $(BITDIR)/$(BITTOP).json
	$(LOG) [PNR]
	$(PNR) $(PNR_FLAGS) --json $< --pcf $(PINS) --asc $@
$(BITDIR)/$(BITTOP).bin: $(BITDIR)/$(BITTOP).asc
	$(LOG) [BIT]
	$(ICEPACK) $< $@

#
# Icarus simulation
#
$(BUILDDIR)/icarus: $(ICARUSTOP).v $(SOURCES) $(BOOTROM) $(ROM) | $(BUILDDIR)
	$(LOG) [IVERILOG]
	$(IVERILOG) -o $@ $< $(IVERILOG_FLAGS)

#
# ROM files for testing.
#
include roms/Makefile.inc

%.hex: %.gb
	$(LOG) [HEX]
	hexdump -v -e '32/1 "%02x ""\n"' $< > $@


$(BUILDDIR) $(SIMDIR) $(BITDIR):
	mkdir -p $@

clean:
	@$(RM) -rf $(BUILDDIR)
