SECTION "start", ROM0[$0100]
    nop
    jp main

SECTION "main", ROM0[$0150]
main:
    halt
