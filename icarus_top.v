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

    wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
    wire dbg_instruction_retired;
    wire dbg_halted;

    main main(clk, dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL,
        dbg_instruction_retired, dbg_halted);

    always @(posedge dbg_instruction_retired) begin
        $display(" PC   SP   AF   BC   DE   HL   Fl\n%04x %04x %04x %04x %04x %04x %d%d%d%d\n\n",
                 dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL,
                 dbg_AF[7], dbg_AF[6], dbg_AF[5], dbg_AF[4]);
        if (dbg_halted)
            $finish;
    end

endmodule
