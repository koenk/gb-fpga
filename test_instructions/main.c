#include <stdio.h>
#include <string.h>
#include <assert.h>

#include "common.h"
#include "disassembler.h"
#include "vcpu.h"
#include "emu_cpu.h"
#include "inputstate.h"
#include "instructions.h"

u8 instruction_mem[4];

unsigned long num_tests = 0;
bool tested_op[256] = { 0 };
bool tested_op_cb[256] = { 0 };


void dump_state(struct state *state) {
    printf(" PC   SP   AF   BC   DE   HL  ZNHC hlt\n"
            "%04x %04x %04x %04x %04x %04x %d%d%d%d  %d\n",
            state->PC, state->SP, state->reg16.AF, state->reg16.BC,
            state->reg16.DE, state->reg16.HL,
            BIT(state->reg16.AF, 7), BIT(state->reg16.AF, 6),
            BIT(state->reg16.AF, 5), BIT(state->reg16.AF, 4), state->halted);

    for (int i = 0; i < state->num_mem_accesses; i++)
        printf("  Mem %s: addr=%04x val=%02x\n",
                state->mem_accesses[i].type ? "write" : "read",
                state->mem_accesses[i].addr, state->mem_accesses[i].val);
    printf("\n");
}

void dump_op_state(struct test_inst *inst, struct op_state *op_state) {
    const char *reg8_names[] = { "B", "C", "D", "E", "H", "L", "(HL)", "A" };
    const char *reg16_names[] = { "BC", "DE", "HL", "SP/AF" };
    const char *cond_names[] = { "NZ", "Z", "NC", "C" };

    if (inst->imm_size == 1)
        printf("imm: %02x\n", op_state->imm);
    else if (inst->imm_size == 2)
        printf("imm: %04x\n", op_state->imm);

    if (inst->reg8_bitpos != -1)
        printf("r8: %s (%d)\n", reg8_names[op_state->reg8], op_state->reg8);

    if (inst->reg8_bitpos2 != -1)
        printf("r8: %s (%d)\n", reg8_names[op_state->reg8_2], op_state->reg8_2);

    if (inst->reg16_bitpos != -1)
        printf("r16: %s (%d)\n", reg16_names[op_state->reg16], op_state->reg16);

    if (inst->cond_bitpos != -1)
        printf("cond: %s (%d)\n", cond_names[op_state->cond], op_state->cond);

    if (inst->bit_bitpos != -1)
        printf("bit: %d\n", op_state->bit);
}

int states_eq(struct state *s1, struct state *s2) {
    return s1->reg16.AF == s2->reg16.AF &&
           s1->reg16.BC == s2->reg16.BC &&
           s1->reg16.DE == s2->reg16.DE &&
           s1->reg16.HL == s2->reg16.HL &&
           s1->PC == s2->PC &&
           s1->SP == s2->SP &&
           s1->halted == s2->halted &&
           s1->num_mem_accesses == s2->num_mem_accesses &&
           memcmp(s1->mem_accesses, s2->mem_accesses,
                  s1->num_mem_accesses * sizeof(struct mem_access)) == 0;
}

static void state_reset(struct state *s) {
    memset(s, 0, sizeof(*s));
}

static void op_state_reset(struct op_state *op_state) {
    memset(op_state, 0, sizeof(*op_state));
}


static int run_state(struct state *state) {
    struct state vcpu_out_state, ecpu_out_state;

    vcpu_reset(state);
    ecpu_reset(state);

    vcpu_step();
    ecpu_step();

    vcpu_get_state(&vcpu_out_state);
    ecpu_get_state(&ecpu_out_state);

    if (!states_eq(&vcpu_out_state, &ecpu_out_state)) {
        printf("\n  === STATE MISMATCH ===\n");
        printf("\n - Instruction -\n");
        disassemble(instruction_mem);
        printf("\n - Input state -\n");
        dump_state(state);
        printf("\n - CPU output state -\n");
        dump_state(&vcpu_out_state);
        printf("\n - Emulated output state -\n");
        dump_state(&ecpu_out_state);
        return 1;
    }

    return 0;
}

static void assemble(u8 *out, struct test_inst *inst,
        struct op_state *op_state) {
    u8 opcode = inst->opcode;
    int idx = 0;

    if (inst->reg8_bitpos >= 0)
        opcode |= op_state->reg8 << inst->reg8_bitpos;
    if (inst->reg8_bitpos2 >= 0)
        opcode |= op_state->reg8_2 << inst->reg8_bitpos2;
    if (inst->reg16_bitpos >= 0)
        opcode |= op_state->reg16 << inst->reg16_bitpos;
    if (inst->cond_bitpos >= 0)
        opcode |= op_state->cond << inst->cond_bitpos;
    if (inst->bit_bitpos >= 0)
        opcode |= op_state->bit << inst->bit_bitpos;

    if (inst->is_cb_prefix)
        out[idx++] = 0xcb;

    out[idx++] = opcode;

    if (inst->imm_size >= 1)
        out[idx++] = op_state->imm & 0xff;
    if (inst->imm_size >= 2)
        out[idx++] = (op_state->imm >> 8) & 0xff;
}

static int test_instruction(struct test_inst *inst) {
    struct op_state op_state;
    struct state state;

    state_reset(&state);
    op_state_reset(&op_state);
    do {
        num_tests++;
        assemble(instruction_mem, inst, &op_state);
        //dump_op_state(&op_state);
        //disassemble(instruction_mem);
        if (run_state(&state))
            return 1;
    } while (!next_state(inst, &op_state, &state));

    return 0;
}

static int test_all_instructions(void) {
    size_t num_instructions = sizeof(instructions) / sizeof(instructions[0]);
    size_t num_cb_instructions = sizeof(cb_instructions) / sizeof(cb_instructions[0]);

    int num_instructions_passed = 0;
    unsigned long num_tests_total = 0;

    for (size_t i = 0; i < num_instructions; i++) {
        printf("%s\n", instructions[i].mnem);

        if (!instructions[i].enabled) {
            printf(" Skipping\n");
            continue;
        }

        if (test_instruction(&instructions[i]))
            return 1;

        printf(" Ran %lu permutations\n", num_tests);
        num_instructions_passed++;
        num_tests_total += num_tests;
        num_tests = 0;
    }

    for (size_t i = 0; i < num_cb_instructions; i++) {
        printf("%s   (CB prefix)\n", cb_instructions[i].mnem);

        if (!cb_instructions[i].enabled) {
            printf(" Skipping\n");
            continue;
        }

        if (test_instruction(&cb_instructions[i]))
            return 1;

        printf(" Ran %lu permutations\n", num_tests);
        num_instructions_passed++;
        num_tests_total += num_tests;
        num_tests = 0;
    }

    printf("\n");
    printf("Tested %d instructions successfully\n", num_instructions_passed);
    printf("Ran %lu permutations total\n", num_tests_total);

    return 0;
}


int main(void) {
    vcpu_init();
    ecpu_init();

    return test_all_instructions();
}
