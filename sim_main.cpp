#include "Vmain.h"
#include "verilated.h"

Vmain *top;
vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

#define BIT(val, bitpos) (((val) >> (bitpos)) & 1)

void dump_state(void) {
    printf(" PC   SP   AF   BC   DE   HL  ZNHC\n"
            "%04x %04x %04x %04x %04x %04x %d%d%d%d\n\n",
            top->dbg_pc, top->dbg_sp, top->dbg_AF, top->dbg_BC,
            top->dbg_DE, top->dbg_HL,
            BIT(top->dbg_AF, 7), BIT(top->dbg_AF, 6),
            BIT(top->dbg_AF, 5), BIT(top->dbg_AF, 4));
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    top = new Vmain;

    top->clk = 0;

    while (!Verilated::gotFinish()) {
        top->clk = !top->clk;

        top->eval();

#ifdef DEBUG
        if (top->clk == 1 && top->dbg_instruction_retired)
            dump_state();
#endif

        main_time++;

        if (top->dbg_instruction_retired && top->dbg_halted) {
            printf("CPU halted, exiting\n");
            break;
        }
    }

    dump_state();

    top->final();

    delete top;

    return 0;
}
