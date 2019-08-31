import serial
ser = serial.Serial('/dev/ttyUSB1', 115200)

def rd(n=1):
    ret = 0
    for i in range(n):
        x = ser.read()
        print(hex(ord(x)), end=' ')
        ret = ret << 8
        ret |= ord(x)
    return ret

while True:
    stat = rd()
    PC = rd(2)
    SP = rd(2)
    AF = rd(2)
    BC = rd(2)
    DE = rd(2)
    HL = rd(2)
    op = rd()
    print("\nST op  PC   SP   AF   BC   DE   HL \n"
         "%02d %02x %04x %04x %04x %04x %04x %04x\n" % (stat & 0x1f, op, PC, SP,
             AF, BC, DE, HL))
