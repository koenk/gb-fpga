/*
 * Top module for running simulations with Icarus (iverilog)
 */

`include "main.v"

module icarus_top ();
    reg clk=0;
    always #5 clk = ~clk;  // Create clock with period=10

    initial begin
        $dumpfile("icarus.vcd");
        $dumpvars(0, icarus_top);
    end

    wire lcd_hblank, lcd_vblank;
    wire lcd_write;
    wire [1:0] lcd_col;
    wire [7:0] lcd_x, lcd_y;

    wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
    wire [7:0] dbg_last_opcode;
    wire [5:0] dbg_stage;
    wire dbg_instruction_retired;
    wire dbg_halted;

    main main(
        clk,

        lcd_hblank,
        lcd_vblank,
        lcd_write,
        lcd_col,
        lcd_x,
        lcd_y,

        dbg_pc,
        dbg_sp,
        dbg_AF,
        dbg_BC,
        dbg_DE,
        dbg_HL,
        dbg_instruction_retired,
        dbg_halted,
        dbg_last_opcode,
        dbg_stage
    );

    `ifdef DEBUG
    always @(posedge dbg_instruction_retired) begin
        $display(" PC   SP   AF   BC   DE   HL  ZNHC\n%04x %04x %04x %04x %04x %04x %d%d%d%d\n\n",
                 dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL,
                 dbg_AF[7], dbg_AF[6], dbg_AF[5], dbg_AF[4]);
        if (dbg_halted)
            $finish;
    end
    `endif

endmodule
