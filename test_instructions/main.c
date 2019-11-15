#include <stdio.h>
#include <string.h>
#include <assert.h>

#include "common.h"
#include "disassembler.h"
#include "vcpu.h"
#include "emu_cpu.h"
#include "inputstate.h"
#include "instructions.h"

bool output_summarize = 1;
bool enable_cb = 0;

u8 instruction_mem[4];

unsigned long num_tests = 0;
bool tested_op[256] = { 0 };
bool tested_op_cb[256] = { 0 };


void dump_state(struct state *state) {
    printf(" PC   SP   AF   BC   DE   HL  ZNHC hlt IME\n"
            "%04x %04x %04x %04x %04x %04x %d%d%d%d  %d   %d\n",
            state->PC, state->SP, state->reg16.AF, state->reg16.BC,
            state->reg16.DE, state->reg16.HL,
            BIT(state->reg16.AF, 7), BIT(state->reg16.AF, 6),
            BIT(state->reg16.AF, 5), BIT(state->reg16.AF, 4), state->halted,
            state->interrupts_master_enabled);

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
           s1->interrupts_master_enabled == s2->interrupts_master_enabled &&
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

        if (inst->is_cb_prefix)
            tested_op_cb[instruction_mem[1]] = 1;
        else
            tested_op[instruction_mem[0]] = 1;
    } while (!next_state(inst, &op_state, &state));

    return 0;
}

static int test_instructions(size_t num_instructions,
                             struct test_inst *insts,
                             const char *prefix) {
    size_t num_instructions_passed = 0;
    for (size_t i = 0; i < num_instructions; i++) {
        if (!output_summarize) {
            printf("%s   ", insts[i].mnem);
            if (insts[i].is_cb_prefix)
                printf("(CB prefix)");
            printf("\n");
        }

        if (!insts[i].enabled) {
            if (!output_summarize)
                printf(" Skipping\n");
            continue;
        }

        if (test_instruction(&insts[i]))
            return 1;

        if (!output_summarize)
            printf(" Ran %lu permutations\n", num_tests);
        num_instructions_passed++;
        num_tests = 0;
    }

    if (!output_summarize)
        printf("\n");

    printf("Tested %zu/%zu %sinstructions\n", num_instructions_passed,
            num_instructions, prefix);
    if (!output_summarize)
        printf("\n");

    return 0;
}

static bool is_valid_op(u8 op) {
    u8 invalid_ops[] = { 0xcb,                          // Special case (prefix)
                         0xd3, 0xdb, 0xdd,
                         0xe3, 0xe4, 0xeb, 0xec, 0xed,
                         0xf4, 0xfc, 0xfd };

    for (size_t i = 0; i < sizeof(invalid_ops); i++)
        if (invalid_ops[i] == op)
            return false;

    return true;
}

static bool is_valid_op_cb(u8 op) {
    (void)op;
    return true;
}

static void print_coverage(bool *op_table, bool (*is_valid)(u8),
        const char *prefix) {
    unsigned num_tested_ops, total_valid_ops;

    num_tested_ops = 0, total_valid_ops = 0;
    for (int op = 0; op <= 0xff; op++) {
        if (op_table[op])
            num_tested_ops++;
        if (is_valid(op))
            total_valid_ops++;
    }

    printf("Tested %d/%d %sopcodes\n", num_tested_ops, total_valid_ops, prefix);

    if (num_tested_ops < total_valid_ops) {
        printf("\nTable of untested %sopcodes:\n", prefix);
        for (int op = 0; op <= 0xff; op++) {
            if (op_table[op] || !is_valid(op))
                printf("-- ");
            else
                printf("%02x ", op);
            if ((op & 0xf) == 0xf)
                printf("\n");
        }
        printf("\n");
    }
}

static int test_all_instructions(void) {
    size_t num_instructions = sizeof(instructions) / sizeof(instructions[0]);
    size_t num_cb_instructions = sizeof(cb_instructions) / sizeof(cb_instructions[0]);

    if (test_instructions(num_instructions, instructions, ""))
        return 1;

    if (enable_cb)
        if (test_instructions(num_cb_instructions, cb_instructions, "CB "))
            return 1;

    print_coverage(tested_op, is_valid_op, "");
    if (enable_cb)
        print_coverage(tested_op_cb, is_valid_op_cb, "CB ");

    return 0;
}


int main(void) {
    vcpu_init();
    ecpu_init();

    return test_all_instructions();
}
