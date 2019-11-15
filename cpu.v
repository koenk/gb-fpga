module cpu (
    input clk,
    input reset,

    output reg [15:0] mem_addr,
    output reg [7:0] mem_data_write,
    input [7:0] mem_data_read,
    output reg mem_do_write,

    output cpu_is_halted,

    output [15:0] dbg_pc,
    output [15:0] dbg_sp,
    output [15:0] dbg_AF,
    output [15:0] dbg_BC,
    output [15:0] dbg_DE,
    output [15:0] dbg_HL,
    output dbg_instruction_retired,
    output reg [7:0] dbg_last_opcode,
    output [5:0] dbg_stage
);

/*
 * We have 4 normal stages: fetch, decode, execute and writeback. We also have
 * some intermediate stages, where more expensive operations can optionally
 * occur. For example, if we need to read data from memory during decode (for an
 * operand) we add several stages (and thus clks) for that.
 */
localparam RESET       = 0,
           HALTED      = 1,
           FETCH       = 2,
           DECODE      = 3,
           DECODE_CB1  = 4,
           DECODE_CB2  = 5,
           DECODE_CB3  = 6,
           DECODE_CB4  = 7,
           DECODE_IMM1 = 8,
           DECODE_IMM2 = 9,
           DECODE_IMM3 = 10,
           DECODE_IMM4 = 11,
           DECODE_IMM5 = 12,
           DECODE_IMM6 = 13,
           DECODE_IMM7 = 14,
           DECODE_IMM8 = 15,
           LOAD_MEM1   = 16,
           LOAD_MEM2   = 17,
           LOAD_MEM3   = 18,
           LOAD_MEM4   = 19,
           LOAD_MEM5   = 20,
           LOAD_MEM6   = 21,
           LOAD_MEM7   = 22,
           LOAD_MEM8   = 23,
           EXECUTE     = 24,
           STORE_MEM1  = 25,
           STORE_MEM2  = 26,
           STORE_MEM3  = 27,
           STORE_MEM4  = 28,
           STORE_MEM5  = 29,
           STORE_MEM6  = 30,
           STORE_MEM7  = 31,
           STORE_MEM8  = 32,
           WRITEBACK   = 33;

/* Operations the ALU can perform. */
localparam ALU_NOP  = 0,
           ALU_ADD  = 1,
           ALU_ADC  = 2,
           ALU_SUB  = 3,
           ALU_SBC  = 4,
           ALU_AND  = 5,
           ALU_XOR  = 6,
           ALU_OR   = 7,
           ALU_RLC  = 8,
           ALU_RRC  = 9,
           ALU_RL   = 10,
           ALU_RR   = 11,
           ALU_SLA  = 12,
           ALU_SRA  = 13,
           ALU_SWAP = 14,
           ALU_SRL  = 15;

/* Possible parameters during decoding (both source during decode/execute, and
 * destination during writeback). */
localparam DE_NONE   = 0,
           DE_CONST  = 1,
           DE_IMM8   = 2,
           DE_IMM16  = 3,
           DE_PC     = 4,
           DE_SP     = 5,
           DE_REG_A  = 6,
           DE_REG_B  = 7,
           DE_REG_C  = 8,
           DE_REG_D  = 9,
           DE_REG_E  = 10,
           DE_REG_H  = 11,
           DE_REG_L  = 12,
           DE_REG_AF = 13,
           DE_REG_BC = 14,
           DE_REG_DE = 15,
           DE_REG_HL = 16,
           DE_HLMEM  = 17, // Memory read/write at address HL
           DE_IO_C   = 18,
           DE_IO_IMM = 19;

/* How to modify the SP register during writeback. */
localparam SP_OP_NONE = 0,
           SP_OP_INC2 = 1,
           SP_OP_DEC2 = 2;
/* How to modify the HL register during writeback. */
localparam HL_OP_NONE = 0,
           HL_OP_INC  = 1,
           HL_OP_DEC  = 2;

reg [5:0] stage, next_stage;

reg halted;

reg interrupts_master_enabled;

reg [15:0] pc, sp;
reg Z, N, H, C;
reg [7:0] reg_A, reg_B, reg_C, reg_D, reg_E, reg_H, reg_L;
wire [7:0] reg_F;
wire [3:0] reg_Fh;

reg decode_halt;
reg decode_instruction_not_implemented;
reg decode_16bit;
reg [3:0] decode_alu_op;
reg [4:0] decode_oper1, decode_oper2;
reg [15:0] decode_oper1_constval, decode_oper2_constval;
reg [1:0] decode_instr_length;
reg [4:0] decode_dest;
reg [7:0] decode_opcode, opc;
reg [3:0] decode_flags_mask;
reg [3:0] decode_flags_override_set, decode_flags_override_reset;
reg [1:0] decode_HL_op, decode_SP_op;
reg decode_cond;
reg decode_load_mem8, decode_load_mem16;
reg decode_store_mem8, decode_store_mem16;
reg [4:0] decode_store_addr_oper, decode_store_data_oper;
reg [15:0] decode_store_addr_constval, decode_store_data_constval;
reg decode_cb_prefix;
reg decode_intm_disable, decode_intm_enable;

