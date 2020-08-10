/*
 * Verilator (verilog emulator)  wrapper for the verilog CPU implementation.
 */

#include "verilated.h"
#include "Vcpu.h"

extern "C" {
#include "common.h"
#include "vcpu.h"
}

static Vcpu *vcpu;

static int num_mem_accesses;
static struct mem_access mem_accesses[16];

extern "C" {

void vcpu_reset(struct state *state) {
#define S(name) vcpu->cpu__DOT__ ## name
    vcpu->clk = 0;
    S(halted) = 0;
    S(interrupts_master_enabled) = state->interrupts_master_enabled;
    S(pc) = state->PC;
    S(sp) = state->SP;
    S(reg_A) = state->reg8.A;
    S(reg_B) = state->reg8.B;
    S(reg_C) = state->reg8.C;
    S(reg_D) = state->reg8.D;
    S(reg_E) = state->reg8.E;
    S(reg_H) = state->reg8.H;
    S(reg_L) = state->reg8.L;
    S(Z) = BIT(state->reg8.F, 7);
    S(N) = BIT(state->reg8.F, 6);
    S(H) = BIT(state->reg8.F, 5);
    S(C) = BIT(state->reg8.F, 4);

    // Reset stage, otherwise we may add cycles coming out of halted state.
    S(stage) = 0; // RESET
    S(next_stage) = 2; // FETCH
#undef S
    num_mem_accesses = 0;
}

void vcpu_get_state(struct state *state) {
    state->PC = vcpu->dbg_pc;
    state->SP = vcpu->dbg_sp;
    state->reg16.AF = vcpu->dbg_AF;
    state->reg16.BC = vcpu->dbg_BC;
    state->reg16.DE = vcpu->dbg_DE;
    state->reg16.HL = vcpu->dbg_HL;
    state->halted = vcpu->cpu_is_halted;
    state->interrupts_master_enabled = vcpu->cpu__DOT__interrupts_master_enabled;
    state->num_mem_accesses = num_mem_accesses;
    memcpy(state->mem_accesses, mem_accesses, sizeof(mem_accesses));
}

int vcpu_step(void) {
    int cycles = 0;
    do {
        if (Verilated::gotFinish())
            return -1;

        if (!vcpu->clk)
            cycles++;
        vcpu->clk = !vcpu->clk;
        vcpu->eval();

        if (vcpu->clk) {
            u16 addr = vcpu->mem_addr;
            u8 data = 0xaa;
            if (addr < 4)
                data = instruction_mem[addr];
            vcpu->mem_data_read = data;

            if (vcpu->mem_do_write) {
                struct mem_access *access = &mem_accesses[num_mem_accesses++];
                access->type = MEM_ACCESS_WRITE;
                access->addr = vcpu->mem_addr;
                access->val = vcpu->mem_data_write;
            }
        }
    } while (!vcpu->dbg_instruction_retired || vcpu->clk);
    return cycles;
}

void vcpu_init(void) {
    vcpu = new Vcpu;
}

}
