#include "Vmain.h"
#include "verilated.h"

Vmain *top;
vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

#define BIT(val, bitpos) (((val) >> (bitpos)) & 1)

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    top = new Vmain;

    top->clk = 0;

#if 1
    while (!Verilated::gotFinish()) {
        top->clk = !top->clk;

        top->eval();

        if (top->clk == 1 && top->dbg_instruction_retired) {
            printf("pc: %04x   F: %d%d%d%d  A: %02x  B: %02x  C: %02x\n\n",
                    top->dbg_pc,
                    BIT(top->dbg_F, 3), BIT(top->dbg_F, 2), BIT(top->dbg_F, 1), BIT(top->dbg_F, 0),
                    top->dbg_A, top->dbg_B, top->dbg_C);
        }
        main_time++;

        if (top->dbg_halted) {
            printf("CPU halted, exiting\n");
            break;
        }
    }

    top->final();

    delete top;
#endif

    return 0;
}
