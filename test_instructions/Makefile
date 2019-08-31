BINNAME = test
VERTOP = cpu
VER_SOURCES =
SIM_SOURCES = main.c inputstate.c vcpu.cpp emu_cpu.c disassembler.c

ASM = bootrom.asm

VERILATOR = verilator
RM = rm

VDIR = ..
BDIR = build

VERILATOR_FLAGS = --Mdir $(BDIR) -Wall -O2 --cc --top-module $(VERTOP)
ifdef DEBUG
	VERILATOR_FLAGS += -DDEBUG
endif
ifdef DEBUG_CPU
	VERILATOR_FLAGS += -DDEBUG_CPU
endif

VERILATOR_DIR = /usr/share/verilator/include
CFLAGS   := -O2 -Wall -Wextra -g -MMD
CXXFLAGS := -I. -I$(BDIR) -I$(VERILATOR_DIR) -I$(VERILATOR_DIR)/vltstd \
		   -DVL_PRINTF=printf -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TRACE=0 \
		   -MMD -faligned-new -O2 -Wall -Wno-sign-compare -Wno-uninitialized \
		   -Wno-unused-but-set-variable -Wno-unused-parameter \
		   -Wno-unused-variable -Wno-shadow \
		   $(shell pkg-config gtkmm-2.4 --cflags)
LDLIBS = -lm -lstdc++ $(shell pkg-config gtkmm-2.4 --libs)

OBJS := $(patsubst %.c,$(BDIR)/%.o,$(patsubst %.cpp,$(BDIR)/%.o,$(SIM_SOURCES)))


# Verbosity control
ifndef V
	LOG=@printf "\e[1;32m%s\e[0m $@\n"
	MAKEFLAGS += --silent
else
	LOG=@true
endif

.SUFFIXES: # Disable builtin rules
.PHONY: all sim run clean

all: sim
sim: $(BDIR)/$(BINNAME)

run: sim
	-$(BDIR)/$(BINNAME)

$(BDIR)/V$(VERTOP)__ALL.a: $(VDIR)/$(VERTOP).v $(VER_SOURCES) | $(BDIR)
	$(LOG) [VERILATOR]
	$(VERILATOR) $(VERILATOR_FLAGS) $<
	$(MAKE) -C $(BDIR) -B -f V$(VERTOP).mk
$(BDIR)/%.o: %.c | $(BDIR)
	$(LOG) [CC]
	$(CC) $(CFLAGS) -c -o $@ $<
$(BDIR)/%.o: %.cpp $(BDIR)/V$(VERTOP)__ALL.a | $(BDIR)
	$(LOG) [CXX]
	$(CXX) $(CXXFLAGS) -c -o $@ $<
$(BDIR)/verilated.o: $(VERILATOR_DIR)/verilated.cpp | $(BDIR)
	$(LOG) [CXX]
	$(CXX) $(CXXFLAGS) -c -o $@ $<
$(BDIR)/$(BINNAME): $(OBJS) $(BDIR)/verilated.o $(BDIR)/V$(VERTOP)__ALL.a | $(BDIR)
	$(LOG) [LINK]
	$(CXX) $^ -o $@ $(LDLIBS)

$(BDIR):
	mkdir -p $@

clean:
	@$(RM) -rf $(BDIR)

-include build/*.d