reg [7:0] decode_cb_opcode;
reg [3:0] decode_cb_alu_op;
reg [4:0] decode_cb_oper1;
reg [4:0] decode_cb_oper2;
reg [7:0] decode_cb_oper2_constval;
reg [4:0] decode_cb_dest;
reg [3:0] decode_cb_flags_mask;
reg decode_cb_instruction_not_implemented;

reg decode_has_imm_operand, decode_has_imm16_operand;
reg decode_imm_operand_is_store_addr;
reg decode_imm_operand_is_oper2;

reg load_mem, load_mem16;
reg load_use_oper2;
reg load_from_iospace;
reg [15:0] load_mem_addr;

reg store_mem, store_mem16;
reg [15:0] store_mem_addr, store_mem_data;
reg store_mem_execout;

reg alu_16bit;
reg [3:0] alu_op;
reg [15:0] exec_oper1, exec_oper2;
reg [16:0] alu_out; // 16 bit + 1 bit for capturing carry
wire alu_out_Z, alu_out_N, alu_out_H;
reg alu_out_C;

reg [4:0] wb_dest;
reg [15:0] wb_data;
reg [15:0] wb_pc;
reg [3:0] wb_flags, wb_flags_mask, wb_flags_override_set, wb_flags_override_reset;
reg [1:0] wb_HL_op, wb_SP_op;
reg wb_intm_disable, wb_intm_enable;

localparam MEMBUS_FETCH=0, MEMBUS_OPER=1, MEMBUS_LOAD=2, MEMBUS_STORE=3;

assign cpu_is_halted = halted;

assign dbg_pc = pc;
assign dbg_sp = sp;
assign dbg_AF = {reg_A, reg_F};
assign dbg_BC = {reg_B, reg_C};
assign dbg_DE = {reg_D, reg_E};
assign dbg_HL = {reg_H, reg_L};
assign dbg_instruction_retired = stage == WRITEBACK;
assign dbg_stage = stage;

