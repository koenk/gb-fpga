module cpu (
    input clk,
    input reset,

    output reg [15:0] mem_addr,
    output [7:0] mem_data_write,
    input [7:0] mem_data_read,
    output mem_do_write,

    output cpu_is_halted,

    output [15:0] dbg_pc,
    output [15:0] dbg_sp,
    output [15:0] dbg_AF,
    output [15:0] dbg_BC,
    output [15:0] dbg_DE,
    output [15:0] dbg_HL,
    output dbg_instruction_retired
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
           DECODE_MEM1 = 4,
           DECODE_MEM2 = 5,
           DECODE_MEM3 = 6,
           DECODE_MEM4 = 7,
           DECODE_MEM5 = 8,
           DECODE_MEM6 = 9,
           DECODE_MEM7 = 10,
           DECODE_MEM8 = 11,
           LOAD_MEM1   = 12,
           LOAD_MEM2   = 13,
           LOAD_MEM3   = 14,
           LOAD_MEM4   = 15,
           LOAD_MEM5   = 16,
           LOAD_MEM6   = 17,
           LOAD_MEM7   = 18,
           LOAD_MEM8   = 19,
           EXECUTE     = 20,
           WRITEBACK   = 21;

// TODO temporary instructions
localparam OP_NOP   = 5'h00,
           OP_HLT   = 5'h01,
           OP_MOV   = 5'h02,
           OP_LDI   = 5'h03,
           OP_LD    = 5'h04,
           OP_ST    = 5'h05,
           OP_ADD   = 5'h06,
           OP_SUB   = 5'h07,
           OP_OR    = 5'h08,
           OP_AND   = 5'h09,
           OP_XOR   = 5'h0a,
           OP_INC   = 5'h0b,
           OP_DEC   = 5'h0c,
           OP_JR    = 5'h0d,
           OP_JRCC  = 5'h0f,
           OP_INC16 = 5'h10,
           OP_DEC16 = 5'h11,
           OP_ADD16 = 5'h12,
           OP_JP    = 5'h13,
           OP_JPCC  = 5'h14,
           OP_LDI16 = 5'h15,
           OP_LD16  = 5'h16,
           OP_LDHLI = 5'h17;

localparam OPARG_REG_A = 0,
           OPARG_REG_B = 1,
           OPARG_REG_C = 2,
           OPARG_REG_D = 3,
           OPARG_REG_E = 4,
           OPARG_REG_H = 5,
           OPARG_REG_L = 6;
localparam OPARG_REG_BC = 0,
           OPARG_REG_DE = 1,
           OPARG_REG_HL = 2,
           OPARG_REG_SP = 3, // For arith
           OPARG_REG_AF = 3; // For pop
localparam OPARG_COND_Z = 0,
           OPARG_COND_C = 1,
           OPARG_COND_NZ = 2,
           OPARG_COND_NC = 3;

/* Operations the ALU can perform. */
localparam ALU_NOP = 0,
           ALU_ADD = 1,
           ALU_SUB = 2,
           ALU_OR  = 3,
           ALU_AND = 4,
           ALU_XOR = 5;

/* Possible parameters during decoding (both source during decode/execute, and
 * destination during writeback). */
localparam DE_NONE   = 0,
           DE_CONST  = 1,
           DE_MEM    = 2,
           DE_MEM16  = 3,
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
           DE_REG_HL = 16;

/* How to modify the HL register during writeback. */
localparam HL_OP_NONE = 0,
           HL_OP_INC  = 1,
           HL_OP_DEC  = 2;

reg [4:0] stage, next_stage;

reg halted;
reg [15:0] pc, sp;
reg Z, N, H, C;
reg [7:0] reg_A, reg_B, reg_C, reg_D, reg_E, reg_H, reg_L;
wire [7:0] reg_F;
wire [3:0] reg_Fh;

reg decode_halt;
reg decode_instruction_not_implemented;
reg decode_16bit;
reg [2:0] decode_alu_op;
reg [4:0] decode_oper1, decode_oper2;
reg [15:0] decode_oper1_val, decode_oper2_val;
reg [1:0] decode_instr_length;
reg [4:0] decode_dest;
reg [7:0] decode_opcode;
reg [3:0] decode_flags_mask;
reg [1:0] decode_HL_op;
reg [4:0] op_reg8, op_reg16;
reg op_cond;
reg decode_load_mem8, decode_load_mem16;

reg decode_has_mem_operand, decode_has_mem16_operand;
reg load_mem, load_mem16;
reg [15:0] load_mem_addr;

reg alu_16bit;
reg [2:0] alu_op;
reg [15:0] exec_oper1, exec_oper2;
reg [16:0] alu_out; // 16 bit + 1 bit for capturing carry
wire alu_out_Z, alu_out_N, alu_out_H, alu_out_C;

reg [4:0] wb_dest;
reg [15:0] wb_data;
reg [15:0] wb_pc;
reg [3:0] wb_flags, wb_flags_mask;
reg [1:0] wb_HL_op;

localparam MEMBUS_PC=0, MEMBUS_OPER=1, MEMBUS_LOAD=2;
/* verilator lint_off UNUSED */
reg[1:0] mem_bus_ctrl;
/* verilator lint_on UNUSED */

// TEMP
assign mem_data_write = 0;
assign mem_do_write = 0;

assign cpu_is_halted = halted;

assign dbg_pc = pc;
assign dbg_sp = sp;
assign dbg_AF = {reg_A, reg_F};
assign dbg_BC = {reg_B, reg_C};
assign dbg_DE = {reg_D, reg_E};
assign dbg_HL = {reg_H, reg_L};
assign dbg_instruction_retired = stage == WRITEBACK;

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
            DECODE:      next_stage = decode_has_mem_operand ? DECODE_MEM1 :
                                      (load_mem ? LOAD_MEM1 : EXECUTE);
            DECODE_MEM1: next_stage = DECODE_MEM2;
            DECODE_MEM2: next_stage = DECODE_MEM3;
            DECODE_MEM3: next_stage = DECODE_MEM4;
            DECODE_MEM4: next_stage = decode_has_mem16_operand ? DECODE_MEM5 :
                                      (load_mem ? LOAD_MEM1 : EXECUTE);
            DECODE_MEM5: next_stage = DECODE_MEM6;
            DECODE_MEM6: next_stage = DECODE_MEM7;
            DECODE_MEM7: next_stage = DECODE_MEM8;
            DECODE_MEM8: next_stage = load_mem ? LOAD_MEM1 : EXECUTE;
            LOAD_MEM1:   next_stage = LOAD_MEM2;
            LOAD_MEM2:   next_stage = LOAD_MEM3;
            LOAD_MEM3:   next_stage = LOAD_MEM4;
            LOAD_MEM4:   next_stage = load_mem16 ? LOAD_MEM5 : EXECUTE;
            LOAD_MEM5:   next_stage = LOAD_MEM6;
            LOAD_MEM6:   next_stage = LOAD_MEM7;
            LOAD_MEM7:   next_stage = LOAD_MEM8;
            LOAD_MEM8:   next_stage = EXECUTE;
            EXECUTE:     next_stage = WRITEBACK;
            WRITEBACK:   next_stage = halted ? HALTED : FETCH;
            // TODO add 4 cycles for jumps (except LD PC, HL)
            default:     next_stage = HALTED;
        endcase

/*
 * Instruction decoder
 */
always @(*) begin
    decode_alu_op = ALU_NOP;
    decode_oper1 = DE_REG_A;
    decode_oper2 = DE_NONE;
    decode_oper1_val = 'hffff;
    decode_oper2_val = 16'h0001;
    decode_dest = DE_NONE;
    decode_halt = 0;
    decode_instruction_not_implemented = 0;
    decode_flags_mask = 4'h0;
    decode_16bit = 0;
    decode_HL_op = HL_OP_NONE;
    decode_load_mem8 = 0;
    decode_load_mem16 = 0;

    decode_opcode = mem_data_read;

    op_reg8 = decode_operand_reg8(decode_opcode[7:5]);
    op_reg16 = decode_operand_reg16(decode_opcode[7:6]);
    op_cond = decode_operand_cond(decode_opcode[7:6]);

    case (decode_opcode[4:0])
        OP_NOP: ;
        OP_HLT:  decode_halt = 1;
        OP_MOV:  begin decode_dest = op_reg8; end
        OP_LDI:  begin decode_dest = op_reg8; decode_oper1 = DE_MEM; end
        OP_LD:   begin decode_dest = op_reg8; decode_oper1 = DE_MEM16; decode_load_mem8 = 1; end
        //OP_ST:
        OP_ADD:  begin decode_alu_op = ALU_ADD; decode_oper2 = op_reg8; decode_dest = DE_REG_A; decode_flags_mask = 4'hf; end
        OP_SUB:  begin decode_alu_op = ALU_SUB; decode_oper2 = op_reg8; decode_dest = DE_REG_A; decode_flags_mask = 4'hf; end
        OP_OR:   begin decode_alu_op = ALU_OR;  decode_oper2 = op_reg8; decode_dest = DE_REG_A; end
        OP_AND:  begin decode_alu_op = ALU_AND; decode_oper2 = op_reg8; decode_dest = DE_REG_A; end
        OP_XOR:  begin decode_alu_op = ALU_XOR; decode_oper2 = op_reg8; decode_dest = DE_REG_A; end
        OP_INC:  begin decode_alu_op = ALU_ADD; decode_oper1 = op_reg8; decode_oper2 = DE_CONST; decode_dest = op_reg8; decode_flags_mask = 4'hf; end
        OP_DEC:  begin decode_alu_op = ALU_SUB; decode_oper1 = op_reg8; decode_oper2 = DE_CONST; decode_dest = op_reg8; decode_flags_mask = 4'hf; end
        OP_JR:   begin decode_alu_op = ALU_ADD; decode_oper1 = DE_MEM; decode_oper2 = DE_PC; decode_dest = DE_PC; end
        OP_JRCC: begin decode_alu_op = ALU_ADD; decode_oper1 = DE_MEM; decode_oper2 = DE_PC; decode_dest = op_cond ? DE_PC : DE_NONE; end
        OP_INC16: begin decode_alu_op = ALU_ADD; decode_oper1 = op_reg16; decode_oper2 = DE_CONST; decode_dest = op_reg16; end
        OP_DEC16: begin decode_alu_op = ALU_ADD; decode_oper1 = op_reg16; decode_oper2 = DE_CONST; decode_dest = op_reg16; end
        OP_ADD16: begin decode_alu_op = ALU_ADD; decode_oper1 = op_reg16; decode_oper2 = DE_CONST; decode_dest = op_reg16; end
        OP_JP:    begin decode_oper1 = DE_MEM16; decode_dest = DE_PC; end
        OP_JPCC:  begin decode_oper1 = DE_MEM16; decode_dest = op_cond ? DE_PC : DE_NONE; end
        OP_LDI16: begin decode_dest = op_reg16; decode_oper1 = DE_MEM16; end
        OP_LD16:  begin decode_dest = op_reg16; decode_oper1 = DE_MEM16; decode_load_mem16 = 1; end
        OP_LDHLI: begin decode_dest = op_reg8; decode_oper1 = DE_REG_HL; decode_load_mem8 = 1; decode_HL_op = HL_OP_INC; end
        default: decode_instruction_not_implemented = 1;
    endcase
    decode_instr_length = decode_oper1 == DE_MEM16 ? 3 : (
                          decode_oper1 == DE_MEM ? 2 : 1);
end

function [4:0] decode_operand_reg8(input [2:0] operand_bits);
    case (operand_bits)
        OPARG_REG_A: decode_operand_reg8 = DE_REG_A;
        OPARG_REG_B: decode_operand_reg8 = DE_REG_B;
        OPARG_REG_C: decode_operand_reg8 = DE_REG_C;
        OPARG_REG_D: decode_operand_reg8 = DE_REG_D;
        OPARG_REG_E: decode_operand_reg8 = DE_REG_E;
        OPARG_REG_H: decode_operand_reg8 = DE_REG_H;
        OPARG_REG_L: decode_operand_reg8 = DE_REG_L;
        default:     decode_operand_reg8 = DE_NONE;
    endcase
endfunction

function [4:0] decode_operand_reg16(input [1:0] operand_bits);
    case (operand_bits)
        OPARG_REG_BC: decode_operand_reg16 = DE_REG_BC;
        OPARG_REG_DE: decode_operand_reg16 = DE_REG_DE;
        OPARG_REG_HL: decode_operand_reg16 = DE_REG_HL;
        OPARG_REG_SP: decode_operand_reg16 = DE_SP;
        //OPARG_REG_AF: decode_operand_reg16 = DE_REG_AF;
        default:      decode_operand_reg16 = DE_NONE;
    endcase
endfunction

function decode_operand_cond(input [1:0] operand_bits);
    case (operand_bits)
        OPARG_COND_Z:  decode_operand_cond = Z;
        OPARG_COND_C:  decode_operand_cond = C;
        OPARG_COND_NZ: decode_operand_cond = ~Z;
        OPARG_COND_NC: decode_operand_cond = ~C;
        default:      decode_operand_cond = 1'b0;
    endcase
endfunction

function automatic [15:0] operand_mux(input [4:0] operand, input [15:0] const_value);
    case (operand)
        DE_NONE:   operand_mux = 'hffff;
        DE_CONST:  operand_mux = const_value;
        DE_MEM:    operand_mux = 'hffff; // Overwritten after reading mem.
        DE_MEM16:  operand_mux = 'hffff; // Overwritten after reading mem.
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
 * ALU
 */
always @(*)
    case (alu_op)
        ALU_NOP: begin alu_out = {1'b0, exec_oper1}; end
        ALU_ADD: begin alu_out = {1'b0, exec_oper1} + {1'b0, exec_oper2}; end
        ALU_SUB: begin alu_out = {1'b0, exec_oper1} - {1'b0, exec_oper2}; end
        ALU_OR:  begin alu_out = {1'b0, exec_oper1} | {1'b0, exec_oper2}; end
        ALU_AND: begin alu_out = {1'b0, exec_oper1} & {1'b0, exec_oper2}; end
        ALU_XOR: begin alu_out = {1'b0, exec_oper1} ^ {1'b0, exec_oper2}; end
        default: alu_out = 17'hFFFF;
    endcase
assign alu_out_Z = alu_16bit ? (alu_out[15:0] == 16'h0000) :
                               (alu_out[7:0] == 8'h00);
assign alu_out_N = alu_op == ALU_SUB;
assign alu_out_H = exec_oper1[4] ^ exec_oper2[4] ^ alu_out[4]; // TODO for 16-bit
assign alu_out_C = alu_16bit ? alu_out[16] :
                               (exec_oper1[8] ^ exec_oper2[8] ^ alu_out[8]);


/*
 * Datapath between stages
 */
always @(posedge clk)
    if (reset) begin
        $display("[CPU] Reset");
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
    end else begin
        //$display("[CPU] Begin stage ", next_stage);
        case (next_stage)
        FETCH: begin
            $display("[CPU] Fetch ", pc);
            mem_bus_ctrl <= MEMBUS_PC;
            mem_addr <= pc;
        end

        DECODE: begin
            $display("[CPU] Decode opcode ", decode_opcode);
            if (decode_instruction_not_implemented) begin
                `ifndef SYNTHESIS
                    $display("Opcode not implemented: ", decode_opcode);
                    $finish;
                `endif
                halted <= 1;
            end

            if (decode_halt)
                halted <= 1;

            alu_op <= decode_alu_op;
            alu_16bit <= decode_16bit;
            exec_oper1 <= operand_mux(decode_oper1, decode_oper1_val);
            exec_oper2 <= operand_mux(decode_oper2, decode_oper2_val);

            decode_has_mem_operand <= decode_oper1 == DE_MEM ||
                                      decode_oper1 == DE_MEM16;
            decode_has_mem16_operand <= decode_oper1 == DE_MEM16;
            load_mem <= decode_load_mem8 || decode_load_mem16;
            load_mem16 <= decode_load_mem16;

            wb_dest <= decode_dest;
            wb_pc <= pc + {14'b0, decode_instr_length};
            wb_flags_mask <= decode_flags_mask;
            wb_HL_op <= decode_HL_op;
        end

        DECODE_MEM1: begin
            $display("[CPU] Decode reading operand from ", pc + 1);
            mem_bus_ctrl <= MEMBUS_OPER;
            mem_addr <= pc + 1;
        end
        DECODE_MEM2: begin
            $display("[CPU] Decode read operand ", mem_data_read);
            exec_oper1 <= sext(mem_data_read);
        end
        DECODE_MEM5: begin
            $display("[CPU] Decode reading operand from ", pc + 2);
            mem_bus_ctrl <= MEMBUS_OPER;
            mem_addr <= pc + 2;
        end
        DECODE_MEM6: begin
            $display("[CPU] Decode read operand ", mem_data_read);
            exec_oper1[15:8] <= mem_data_read;
        end

        LOAD_MEM1: begin
            $display("[CPU] Load from ", exec_oper1);
            load_mem_addr <= exec_oper1;
            mem_bus_ctrl <= MEMBUS_LOAD;
            mem_addr <= exec_oper1;
        end
        LOAD_MEM2: begin
            $display("[CPU] Load result ", mem_data_read);
            exec_oper1 <= sext(mem_data_read);
        end
        LOAD_MEM5: begin
            $display("[CPU] Load from ", load_mem_addr + 1);
            mem_bus_ctrl <= MEMBUS_LOAD;
            mem_addr <= load_mem_addr + 1;
        end
        LOAD_MEM6: begin
            $display("[CPU] Load result ", mem_data_read);
            exec_oper1[15:8] <= mem_data_read;
        end

        EXECUTE: begin
            wb_data <= alu_out[15:0];
            wb_flags <= {alu_out_Z, alu_out_N, alu_out_H, alu_out_C};
            $display("[CPU] Execute ALU op ", alu_op, " in1: ", exec_oper1, " in2: ", exec_oper2, " out: ", alu_out[15:0], " F ", alu_out_Z, alu_out_N, alu_out_H, alu_out_C);
        end

        WRITEBACK: begin
            $display("[CPU] WB ", wb_data, " to ", wb_dest);
            case (wb_dest)
                DE_SP:     sp <= wb_data;
                DE_REG_A:  reg_A <= wb_data[7:0];
                DE_REG_B:  reg_B <= wb_data[7:0];
                DE_REG_C:  reg_C <= wb_data[7:0];
                DE_REG_D:  reg_D <= wb_data[7:0];
                DE_REG_E:  reg_E <= wb_data[7:0];
                DE_REG_H:  reg_H <= wb_data[7:0];
                DE_REG_L:  reg_L <= wb_data[7:0];
                DE_REG_BC: {reg_B, reg_C} <= wb_data;
                DE_REG_DE: {reg_D, reg_E} <= wb_data;
                DE_REG_HL: {reg_H, reg_L} <= wb_data;
            endcase

            pc <= wb_dest == DE_PC ? wb_data : wb_pc;
            {Z, N, H, C} <= (reg_Fh & ~wb_flags_mask) | (wb_flags & wb_flags_mask);

            case (wb_HL_op)
                HL_OP_INC: {reg_H, reg_L} <= {reg_H, reg_L} + 16'h0001;
                HL_OP_DEC: {reg_H, reg_L} <= {reg_H, reg_L} - 16'h0001;
            endcase

        end
        endcase // next_stage

        stage <= next_stage;
    end
endmodule
