# Partial rules to build ROMs

RGBDS ?=
RGBASM  = $(RGBDS)rgbasm
RGBLINK = $(RGBDS)rgblink
RGBFIX  = $(RGBDS)rgbfix

BUILDDIR ?= build
ROMDIR ?= .

$(BUILDDIR)/%.o: $(ROMDIR)/%.asm | $(BUILDDIR)
	$(LOG) [AS]
	$(RGBASM) -o $@ $^

$(BUILDDIR)/%.gb: $(BUILDDIR)/%.o
	$(LOG) [LINK]
	$(RGBLINK) -o $@ $^
	$(RGBFIX) -v $@

