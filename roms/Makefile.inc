# Partial rules to build ROMs

RGBDS ?=
RGBASM  = $(RGBDS)rgbasm
RGBLINK = $(RGBDS)rgblink
RGBFIX  = $(RGBDS)rgbfix

ROMBUILDDIR ?= build
ROMDIR ?= .

$(ROMBUILDDIR)/%.o: $(ROMDIR)/%.asm | $(ROMBUILDDIR)
	$(LOG) [AS]
	$(RGBASM) -o $@ $^

$(ROMBUILDDIR)/%.gb: $(ROMBUILDDIR)/%.o
	$(LOG) [LINK]
	$(RGBLINK) -o $@ $^
	$(RGBFIX) -v $@

