ROMS = halt test_mem bg

BUILDDIR = build

ROM_FILES := $(patsubst %,$(BUILDDIR)/%.gb,$(ROMS))

# Verbosity control
ifndef V
	LOG=@printf "\e[1;32m%s\e[0m $@\n"
	MAKEFLAGS += --silent
else
	LOG=@true
endif

.PRECIOUS:
.SECONDARY:
.SUFFIXES: # Disable builtin rules
.PHONY: all clean

all: $(ROM_FILES)

include Makefile.inc

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	@rm -rf $(BUILDDIR)
