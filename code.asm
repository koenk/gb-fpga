# This counts a bit and then halts
ldi A, 0xF8
ldi B, 0xDE
ldi C, 0xAD
inc A
JR NZ, -3

inc A

jr 0
inc A # skipped
inc B # skipped
inc C # skipped
inc D # skipped

ldi C, 0xFF
inc BC
#ld a, 0x0002
hlt
