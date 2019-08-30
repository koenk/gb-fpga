; Expected output:
;   SP  A   BC   DE   HL
;  aaaa 42 dead beef cafe

SECTION "start", ROM0[$0100]
    nop
    jp main

SECTION "main", ROM0[$0150]
main:

    ld C, $ad
    ld E, $ef
    ld L, $fe

 ; 8000-9FFF VRAM
 ; C000-DFFF WRAM
 ; FE00-FE9F OAM
 ; FF80-FFFE HRAM

    ld A, $42
    ld [$FE54], A
    ld A, $de
    ld [$8123], A
    ld A, $be
    ld [$C123], A
    ld A, $ca
    ld [$FF85], A

    ld A, [$8123]
    ld B, A
    ld A, [$C123]
    ld D, A
    ld A, [$FF85]
    ld H, A
    ld A, [$FE54]

    ld SP, $AAAA
    halt
