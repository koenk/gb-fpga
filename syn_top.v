`include "pll.v"
`include "main.v"

module syn_top (
    input device_clk,
    output LEDR_N, LEDG_N,
    output LED1, output LED2, output LED3, output LED4, output LED5,
    output P1A1, output P1A2, output P1A3, output P1A4, output P1A7, output P1A8, output P1A9, output P1A10,
    output P1B1, output P1B2, output P1B3, output P1B4, output P1B7, output P1B8, output P1B9, output P1B10,
);

wire pll_locked;
wire clk_16mhz, clk_8mhz, clk_4mhz;


pll pll(device_clk, clk_16mhz, pll_locked);


main main(
    clk_4mhz,

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

wire lcd_hblank, lcd_vblank;
wire lcd_write;
wire [1:0] lcd_col;
wire [7:0] lcd_x, lcd_y;

/* Generate system clock signals. */
reg clk_16mhz_cnt;
reg clk_8mhz_cnt;
always @(posedge clk_16mhz) clk_16mhz_cnt <= clk_16mhz_cnt + 1;
always @(posedge clk_8mhz) clk_8mhz_cnt <= clk_8mhz_cnt + 1;
assign clk_8mhz = clk_16mhz_cnt;
assign clk_4mhz = clk_8mhz_cnt;
/*
 * Debug output on pins.
 */
wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
wire [7:0] dbg_last_opcode;
wire [5:0] dbg_stage;
reg dbg_instruction_retired;
wire dbg_halted;

assign {LED5, LED4, LED3, LED2, LED1} = dbg_pc[4:0];
assign LEDR_N = ~dbg_halted;
assign LEDG_N = clk_4mhz;

assign {P1A1, P1A2, P1A3, P1A4, P1A7, P1A8, P1A9, P1A10 } =
    {2'b0, clk_4mhz, lcd_write, lcd_hblank, lcd_vblank, lcd_col};
assign {P1B1, P1B2, P1B3, P1B4, P1B7, P1B8, P1B9, P1B10 } = dbg_pc[7:0];

endmodule
