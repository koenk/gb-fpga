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

    wire [7:0] dbg1, dbg2, dbg3, dbg4;
    wire [7:0] dbg_A, dbg_B, dbg_C;
    wire [3:0] dbg_F;
    wire [15:0] dbg_pc;
    wire dbg_instruction_retired;
    wire dbg_halted;

    main main(clk, dbg1, dbg2, dbg3, dbg4, dbg_pc, dbg_F, dbg_A, dbg_B, dbg_C,
        dbg_instruction_retired, dbg_halted);

endmodule
