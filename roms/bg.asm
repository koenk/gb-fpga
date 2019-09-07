;
; Display a scrolling background with a checkerboard pattern
;

LCDC    equ $ff40
SCY     equ $ff42
SCX     equ $ff43
LY      equ $ff44
BGP     equ $ff47

BG_TILEMAP      equ $9800 ; Tile numbers for background
BGWIN_TILEDATA  equ $8000 ; Pixels per tile

SECTION "start", ROM0[$0100]
    nop
    jp main

SECTION "main", ROM0[$0150]
main:

init_wait_vblank:
    ld A, [LY]
    cp $90
    jr nz, init_wait_vblank

    ; Turn off lcd so we can freely populate VRAM
    ld A, $0
    ld [LCDC], A

    ; Identity map BG palette
    ld A, $e4
    ld [BGP], A


    ld A, $00
    ld [SCX], A
    ld [SCY], A

    ; Set tiledata for tiles 1..3
    ld HL, BGWIN_TILEDATA
    ld B, $8
tile1:
    ld A, $ff
    ld [HL+], A
    ld A, $00
    ld [HL+], A
    dec B
    jr nz, tile1

    ld B, $8
tile2:
    ld A, $00
    ld [HL+], A
    ld A, $ff
    ld [HL+], A
    dec B
    jr nz, tile2

    ld B, $4
tile3:
    ld A, $aa
    ld [HL+], A
    ld [HL+], A
    ld A, $55
    ld [HL+], A
    ld [HL+], A
    dec B
    jr nz, tile3

    ; Fill the screen with checkerboard pattern of tiles 0 and 1
    ld HL, BG_TILEMAP
    ld DE, $0
    ld B, $20 ; Height
loop_y:
    ld C, $10 ; Width / 2
loop_x:
    BIT 0, B
    jr z, even
odd:
    ld A, $0
    ld [HL+], A
    ld A, $1
    ld [HL+], A
    jr n
even:
    ld A, $1
    ld [HL+], A
    ld A, $0
    ld [HL+], A
n:
    dec C
    jr nz, loop_x
    add HL, DE
    dec B
    jr nz, loop_y


    ; Make leftmost column of tiles different pattern
    ld HL, BG_TILEMAP
    ld DE, $21          ; Stride (width)
    ld B, $20           ; Rows
    ld A, $2            ; Tile idx
loop_y2:
    ld [hl], A
    add HL, DE
    dec B
    jr nz, loop_y2


    ; Turn on LCD again
    ld A, $91
    ld [LCDC], A ; LCDC

    ld A, 14
    ld [SCX], A


scroll:

wait_vblank:
    ld A, [LY]
    cp $90
    jr nz, wait_vblank

    ld A, [SCX]
    inc A
    ld [SCX], A

    BIT 0, A
    jr Z, skip_y
    ld A, [SCY]
    inc A
    ld [SCY], A
skip_y:

wait_vblank2:
    ld A, [LY]
    cp $90
    jr z, wait_vblank2

    jr scroll


inf: jr inf
