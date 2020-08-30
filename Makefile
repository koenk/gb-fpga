#
# Makefile for simulations (using verilator) and synthesis for ice40.
#
# Interesting targets are:
#  - run: Run simulation using verilator.
#  - prog: Upload code to an ice40 device.
#
# And for compilation only (implied by above commands):
#  - sim: Build verilator simulation. [default]
#  - bit: Synthesize for ice40 device.
#
# Output is normally silenced/summarized. For full output, specify V=1 (e.g.,
# `make bit V=1`).
#

BITTOP = syn_top
SIMTOP = main

SOURCES = main.v cpu.v bootrom.v lram.v ram.v cart.v ppu.v
BIT_SOURCES := $(BITTOP).v tft.v pll.v $(SOURCES)
SIM_SOURCES = sim_main.cpp gui.c

BOOTROM = dmg_boot.hex
ROM = roms/build/obj.gb

DEV = up5k
PINS = icebreaker.pcf
FREQ = 4.19

SYN = yosys
PNR = nextpnr-ice40
ICEPACK = icepack
ICEPROG = iceprog
VERILATOR = verilator
RM = rm

BUILDDIR = build
BITDIR = $(BUILDDIR)/bit
SIMDIR = $(BUILDDIR)/sim

SYN_FLAGS = -DSYNTHESIS
PNR_FLAGS = --$(DEV) --freq $(FREQ)
VERILATOR_FLAGS = --Mdir $(SIMDIR) -Wall -O2 --cc --top-module $(SIMTOP)

ROMHEX = $(patsubst %.gb,%.hex,$(ROM))

VERILATOR_DIR = /usr/share/verilator/include
CFLAGS := -Wall -Wextra -O2 -ggdb
CXXFLAGS := -I. -I$(SIMDIR) -I$(VERILATOR_DIR) -I$(VERILATOR_DIR)/vltstd \
		   -DVL_PRINTF=printf -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TRACE=0 \
		   -MMD -faligned-new -ggdb -O2 -Wall \
		   -Wno-sign-compare -Wno-uninitialized -Wno-unused-but-set-variable \
		   -Wno-unused-parameter -Wno-unused-variable -Wno-shadow \
		   $(shell pkg-config gtkmm-2.4 --cflags)
LDLIBS = -lm -lstdc++ -lSDL2 $(shell pkg-config gtkmm-2.4 --libs)

SIM_OBJS := $(patsubst %.c,$(SIMDIR)/%.o, \
			$(patsubst %.cpp,$(SIMDIR)/%.o, \
			 $(SIM_SOURCES)))


ifdef DEBUG
	VERILATOR_FLAGS += -DDEBUG
	CXXFLAGS += -DDEBUG
endif

ifdef DEBUG_CPU
	VERILATOR_FLAGS += -DDEBUG_CPU
endif

ifdef DEBUG_PPU
	VERILATOR_FLAGS += -DDEBUG_PPU
endif

ifdef DEBUG_DMA
	VERILATOR_FLAGS += -DDEBUG_DMA
endif

ifndef DO_BOOTROM
	VERILATOR_FLAGS += -DSKIP_BOOTROM
endif


# Verbosity control
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
.PHONY: all sim bit run prog clean test-cpu

all: sim
bit: $(BITDIR)/$(BITTOP).bin
sim: $(SIMDIR)/V$(SIMTOP)

run: sim
	-$(SIMDIR)/V$(SIMTOP) $(ROM)
prog: bit
	$(LOG) [PROG]
	$(ICEPROG) $(BITDIR)/$(BITTOP).bin

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
$(SIMDIR)/%.o: %.c | $(SIMDIR)
	$(LOG) [CC]
	$(CC) $(CFLAGS) -c -o $@ $<
$(SIMDIR)/verilated.o: $(VERILATOR_DIR)/verilated.cpp
	$(LOG) [CXX]
	$(CXX) $(CXXFLAGS) -c -o $@ $<
$(SIMDIR)/V$(SIMTOP): $(SIM_OBJS) $(SIMDIR)/verilated.o $(SIMDIR)/V$(SIMTOP)__ALL.a | $(SIMDIR)
	$(LOG) [LINK]
	$(CXX) $^ -o $@ $(LDLIBS)

#
# Synthesis for ice40
#
$(BITDIR)/$(BITTOP).json: $(BIT_SOURCES) $(BOOTROM) $(ROMHEX) | $(BITDIR)
	$(LOG) [SYN]
	$(SYN) $(SYN_FLAGS) -p "synth_ice40 -top $(BITTOP) -json $@" $<
$(BITDIR)/$(BITTOP).asc: $(BITDIR)/$(BITTOP).json
	$(LOG) [PNR]
	$(PNR) $(PNR_FLAGS) --json $< --pcf $(PINS) --asc $@
$(BITDIR)/$(BITTOP).bin: $(BITDIR)/$(BITTOP).asc
	$(LOG) [BIT]
	$(ICEPACK) $< $@

#
# ROM files for testing.
#
ROMDIR = roms
ROMBUILDDIR = roms/build
include roms/Makefile.inc

%.hex: %.gb
	$(LOG) [HEX]
	hexdump -v -e '32/1 "%02x ""\n"' $< > $@


$(BUILDDIR) $(SIMDIR) $(BITDIR):
	mkdir -p $@

clean:
	@$(RM) -rf $(BUILDDIR)
