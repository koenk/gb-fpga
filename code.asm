# This counts a bit and then halts
ldi A, 0xF8
inc A
JR NZ, -3

inc A

jr 4
inc A # skipped
inc B # skipped
inc C # skipped
inc D # skipped
hlt
