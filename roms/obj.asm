;
; Sprite test with scrolling text (with checkerboard on background).
;

_USE_DMA equ 1

rLCDC   equ $ff40
rSCY    equ $ff42
rSCX    equ $ff43
rLY     equ $ff44
rLYC    equ $ff45
rDMA    equ $ff46
rBGP    equ $ff47
rOBP0   equ $ff48
rOBP1   equ $ff49
rIF     equ $ff0f
rIE     equ $ffff

BG_TILEMAP      equ $9800 ; Tile numbers for background
BGWIN_TILEDATA  equ $8000 ; Pixels per tile
OBJ_TILEDATA    equ $8000

IF !DEF(_USE_DMA)
OAM_ADDR        equ $fe00 ; Object Attribute Memory (40 * 4 byte)
ENDC

vramCharIdx equ $80


SECTION "VBlank Interrupt", ROM0[$0040]
    jp VBlankHandler


SECTION "start", ROM0[$0100]
    nop
    jp main


SECTION "main", ROM0[$0150]

main::

    call WaitVBlank

    ; Turn off lcd so we can freely populate VRAM and OAM
    ld a, $0
    ld [rLCDC], a

    ; Identity map BG and OBJ palettes
    ld a, $e4
    ld [rBGP], a
    ld [rOBP0], a
    ld [rOBP1], a

    ; Reset background scroll
    ld a, $0
    ld [rSCX], a
    ld [rSCY], a

    call InitDMACode

    call InitVRAMTiles
    call InitBackground
    call ClearOAM
    call CreateTextObjs

    ld a, wOAMBuf / $100
    call DoOAMDMA

    ; Turn on LCD again
    ld a, $93
    ld [rLCDC], a ; LCDC

    ; Scroll background a bit
    ld a, 14
    ld [rSCX], a

    ; Enable VBlank interrupts
    ld a, %00000
    ld [rIF], a ; IF
    ld a, %00001  ; VBlank
    ld [rIE], a ; IE
    ei

mainloop:
    halt ; wait for vblank
    jr mainloop

;
; Called on VBlank interrupts
;
VBlankHandler::
    call ScrollText
    ld a, wOAMBuf / $100
    call DoOAMDMA
    reti

;
; Spin until LCD reaches VBlank. Returns immidiately if LCD is off.
;
WaitVBlank::
    ld a, [rLCDC]
    bit 7, a
    ret z
.wait_vblank
    ld a, [rLY]
    cp $90
    jr nz, .wait_vblank
    ret

;
; Copies a (2bpp) tile from location BC to HL
;
CopyTile::
REPT 16
    ld a, [bc]
    inc bc
    ld [hl+], a
ENDR
    ret

;
; Returns length of string (without spaces) pointed to by HL in E.
;
StrLenNoSpaces::
    xor a
    ld e, a
.loop
    ld a, [hl+]
    cp a, $20 ; ' '
    jr z, .loop
    cp a, $40 ; '@'
    ret z
    inc e
    jr .loop

;
; Copy the DMA code stub to HRAM
;
InitDMACode::
    ld hl, DoOAMDMA ; Dest
    ld bc, DoOAMDMACode ; Source
    ld de, DoOAMDMACodeEnd - DoOAMDMACode   ; Len

.loop
    ld a, [bc]
    ld [hl+], a
    inc bc
    dec de
    ld a, d
    or e
    jr nz, .loop

    ret

;
; Init VRAM tiles
;
InitVRAMTiles::
    ld bc, Tile1
    ld hl, vramTile1
    call CopyTile

    ld bc, Tile2
    ld hl, vramTile2
    call CopyTile

    ld bc, Tile3
    ld hl, vramTile3
    call CopyTile

    call CopyFontToVRAM

    ret

InitBackground::
    call InitBackgroundCheckerboard
    call InitBackgroundLine
    ret

;
; Fill the screen with checkerboard pattern of tiles 0 and 1
;
InitBackgroundCheckerboard::
    ld hl, BG_TILEMAP
    ld de, $0
    ld b, $20 ; Height
.loop_y
    ld c, $10 ; Width / 2
.loop_x

    bit 0, b
    jr z, .even
.odd
    ld a, $1
    ld [hl+], a
    ld a, $0
    ld [hl+], a
    jr .next
.even
    ld a, $0
    ld [hl+], a
    ld a, $1
    ld [hl+], a