assign reg_Fh = {Z, N, H, C};
assign reg_F = {reg_Fh, 4'h0};


function [15:0] sext(input [7:0] val);
    sext = {{8{val[7]}}, val};
endfunction


/*
 * CPU stage FSM
 */
always @(*)
    if (reset)
        next_stage = RESET;
    else
        case (stage)
            RESET:       next_stage = FETCH;
            HALTED:      next_stage = halted ? HALTED : FETCH;
            FETCH:       next_stage = DECODE;
            DECODE:      next_stage = decode_cb_prefix ? DECODE_CB1 :
                                      decode_has_imm_operand ? DECODE_IMM1 :
                                      load_mem ? LOAD_MEM1 : EXECUTE;
            DECODE_CB1:  next_stage = DECODE_CB2;
            DECODE_CB2:  next_stage = DECODE_CB3;
            DECODE_CB3:  next_stage = DECODE_CB4;
            DECODE_CB4:  next_stage = decode_has_imm_operand ? DECODE_IMM1 :
                                      load_mem ? LOAD_MEM1 : EXECUTE;
            DECODE_IMM1: next_stage = DECODE_IMM2;
            DECODE_IMM2: next_stage = DECODE_IMM3;
            DECODE_IMM3: next_stage = DECODE_IMM4;
            DECODE_IMM4: next_stage = decode_has_imm16_operand ? DECODE_IMM5 :
                                      (load_mem ? LOAD_MEM1 : EXECUTE);
            DECODE_IMM5: next_stage = DECODE_IMM6;
            DECODE_IMM6: next_stage = DECODE_IMM7;
            DECODE_IMM7: next_stage = DECODE_IMM8;
            DECODE_IMM8: next_stage = load_mem ? LOAD_MEM1 : EXECUTE;
            LOAD_MEM1:   next_stage = LOAD_MEM2;
            LOAD_MEM2:   next_stage = LOAD_MEM3;
            LOAD_MEM3:   next_stage = LOAD_MEM4;
            LOAD_MEM4:   next_stage = load_mem16 ? LOAD_MEM5 : EXECUTE;
            LOAD_MEM5:   next_stage = LOAD_MEM6;
            LOAD_MEM6:   next_stage = LOAD_MEM7;
            LOAD_MEM7:   next_stage = LOAD_MEM8;
            LOAD_MEM8:   next_stage = EXECUTE;
            EXECUTE:     next_stage = store_mem ? STORE_MEM1 : WRITEBACK;
            STORE_MEM1:  next_stage = STORE_MEM2;
            STORE_MEM2:  next_stage = STORE_MEM3;
            STORE_MEM3:  next_stage = STORE_MEM4;
            STORE_MEM4:  next_stage = store_mem16 ? STORE_MEM5 : WRITEBACK;
            STORE_MEM5:  next_stage = STORE_MEM6;
            STORE_MEM6:  next_stage = STORE_MEM7;
            STORE_MEM7:  next_stage = STORE_MEM8;
            STORE_MEM8:  next_stage = WRITEBACK;
            WRITEBACK:   next_stage = halted ? HALTED : FETCH;
            // TODO add 4 cycles for jumps (except LD PC, HL)
            default:     next_stage = HALTED;
        endcase


/*
 * Instruction decoding
 */

/* Determine reg8 operand of certain opcode bits. */
function [4:0] decode_operand_reg8(input [2:0] operand_bits);
    case (operand_bits)
        3'b000: decode_operand_reg8 = DE_REG_B;
        3'b001: decode_operand_reg8 = DE_REG_C;
        3'b010: decode_operand_reg8 = DE_REG_D;
        3'b011: decode_operand_reg8 = DE_REG_E;
        3'b100: decode_operand_reg8 = DE_REG_H;
        3'b101: decode_operand_reg8 = DE_REG_L;
        3'b110: decode_operand_reg8 = DE_HLMEM;
        3'b111: decode_operand_reg8 = DE_REG_A;
    endcase
endfunction

/* Determine reg16 operand of certain opcode bits. */
function [4:0] decode_operand_reg16(input [1:0] operand_bits, input allow_AF);
    case (operand_bits)
        2'b00: decode_operand_reg16 = DE_REG_BC;
        2'b01: decode_operand_reg16 = DE_REG_DE;
        2'b10: decode_operand_reg16 = DE_REG_HL;
        2'b11: decode_operand_reg16 = allow_AF ? DE_REG_AF : DE_SP;
    endcase
endfunction

/* Determine conditional operand of certain opcode bits. */
function decode_operand_cond(input [1:0] operand_bits);
    case (operand_bits)
        2'b00: decode_operand_cond = ~Z;
        2'b01: decode_operand_cond = Z;
        2'b10: decode_operand_cond = ~C;
        2'b11: decode_operand_cond = C;
    endcase
endfunction

/* Instruction decoder (for non-cb prefix instructions). */
always @(*) begin
    decode_cb_prefix = 0;
    decode_alu_op = ALU_NOP;
    decode_oper1 = DE_REG_A;
    decode_oper2 = DE_NONE;
    decode_oper1_constval = 'hffff;
    decode_oper2_constval = 16'h0001;
    decode_dest = DE_NONE;
    decode_halt = 0;
    decode_instruction_not_implemented = 0;
    decode_flags_mask = 4'h0;
    decode_flags_override_reset = 4'h0;
    decode_flags_override_set = 4'h0;
    decode_16bit = 0;
    decode_HL_op = HL_OP_NONE;
    decode_SP_op = SP_OP_NONE;
    decode_load_mem8 = 0;
    decode_load_mem16 = 0;
    decode_store_mem8 = 0;
    decode_store_mem16 = 0;
    decode_store_addr_oper = DE_CONST;
    decode_store_data_oper = DE_CONST;
    decode_store_addr_constval = 16'hffff;
    decode_store_data_constval = 16'hffff;
    decode_intm_disable = 0;
    decode_intm_enable = 0;

    decode_opcode = mem_data_read;
    opc = decode_opcode;

    if (opc == 'h00) begin                          // NOP
        ;
    end else if (opc == 'h76) begin                 // HALT
        decode_halt = 1;

    end else if (opc == 'hf3) begin                 // DI
        decode_intm_disable = 1;
    end else if (opc == 'hfb) begin                 // EI
        decode_intm_enable = 1;

    end else if ((opc & 'hcf) == 'h01) begin        // LD r16, imm16
        decode_dest = decode_operand_reg16(opc[5:4], 0);
        decode_oper1 = DE_IMM16;
    end else if ((opc & 'hc7) == 'h06) begin        // LD r8, imm8
        decode_oper1 = DE_IMM8;
        decode_dest = decode_operand_reg8(opc[5:3]);

    end else if ((opc & 'hc0) == 'h40) begin        // LD r8, r8
        decode_oper1 = decode_operand_reg8(opc[2:0]);
        decode_dest = decode_operand_reg8(opc[5:3]);


    end else if ((opc & 'hef) == 'h0a) begin        // LD A, (r16)
        decode_load_mem8 = 1;
        decode_oper1 = decode_operand_reg16(opc[5:4], 0);
        decode_dest = DE_REG_A;
    end else if (opc == 'h2a) begin                 // LD A, (HL+)
        decode_load_mem8 = 1;
        decode_oper1 = DE_REG_HL;
        decode_dest = DE_REG_A;
        decode_HL_op = HL_OP_INC;
    end else if (opc == 'h3a) begin                 // LD A, (HL-)
        decode_load_mem8 = 1;
        decode_oper1 = DE_REG_HL;
        decode_dest = DE_REG_A;
        decode_HL_op = HL_OP_DEC;
    end else if (opc == 'hf0) begin                 // LD A, ($FF00+imm8)
        decode_load_mem8 = 1;
        decode_oper1 = DE_IO_IMM;
        decode_dest = DE_REG_A;
    end else if (opc == 'hfa) begin                 // LD A, (imm16)
        decode_load_mem8 = 1;
        decode_oper1 = DE_IMM16;
        decode_dest = DE_REG_A;

    end else if ((opc & 'hef) == 'h02) begin        // LD (r16), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = decode_operand_reg16(opc[5:4], 0);
        decode_store_data_oper = DE_REG_A;
    end else if (opc == 'h22) begin                 // LD (HL+), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = DE_REG_HL;
        decode_store_data_oper = DE_REG_A;
        decode_HL_op = HL_OP_INC;
    end else if (opc == 'h32) begin                 // LD (HL-), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = DE_REG_HL;
        decode_store_data_oper = DE_REG_A;
        decode_HL_op = HL_OP_DEC;
    end else if (opc == 'hea) begin                 // LD (imm16), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = DE_IMM16;
        decode_store_data_oper = DE_REG_A;
    end else if (opc == 'he2) begin                 // LD ($FF00+C), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = DE_IO_C;
        decode_store_data_oper = DE_REG_A;
    end else if (opc == 'he0) begin                 // LD ($FF00+imm8), A
        decode_store_mem8 = 1;
        decode_store_addr_oper = DE_IO_IMM;
        decode_store_data_oper = DE_REG_A;

    end else if ((opc & 'hcf) == 'hc5) begin        // PUSH r16
        decode_store_mem16 = 1;
        decode_store_addr_constval = sp - 2;
        decode_store_data_oper = decode_operand_reg16(opc[5:4], 1);
        decode_SP_op = SP_OP_DEC2;
    end else if ((opc & 'hcf) == 'hc1) begin        // POP r16
        decode_load_mem16 = 1;
        decode_oper1 = DE_SP;
        decode_dest = decode_operand_reg16(opc[5:4], 1);
        decode_SP_op = SP_OP_INC2;

    end else if (opc == 'hcd) begin                 // CALL imm16
        decode_store_mem16 = 1;
        decode_store_addr_constval = sp - 2;
        decode_store_data_constval = pc + 3;
        decode_SP_op = SP_OP_DEC2;
        decode_oper1 = DE_IMM16;
        decode_dest = DE_PC;
    end else if (opc == 'hc9) begin                 // RET
        decode_load_mem16 = 1;
        decode_oper1 = DE_SP;
        decode_dest = DE_PC;
        decode_SP_op = SP_OP_INC2;
    end else if ((opc & 'he7) == 'hc0) begin        // RET cc
        decode_cond = decode_operand_cond(opc[4:3]);
        decode_load_mem16 = decode_cond;
        decode_oper1 = DE_SP;
        decode_dest = decode_cond ? DE_PC : DE_NONE;
        decode_SP_op = decode_cond ? SP_OP_INC2 : SP_OP_NONE;

    end else if ((opc & 'hc7) == 'hc7) begin        // RST vec
        decode_store_mem16 = 1;
        decode_store_addr_constval = sp - 2;
        decode_store_data_constval = pc + 1;
        decode_SP_op = SP_OP_DEC2;
        decode_oper1 = DE_CONST;
        decode_oper1_constval = {10'h0, opc[5:3], 3'b000};
        decode_dest = DE_PC;

    end else if (opc == 'hc3) begin                 // JP imm16
        decode_oper1 = DE_IMM16;
        decode_dest = DE_PC;
    end else if (opc == 'h18) begin                 // JR off8
        decode_alu_op = ALU_ADD;
        decode_oper1 = DE_IMM8;
        decode_oper2 = DE_PC;
        decode_dest = DE_PC;
    end else if ((opc & 'he7) == 'hc2) begin        // JP cc, imm16
        decode_oper1 = DE_IMM16;
        decode_dest = DE_PC;
        decode_cond = decode_operand_cond(opc[4:3]);
        decode_dest = decode_cond ? DE_PC : DE_NONE;
    end else if ((opc & 'he7) == 'h20) begin        // JR cc, off8
        decode_alu_op = ALU_ADD;
        decode_oper1 = DE_IMM8;
        decode_oper2 = DE_PC;
        decode_cond = decode_operand_cond(opc[4:3]);
        decode_dest = decode_cond ? DE_PC : DE_NONE;

    end else if (opc == 'h17) begin                 // RLA
        decode_alu_op = ALU_RL;
        decode_oper1 = DE_REG_A;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
        decode_flags_override_reset = 4'b1000;
    end else if (opc == 'h2f) begin                 // CPL
        decode_alu_op = ALU_XOR;
        decode_oper1 = DE_REG_A;
        decode_oper2 = DE_CONST;
        decode_oper2_constval = 'hff;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b0110;
        decode_flags_override_set = 4'b0110;
    end else if ((opc & 'hc7) == 'h04) begin        // INC r8
        decode_alu_op = ALU_ADD;
        decode_oper1 = decode_operand_reg8(opc[5:3]);
        decode_oper2 = DE_CONST;
        decode_dest = decode_operand_reg8(opc[5:3]);
        decode_flags_mask = 4'b1110;
    end else if ((opc & 'hc7) == 'h05) begin        // DEC r8
        decode_alu_op = ALU_SUB;
        decode_oper1 = decode_operand_reg8(opc[5:3]);
        decode_oper2 = DE_CONST;
        decode_dest = decode_operand_reg8(opc[5:3]);
        decode_flags_mask = 4'b1110;
    end else if ((opc & 'hf8) == 'h80) begin        // ADD r8
        decode_alu_op = ALU_ADD;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'h88) begin        // ADC r8
        decode_alu_op = ALU_ADC;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'h90) begin        // SUB r8
        decode_alu_op = ALU_SUB;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'h98) begin        // SBC r8
        decode_alu_op = ALU_SBC;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'ha0) begin        // AND r8
        decode_alu_op = ALU_AND;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'ha8) begin        // XOR r8
        decode_alu_op = ALU_XOR;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'hb0) begin        // OR r8
        decode_alu_op = ALU_OR;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if ((opc & 'hf8) == 'hb8) begin        // CP r8
        decode_alu_op = ALU_SUB;
        decode_oper2 = decode_operand_reg8(opc[2:0]);
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hc6) begin                 // ADD imm8
        decode_alu_op = ALU_ADD;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hd6) begin                 // SUB imm8
        decode_alu_op = ALU_SUB;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'he6) begin                 // AND imm8
        decode_alu_op = ALU_AND;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hf6) begin                 // OR imm8
        decode_alu_op = ALU_OR;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hce) begin                 // ADC imm8
        decode_alu_op = ALU_ADC;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hde) begin                 // SBC imm8
        decode_alu_op = ALU_SBC;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hee) begin                 // XOR imm8
        decode_alu_op = ALU_XOR;
        decode_oper2 = DE_IMM8;
        decode_dest = DE_REG_A;
        decode_flags_mask = 4'b1111;
    end else if (opc == 'hfe) begin                 // CP imm8
        decode_alu_op = ALU_SUB;
        decode_oper2 = DE_IMM8;
        decode_flags_mask = 4'b1111;

    end else if ((opc & 'hcf) == 'h03) begin        // INC r16
        decode_alu_op = ALU_ADD;
        decode_oper1 = decode_operand_reg16(opc[5:4], 0);
        decode_oper2 = DE_CONST;
        decode_dest = decode_operand_reg16(opc[5:4], 0);
    end else if ((opc & 'hcf) == 'h0b) begin        // DEC r16
        decode_alu_op = ALU_SUB;
        decode_oper1 = decode_operand_reg16(opc[5:4], 0);
        decode_oper2 = DE_CONST;
        decode_dest = decode_operand_reg16(opc[5:4], 0);
    end else if ((opc & 'hcf) == 'h09) begin        // ADD HL, r
        decode_alu_op = ALU_ADD;
        decode_16bit = 1;
        decode_oper1 = DE_REG_HL;
        decode_oper2 = decode_operand_reg16(opc[5:4], 0);
        decode_dest = DE_REG_HL;
        decode_flags_mask = 4'b0111;

    end else if (opc == 'hcb) begin                 // CB prefix
        decode_cb_prefix = 1;

    end else
        decode_instruction_not_implemented = 1;

    decode_instr_length = (decode_oper1 == DE_IMM16 ||
                           decode_store_addr_oper == DE_IMM16) ? 3 : (
                          (decode_oper1 == DE_IMM8 ||
                           decode_oper2 == DE_IMM8 ||
                           decode_oper1 == DE_IO_IMM ||
                           decode_store_addr_oper == DE_IMM8 ||
                           decode_store_addr_oper == DE_IO_IMM ||
                           decode_cb_prefix) ? 2 :
                                               1);
end

/* Instruction decoder for CB-prefixed instructions. */
always @(*) begin
    decode_cb_opcode = mem_data_read;
    decode_cb_alu_op = ALU_NOP;
    decode_cb_oper2 = DE_NONE;
    decode_cb_oper2_constval = 8'h01;
    decode_cb_instruction_not_implemented = 0;

    decode_cb_oper1 = decode_operand_reg8(decode_cb_opcode[2:0]);
    decode_cb_dest = decode_operand_reg8(decode_cb_opcode[2:0]);
    decode_cb_flags_mask = 4'b1111;

    if ((decode_cb_opcode & 'hf8) == 'h00) begin            // RLC r8
        decode_cb_alu_op = ALU_RLC;
    end else if ((decode_cb_opcode & 'hf8) == 'h08) begin   // RRC r8
        decode_cb_alu_op = ALU_RRC;
    end else if ((decode_cb_opcode & 'hf8) == 'h10) begin   // RL r8
        decode_cb_alu_op = ALU_RL;
    end else if ((decode_cb_opcode & 'hf8) == 'h18) begin   // RR r8
        decode_cb_alu_op = ALU_RR;
    end else if ((decode_cb_opcode & 'hf8) == 'h20) begin   // SLA r8
        decode_cb_alu_op = ALU_SLA;
    end else if ((decode_cb_opcode & 'hf8) == 'h28) begin   // SRA r8
        decode_cb_alu_op = ALU_SRA;
    end else if ((decode_cb_opcode & 'hf8) == 'h30) begin   // SWAP r8
        decode_cb_alu_op = ALU_SWAP;
    end else if ((decode_cb_opcode & 'hf8) == 'h38) begin   // SRL r8
        decode_cb_alu_op = ALU_SRL;
    end else if ((decode_cb_opcode & 'hc0) == 'h40) begin   // BIT n, r8
        decode_cb_alu_op = ALU_AND;
        decode_cb_oper2 = DE_CONST;
        decode_cb_oper2_constval = 8'b1 << decode_cb_opcode[5:3];
        decode_cb_dest = DE_NONE;
        decode_cb_flags_mask = 4'b1110;
    end else if ((decode_cb_opcode & 'hc0) == 'h80) begin   // RES n, r8
        decode_cb_alu_op = ALU_AND;
        decode_cb_oper2 = DE_CONST;
        decode_cb_oper2_constval = ~(8'b1 << decode_cb_opcode[5:3]);
        decode_cb_flags_mask = 4'b0000;
    end else if ((decode_cb_opcode & 'hc0) == 'hc0) begin   // SET n, r8
        decode_cb_alu_op = ALU_OR;
        decode_cb_oper2 = DE_CONST;
        decode_cb_oper2_constval = 8'b1 << decode_cb_opcode[5:3];
        decode_cb_flags_mask = 4'b0000;
    end else
        decode_cb_instruction_not_implemented = 1;
end


function automatic [15:0] operand_mux(input [4:0] operand, input [15:0] const_value);
    case (operand)
        DE_NONE:   operand_mux = 'hffff;
        DE_CONST:  operand_mux = const_value;
        DE_IMM8:   operand_mux = 'hffff; // Overwritten after reading mem.
        DE_IMM16:  operand_mux = 'hffff; // Overwritten after reading mem.
        DE_PC:     operand_mux = pc + {14'b0, decode_instr_length};
        DE_SP:     operand_mux = sp;
        DE_REG_A:  operand_mux = sext(reg_A);
        DE_REG_B:  operand_mux = sext(reg_B);
        DE_REG_C:  operand_mux = sext(reg_C);
        DE_REG_D:  operand_mux = sext(reg_D);
        DE_REG_E:  operand_mux = sext(reg_E);
        DE_REG_H:  operand_mux = sext(reg_H);
        DE_REG_L:  operand_mux = sext(reg_L);
        DE_REG_AF: operand_mux = {reg_A, reg_F};
        DE_REG_BC: operand_mux = {reg_B, reg_C};
        DE_REG_DE: operand_mux = {reg_D, reg_E};
        DE_REG_HL: operand_mux = {reg_H, reg_L};
        DE_HLMEM:  operand_mux = {reg_H, reg_L}; // Used as addr, overwritten.
        DE_IO_C:   operand_mux = {8'hff, reg_C};
        DE_IO_IMM: operand_mux = 16'hff00; // Lower by overwritten by imm

        default: begin
            operand_mux = 'hffff;
            `ifndef SYNTHESIS
                $display("Unknown operand: ", operand);
                $finish;
            `endif
        end
    endcase
endfunction

/*
 * Execution - ALU
 */
always @(*)
    case (alu_op)
        ALU_NOP:  begin alu_out = {1'b0, exec_oper1}; end
        ALU_ADD:  begin alu_out = {1'b0, exec_oper1} + {1'b0, exec_oper2}; end
        ALU_ADC:  begin alu_out = {1'b0, exec_oper1} + {1'b0, exec_oper2} + {16'b0, C}; end
        ALU_SUB:  begin alu_out = {1'b0, exec_oper1} - {1'b0, exec_oper2}; end
        ALU_SBC:  begin alu_out = {1'b0, exec_oper1} - {1'b0, exec_oper2} - {16'b0, C}; end
        ALU_AND:  begin alu_out = {1'b0, exec_oper1} & {1'b0, exec_oper2}; end
        ALU_XOR:  begin alu_out = {1'b0, exec_oper1} ^ {1'b0, exec_oper2}; end
        ALU_OR:   begin alu_out = {1'b0, exec_oper1} | {1'b0, exec_oper2}; end
        ALU_RLC:  begin alu_out = {9'b0, exec_oper1[6:0], exec_oper1[7]}; end
        ALU_RRC:  begin alu_out = {9'b0, exec_oper1[0], exec_oper1[7:1]}; end
        ALU_RL:   begin alu_out = {9'b0, exec_oper1[6:0], C}; end
        ALU_RR:   begin alu_out = {9'b0, C, exec_oper1[7:1]}; end
        ALU_SLA:  begin alu_out = {9'b0, exec_oper1[6:0], 1'b0}; end
        ALU_SRA:  begin alu_out = {9'b0, exec_oper1[7], exec_oper1[7:1]}; end
        ALU_SWAP: begin alu_out = {9'b0, exec_oper1[3:0], exec_oper1[7:4]}; end
        ALU_SRL:  begin alu_out = {9'b0, 1'b0, exec_oper1[7:1]}; end
        default:  alu_out = 17'hFFFF;
    endcase

assign alu_out_Z = alu_16bit ? (alu_out[15:0] == 16'h0000) :
                               (alu_out[7:0] == 8'h00);
assign alu_out_N = alu_op == ALU_SUB || alu_op == ALU_SBC;
assign alu_out_H = alu_op == ALU_AND ||
                   ((alu_op == ALU_ADD || alu_op == ALU_ADC ||
                     alu_op == ALU_SUB || alu_op == ALU_SBC) &&
                    (alu_16bit ? exec_oper1[12] ^ exec_oper2[12] ^ alu_out[12]
                               : exec_oper1[4] ^ exec_oper2[4] ^ alu_out[4]));
always @(*)
    case (alu_op)
        ALU_ADD, ALU_ADC, ALU_SUB, ALU_SBC:
            alu_out_C = alu_16bit ? alu_out[16] :
                            (exec_oper1[8] ^ exec_oper2[8] ^ alu_out[8]);
        ALU_RLC, ALU_RL,
        ALU_SLA:
            alu_out_C = exec_oper1[7];
        ALU_RRC, ALU_RR,
        ALU_SRA, ALU_SRL:
            alu_out_C = exec_oper1[0];
        default:
            alu_out_C = 0;
    endcase

/*
 * Datapath between stages (propagate on clock).
 */
always @(posedge clk)
    if (reset) begin
        `ifdef DEBUG_CPU
            $display("[CPU] Reset");
        `endif
        stage <= RESET;
        halted <= 0;
        pc <= 16'h0000;
        sp <= 16'h0000;
        reg_A <= 8'h00;
        reg_B <= 8'h00;
        reg_C <= 8'h00;
        reg_D <= 8'h00;
        reg_E <= 8'h00;
        reg_H <= 8'h00;
        reg_L <= 8'h00;
        {Z, N, H, C} <= 4'h0;
        mem_do_write <= 0;
        mem_addr <= 0;
        interrupts_master_enabled <= 1;
    end else begin
        case (next_stage)
        FETCH: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Fetch %04x", pc);
            `endif
            // For simulations (in particular, testcases), (re)start the fetch
            // in case we start execution here (without reset cycles).
            mem_addr <= pc;
        end

        DECODE: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode opcode %02x", decode_opcode);
            `endif
            if (decode_instruction_not_implemented) begin
                `ifndef SYNTHESIS
                    $display("Opcode not implemented: %02x", decode_opcode);
                    $finish;
                `endif
                halted <= 1;
            end

            if (decode_halt)
                halted <= 1;

            dbg_last_opcode <= decode_opcode;

            alu_op <= decode_alu_op;
            alu_16bit <= decode_16bit;
            exec_oper1 <= operand_mux(decode_oper1, decode_oper1_constval);
            exec_oper2 <= operand_mux(decode_oper2, decode_oper2_constval);

            decode_has_imm_operand <= decode_oper1 == DE_IMM8 ||
                                      decode_oper1 == DE_IMM16 ||
                                      decode_oper1 == DE_IO_IMM ||
                                      decode_oper2 == DE_IMM8 ||
                                      decode_oper2 == DE_IMM16 ||
                                      decode_store_addr_oper == DE_IMM8 ||
                                      decode_store_addr_oper == DE_IMM16 ||
                                      decode_store_addr_oper == DE_IO_IMM;
            decode_has_imm16_operand <= decode_oper1 == DE_IMM16 ||
                                        decode_oper2 == DE_IMM16 ||
                                        decode_store_addr_oper == DE_IMM16;
            decode_imm_operand_is_store_addr <= decode_store_addr_oper == DE_IMM8 ||
                                                decode_store_addr_oper == DE_IMM16 ||
                                                decode_store_addr_oper == DE_IO_IMM;
            decode_imm_operand_is_oper2 <= decode_oper2 == DE_IMM8 ||
                                           decode_oper2 == DE_IMM16;

            load_mem <= decode_load_mem8 || decode_load_mem16 ||
                        decode_oper1 == DE_HLMEM || decode_oper2 == DE_HLMEM ||
                        decode_oper1 == DE_IO_IMM;
            load_mem16 <= decode_load_mem16;
            load_use_oper2 <= decode_oper2 == DE_HLMEM;
            load_from_iospace <= decode_oper1 == DE_IO_IMM;

            store_mem <= decode_store_mem8 || decode_store_mem16 ||
                         decode_dest == DE_HLMEM;
            store_mem16 <= decode_store_mem16;
            store_mem_addr <= operand_mux(decode_dest == DE_HLMEM ? DE_HLMEM : decode_store_addr_oper, decode_store_addr_constval);
            store_mem_data <= operand_mux(decode_store_data_oper, decode_store_data_constval);
            store_mem_execout <= decode_dest == DE_HLMEM;

            wb_dest <= decode_dest;
            wb_pc <= pc + {14'b0, decode_instr_length};
            wb_flags_mask <= decode_flags_mask;
            wb_flags_override_set <= decode_flags_override_set;
            wb_flags_override_reset <= decode_flags_override_reset;
            wb_HL_op <= decode_HL_op;
            wb_SP_op <= decode_SP_op;
            wb_intm_disable <= decode_intm_disable;
            wb_intm_enable <= decode_intm_enable;
        end

        DECODE_CB1: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Fetch CB %04x", pc + 16'h1);
            `endif
            mem_addr <= pc + 16'h1;
        end
        DECODE_CB3: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode opcode cb %02x", decode_cb_opcode);
            `endif
            if (decode_cb_instruction_not_implemented) begin
                `ifndef SYNTHESIS
                    $display("Opcode not implemented: cb %02x", decode_cb_opcode);
                    $finish;
                `endif
                halted <= 1;
            end

            alu_op <= decode_cb_alu_op;
            exec_oper1 <= operand_mux(decode_cb_oper1, 16'hdead);
            exec_oper2 <= operand_mux(decode_cb_oper2, {8'h00, decode_cb_oper2_constval});
            wb_dest <= decode_cb_dest;
            wb_flags_mask <= decode_cb_flags_mask;

            load_mem <= decode_cb_oper1 == DE_HLMEM;
            load_mem16 <= 0;
            load_use_oper2 <= 0;
            load_from_iospace <= 0;

            store_mem <= decode_cb_dest == DE_HLMEM;
            store_mem_addr <= operand_mux(DE_HLMEM, 0);
            store_mem_execout <= 1;
        end

        DECODE_IMM1: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode reading operand from %04x", pc + 16'h1);
            `endif
            mem_addr <= pc + 16'h1;
        end
        DECODE_IMM3: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode read operand %02x", mem_data_read);
            `endif
            if (decode_imm_operand_is_store_addr)
                store_mem_addr[7:0] <= mem_data_read;
            else if (decode_imm_operand_is_oper2)
                exec_oper2 <= sext(mem_data_read);
            else
                exec_oper1 <= sext(mem_data_read);
        end
        DECODE_IMM5: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode reading operand from %04x", pc + 16'h2);
            `endif
            mem_addr <= pc + 16'h2;
        end
        DECODE_IMM7: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Decode read operand %02x", mem_data_read);
            `endif
            if (decode_imm_operand_is_store_addr)
                store_mem_addr[15:8] <= mem_data_read;
            else if (decode_imm_operand_is_oper2)
                exec_oper2[15:8] <= mem_data_read;
            else
                exec_oper1[15:8] <= mem_data_read;
        end

        LOAD_MEM1: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Load from %04x", exec_oper1);
            `endif
            if (load_use_oper2)
                mem_addr <= load_from_iospace ? {8'hff, exec_oper2[7:0]} : exec_oper2;
            else
                mem_addr <= load_from_iospace ? {8'hff, exec_oper1[7:0]} : exec_oper1;
        end
        LOAD_MEM3: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Load result %02x", mem_data_read);
            `endif
            load_mem_addr <= mem_addr;
            if (load_use_oper2)
                exec_oper2 <= sext(mem_data_read);
            else
                exec_oper1 <= sext(mem_data_read);
        end
        LOAD_MEM5: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Load from %04x", load_mem_addr + 16'h1);
            `endif
            mem_addr <= load_mem_addr + 16'h1;
        end
        LOAD_MEM7: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Load result %02x", mem_data_read);
            `endif
            if (load_use_oper2)
                exec_oper2[15:8] <= mem_data_read;
            else
                exec_oper1[15:8] <= mem_data_read;
        end

        EXECUTE: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Execute ALU op %x  in1: %04x  in2: %04x  out: %04x  F %d%d%d%d", alu_op, exec_oper1, exec_oper2, alu_out[15:0], alu_out_Z, alu_out_N, alu_out_H, alu_out_C);
            `endif
            wb_data <= alu_out[15:0];
            wb_flags <= {alu_out_Z, alu_out_N, alu_out_H, alu_out_C};
            if (store_mem_execout)
                store_mem_data <= alu_out[15:0];
        end

        STORE_MEM1: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Store %02x to %04x", store_mem_data[7:0], store_mem_addr);
            `endif
            mem_addr <= store_mem_addr;
            mem_data_write <= store_mem_data[7:0];
            mem_do_write <= 1;
        end
        STORE_MEM2: begin
            mem_do_write <= 0;
        end
        STORE_MEM5: begin
            `ifdef DEBUG_CPU
                $display("[CPU] Store %02x to %04x", store_mem_data[15:8], store_mem_addr + 16'h1);
            `endif
            mem_addr <= store_mem_addr + 16'h1;
            mem_data_write <= store_mem_data[15:8];
            mem_do_write <= 1;
        end
        STORE_MEM6: begin
            mem_do_write <= 0;
        end

        WRITEBACK: begin
            `ifdef DEBUG_CPU
                $display("[CPU] WB %04x to %x", wb_data, wb_dest);
            `endif

            pc <= wb_dest == DE_PC ? wb_data : wb_pc;
            mem_addr <= wb_dest == DE_PC ? wb_data : wb_pc; // Start next fetch

            {Z, N, H, C} <= ((reg_Fh & ~wb_flags_mask) |
                             (wb_flags & wb_flags_mask))
                            & ~wb_flags_override_reset
                            | wb_flags_override_set;

            interrupts_master_enabled <= wb_intm_disable ? 0 :
                                         wb_intm_enable  ? 1 :
                                         interrupts_master_enabled;

            case (wb_dest)
                DE_SP:     sp <= wb_data;
                DE_REG_A:  reg_A <= wb_data[7:0];
                DE_REG_B:  reg_B <= wb_data[7:0];
                DE_REG_C:  reg_C <= wb_data[7:0];
                DE_REG_D:  reg_D <= wb_data[7:0];
                DE_REG_E:  reg_E <= wb_data[7:0];
                DE_REG_H:  reg_H <= wb_data[7:0];
                DE_REG_L:  reg_L <= wb_data[7:0];
                DE_REG_AF: {reg_A, Z, N, H, C} <= wb_data[15:4];
                DE_REG_BC: {reg_B, reg_C} <= wb_data;
                DE_REG_DE: {reg_D, reg_E} <= wb_data;
                DE_REG_HL: {reg_H, reg_L} <= wb_data;
            endcase

            case (wb_HL_op)
                HL_OP_INC: {reg_H, reg_L} <= {reg_H, reg_L} + 16'h0001;
                HL_OP_DEC: {reg_H, reg_L} <= {reg_H, reg_L} - 16'h0001;
            endcase

            case (wb_SP_op)
                SP_OP_INC2: sp <= sp + 16'h0002;
                SP_OP_DEC2: sp <= sp - 16'h0002;
            endcase

        end
        endcase // next_stage

        stage <= next_stage;
    end
endmodule
