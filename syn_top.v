`include "main.v"

module syn_top (
    input device_clk,
    output led1, output led2, output led3, output led4, output led5,
    output TR3, output TR4, output TR5, output TR6, output TR7, output TR8, output TR9, output TR10,
    output BR3, output BR4, output BR5, output BR6, output BR7, output BR8, output BR9, output BR10
);

/*
 * Slow down the clock so we can observe what the CPU is doing with LEDs.
 */
wire clk;
reg [15:0] clk_cnt;
always @(posedge device_clk)
    clk_cnt = clk_cnt + 1;
assign clk = clk_cnt[15];

wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
reg dbg_instruction_retired;
wire dbg_halted;

assign {led4, led3, led2, led1} = dbg_BC[11:8];
assign led5 = dbg_halted;

assign {TR10, TR9, TR8, TR7, TR6, TR5, TR4, TR3} = dbg_pc[7:0];
assign {BR10, BR9, BR8, BR7, BR6, BR5, BR4, BR3} = dbg_AF[15:8];

main main(
    clk,

    dbg_pc,
    dbg_sp,
    dbg_AF,
    dbg_BC,
    dbg_DE,
    dbg_HL,
    dbg_instruction_retired,
    dbg_halted
);

endmodule
