ldi a, 0x1f # opcode 0x1f is not implemented, so this is trap for jumping to 0x1
ldi SP, 0xfff0
ldi BC, 0xdead
ldi DE, 0xbeef
ldi HL, 0xf00f

ldi A, 0xf8
inc A
jr NZ, -3
ldi A, 0xaa

xor A
call NZ, 1
call C, 1
call Z, 0x20

hlt

ldi DE, 0xcafe
ret NZ
ret C
ldi A, 0xaa
ret
