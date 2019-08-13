#!/usr/bin/env python3
#
# Simple assembler, for converting an asm file to a hex file that can be loaded
# as memory for the CPU.
#

import sys

opcodes = {
    'nop': 0x00,
    'hlt': 0x01,
    'mov': 0x02,
    'ldi': 0x03,
    'ld':  0x04,
    'st':  0x05,
    'add': 0x06,
    'sub': 0x07,
    'or':  0x08,
    'and': 0x09,
    'xor': 0x0a,
    'inc': 0x0b,
    'dec': 0x0c,
    'jr':  0x0d,
    'jrcc': 0x0f,
    'inc16': 0x10,
    'dec16': 0x11,
    'add16': 0x12,
    'jp': 0x13,
    'jpcc': 0x14,
    'ldi16': 0x15,
    'ld16': 0x16,
    'ldhli': 0x17,
    'push': 0x18,
    'pop': 0x19,
    'call': 0x1a,
    'callcc': 0x1b,
    'ret': 0x1c,
    'retcc': 0x1d,
    # max 0x1f
}

arg_reg8_shift = 5
arg_reg8 = {
    'a': 0x0,
    'b': 0x1,
    'c': 0x2,
    'd': 0x3,
    'e': 0x4,
    'h': 0x5,
    'l': 0x6,
}
arg_reg16_shift = 6
arg_reg16 = {
    'bc': 0x0,
    'de': 0x1,
    'hl': 0x2,
    'sp': 0x3, # for arith
    'af': 0x3, # for pop
}
arg_cond_shift = 6
arg_cond = {
    'z': 0x0,
    'c': 0x1,
    'nz': 0x2,
    'nc': 0x3,
}

def parseint(val, width=8):
    if val.startswith('(') and val.endswith(')'):
        val = val[1:-1]
    val = int(val, 0)
    if val < 0: val = (1 << width) + val
    return val

class Instruction:
    def __init__(self, instr):
        self.instr = instr

        op, *args = self.instr.split(' ', 1)
        if op not in opcodes:
            raise ValueError(f'Unknown instruction {op}')
        opcode = opcodes[op]

        if args:
            args = [a.strip() for a in args[0].split(',')]

        argbytes = []
        if op in ('nop', 'hlt'):
            assert(len(args) == 0)
        elif op in ('jr', 'jp', 'call'):
            assert(len(args) in (1, 2))
            if len(args) == 2:
                opcode = opcodes[f'{op}cc']
                opcode |= arg_cond[args[0]] << arg_cond_shift
                addr = parseint(args[1])
            else:
                addr = parseint(args[0])
            argbytes.append(addr & 0xff)
            if op in ('jp', 'call'):
                argbytes.append((addr >> 8) & 0xff)
        elif op in ('inc', 'dec', 'add', 'sub', 'or', 'and', 'xor'):
            assert(len(args) == 1)
            if args[0] in arg_reg16:
                assert(args[0] != 'af')
                opcode = opcodes[f'{op}16']
                opcode |= arg_reg16[args[0]] << arg_reg16_shift
            else:
                opcode |= arg_reg8[args[0]] << arg_reg8_shift
        elif op == 'ldi':
            assert(len(args) == 2)
            if args[0] in arg_reg16:
                assert(args[0] != 'af')
                opcode = opcodes[f'{op}16']
                opcode |= arg_reg16[args[0]] << arg_reg16_shift
                val = parseint(args[1])
                argbytes.append(val & 0xff)
                argbytes.append((val >> 8) & 0xff)
            else:
                opcode |= arg_reg8[args[0]] << arg_reg8_shift
                argbytes.append(parseint(args[1]))
        elif op == 'mov':
            assert(len(args) == 1)
            opcode |= arg_reg8[args[0]] << arg_reg8_shift
        elif op in ('ld', 'st'):
            assert(len(args) == 2)
            if op == 'ld':
                addr = parseint(args[1])
                reg = args[0]
            else:
                addr = parseint(args[0])
                reg = args[1]
            if reg in arg_reg16:
                assert(reg != 'af')
                opcode = opcodes[f'{op}16']
                opcode |= arg_reg16[reg] << arg_reg16_shift
            else:
                opcode |= arg_reg8[reg] << arg_reg8_shift
            argbytes.append(addr & 0xff)
            argbytes.append((addr >> 8) & 0xff)
        elif op == 'ldhli':
            assert(len(args) == 2)
            assert(args[1] == '(hl+)')
            opcode |= arg_reg8[args[0]] << arg_reg8_shift
        elif op in ('push', 'pop'):
            assert(len(args) == 1)
            assert(args[0] != 'sp')
            opcode |= arg_reg16[args[0]] << arg_reg16_shift
        elif op == 'ret':
            assert(len(args) in (0, 1))
            if len(args) == 1:
                opcode = opcodes[f'{op}cc']
                opcode |= arg_cond[args[0]] << arg_cond_shift

        self.bytes = [opcode] + argbytes

    def __repr__(self):
        return f'<Instruction "{self.instr}">'

    def __len__(self):
        return len(self.bytes);

    def assemble(self, annotate=True):
        ret = ' '.join(['%02x' % byte for byte in self.bytes])
        if annotate:
            annotate_col = 10
            ret += ' ' * (annotate_col - len(ret))
            ret += f'// {self.instr}'
        return ret


def main():
    if len(sys.argv) != 4:
        print("Usage: %s infile outfile flash_size" % sys.argv[0])
        return

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    flash_size = int(sys.argv[3])

    instructions = []

    with open(input_file) as f:
        for line in f:
            line = line.split('#')[0].strip().lower()
            if not line:
                continue
            instructions.append(Instruction(line))

    output_num_bytes = 0
    with open(output_file, 'w') as f:
        for instr in instructions:
            assembled = instr.assemble()
            output_num_bytes += len(instr)
            #print(assembled)
            f.write(f'{assembled}\n')

        pad_size = flash_size - output_num_bytes
        #print(f'Padding with {pad_size} bytes')
        f.write(' '.join(['00' for i in range(pad_size)]))


if __name__ == '__main__':
    main()