.next
    dec c
    jr nz, .loop_x
    add hl, de
    dec b
    jr nz, .loop_y

    ret

;
; Create a (strided) line of tiles with different pattern
;
InitBackgroundLine::
    ; Make leftmost column of tiles different pattern
    ld hl, BG_TILEMAP
    ld de, $21          ; Stride (width)
    ld b, $20           ; Rows
    ld a, $2            ; Tile idx
.loop_y2
    ld [hl], a
    add hl, de
    dec b
    jr nz, .loop_y2
    ret

;
; Scroll all sprites of the text down and right
;
ScrollText::
    ld hl, TextHello
    call StrLenNoSpaces
    ld b, 0

.loop
IF DEF(_USE_DMA)
    ld hl, wOAMBuf
ELSE
    ld hl, OAM_ADDR
ENDC
    ld c, e
    dec c
    sla c
    sla c
    add hl, bc
    ld a, [hl] ; Y
    inc a
    cp 160
    jr nz, .nowrapy
    xor a
.nowrapy
    ld [hl], a ; Y

    bit 0, a
    jr z, .skip_x_scroll

    inc hl
    ld a, [hl] ; X
    inc a
    cp 168
    jr nz, .nowrapx
    xor a
.nowrapx
    ld [hl], a

.skip_x_scroll

    dec e
    jr nz, .loop
    ret

;
; Clears the entire OAM to 0. Assumes OAM is accessible.
;
ClearOAM::
    ld c, 160 ; 40 objects, 4 bytes each
IF DEF(_USE_DMA)
    ld hl, wOAMBuf
ELSE
    ld hl, OAM_ADDR
ENDC
    xor a
.loop
    ld [hl+], a
    dec c
    jr nz, .loop
    ret

;
; Load the text as objects (sprites)
;
CreateTextObjs::
IF DEF(_USE_DMA)
    ld hl, wOAMBuf
ELSE
    ld hl, OAM_ADDR
ENDC
    ld bc, TextHello
    ld d, 64 ; Start X pos

.loop
    ; Check the character (skip spaces, stop at @)
    ld a, [bc]
    cp a, $40 ; '@'
    jr z, .done

    cp a, $20 ; ' '
    jr nz, .dochar
    inc bc   ; Next char
    ld a, d
    add a, 8 ; Shift X pos for next char
    ld d, a
    jp .loop

.dochar
    ; Y pos
    ld a, 32
    ld [hl+], a

    ; X pos
    ld a, d
    ld [hl+], a
    add a, 8
    ld d, a

    ; Tile
    ld a, [bc]
    inc bc
    sub a, $41 ; 'A'
    add a, vramCharIdx
    ld [hl+], a

    ; Attrs
    ld a, 0
    ld [hl+], a ; Attributes

    jr .loop
.done
    ret


;
; Load font into VRAM (doubling up the bytes for 2 bpp)
;
CopyFontToVRAM::
    ld hl, vramFontStart    ; Dest
    ld bc, Font             ; Source
    ld de, FontEnd - Font   ; Len

.loop
    ld a, [bc]
    ld [hl+], a
    ld [hl+], a
    inc bc
    dec de
    ld a, d
    or e
    jr nz, .loop

    ret

;
; Stub which is copied to HRAM and executed to initiate and wait for OAM DMA.
; A should contain the upper byte of the source address.
;
DoOAMDMACode::
    ld [rDMA], a
    ld a, $28
.dma_wait
    dec a
    jr nz, .dma_wait
    ret
DoOAMDMACodeEnd::


SECTION "text", ROM0[$300]
TextHello: db "Hello world@"


SECTION "gfx", ROM0[$310]

Tile1:
REPT 8
    dw $ff00
ENDR

Tile2:
REPT 8
    dw $00ff
ENDR

Tile3:
REPT 4
    dw $aaaa
    dw $5555
ENDR

Font:       INCBIN "pkmn_font.1bpp"
FontEnd:


SECTION "WRAM OAM buffer", WRAM0
wOAMBuf:: ds 40 * 4


SECTION "HRAM DMA", HRAM
DoOAMDMA::


SECTION "VRAMTileData", VRAM
vramTile1: ds 16
vramTile2: ds 16
vramTile3: ds 16

SECTION "VRAMTileDataFont", VRAM[$8800]
vramFontStart:

