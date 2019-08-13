ldi A, 0xF8
ldi B, 0xDE
ldi C, 0xAD
ldi BC, 0xBEEF
inc A
JR NZ, -3

inc A

jr 4
inc A # skipped
inc B # skipped
inc C # skipped
inc D # skipped

ldi C, 0xFF
inc BC
ldi a, 0
add b
ldi hl, 0x0003
ldhli a, (hl+)
ldhli b, (hl+)
ldhli c, (hl+)
#hlt
xor A # 0x00=nop
st (0x0001), A
inc A # 0x01=hlt
st (0x0002), A
jp 0x0001
