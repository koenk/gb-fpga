#include <chrono>

#include "Vmain.h"
#include "verilated.h"

extern "C" {
#include "gui.h"
}

#define RES_X 160
#define RES_Y 144
#define ZOOM  4

using namespace std::chrono;

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
    struct gui_input input_state = { 0 };
    uint8_t *pixbuf;

    Verilated::commandArgs(argc, argv);

    gui_init(RES_X, RES_Y, ZOOM, "gb-fpga");
    pixbuf = (uint8_t*)malloc(RES_X * RES_Y);
    memset(pixbuf, 0, RES_X * RES_Y);

    top = new Vmain;

    top->clk = 0;

    bool vblank_old = 0;
    bool paused = 0;

    top->reset = 1;
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->reset = 0;
    top->clk = 0;
    top->eval();

    steady_clock::time_point last_poll = steady_clock::now();
    while (!Verilated::gotFinish()) {
        main_time++;

        steady_clock::time_point now = steady_clock::now();
        auto ms_since_poll = duration_cast<milliseconds>(now - last_poll).count();
        if (ms_since_poll > 16) { // ~60 times per second
            last_poll = now;
            gui_input_poll(&input_state);
            if (input_state.special_quit)
                break;
            if (input_state.special_pause) {
                paused = !paused;
                printf("Paused: %d\n", paused);
            }
        }

        if (paused)
            continue;

        top->clk = !top->clk;

        top->eval();

#ifdef DEBUG
        if (top->clk == 1 && top->dbg_instruction_retired)
            dump_state();
#endif

        // Redraw screen on vblank
        if (top->lcd_vblank && !vblank_old)
            gui_render_frame(pixbuf);
        vblank_old = top->lcd_vblank;

        if (top->clk && top->lcd_write)
            pixbuf[top->lcd_x + top->lcd_y * RES_X] = top->lcd_col;

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
