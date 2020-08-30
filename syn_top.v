`include "pll.v"
`include "main.v"
`include "tft.v"
`include "cart.v"
`include "spram.v"

module syn_top (
    input device_clk,
    output LEDR_N, LEDG_N,
    output LED1, output LED2, output LED3, output LED4, output LED5,
    output P1A1, output P1A2, output P1A3, output P1A4, output P1A7, output P1A8, output P1A9, output P1A10,
    output P1B1, output P1B2, output P1B3, output P1B4, output P1B7, output P1B8, output P1B9, output P1B10,
);

wire pll_locked;
wire clk_16mhz, clk_8mhz, clk_4mhz;

wire reset;
reg [3:0] reset_cnt;

wire btn_a, btn_b, btn_start, btn_select;
wire btn_up, btn_down, btn_left, btn_right;

wire [15:0] extbus_addr;
wire [7:0] extbus_data_w, extbus_data_r;
wire extbus_do_write;

wire [15:0] vram_addr;
wire [7:0] vram_data_w, vram_data_r;
wire vram_do_write;
wire vram_data_active;

wire [7:0] cart_data_r;
wire cart_data_active;
wire [7:0] wram_data_r;
wire wram_data_active;

wire lcd_hblank, lcd_vblank;
wire lcd_write;
wire [1:0] lcd_col;
wire [7:0] lcd_x, lcd_y;

wire tft_initialized;
wire tft_rst, tft_cs, tft_rs, tft_wr, tft_rd;
wire [7:0] tft_data;

wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
wire [7:0] dbg_last_opcode;
wire [5:0] dbg_stage;
reg dbg_instruction_retired;
wire dbg_halted;

pll pll(device_clk, clk_16mhz, pll_locked);

tft tft (
    clk_16mhz,
    reset,
    tft_initialized,

    tft_rst,
    tft_cs,
    tft_rs,
    tft_wr,
    tft_rd,
    tft_data,

    lcd_vblank,
    lcd_write,
    lcd_col
);

main main(
    clk_4mhz,
    reset | ~tft_initialized,

    btn_a,
    btn_b,
    btn_start,
    btn_select,
    btn_up,
    btn_down,
    btn_left,
    btn_right,

    extbus_addr,
    extbus_data_w,
    extbus_data_r,
    extbus_do_write,

    vram_addr,
    vram_data_w,
    vram_data_r,
    vram_do_write,

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

localparam VRAM_BASE = 'h8000, VRAM_SIZE = 'h2000;
localparam WRAM_BASE = 'hC000, WRAM_SIZE = 'h2000;

cart cart (clk_4mhz, extbus_addr, cart_data_r, extbus_data_w, extbus_do_write, cart_data_active);

spram #(.base(WRAM_BASE), .size(WRAM_SIZE), .addrbits(13))
    wram (clk_4mhz, extbus_addr, wram_data_r, extbus_data_w, extbus_do_write, wram_data_active);
spram #(.base(VRAM_BASE), .size(VRAM_SIZE), .addrbits(13))
    vram (clk_4mhz, vram_addr, vram_data_r, vram_data_w, vram_do_write, vram_data_active);

assign extbus_data_r = cart_data_active ? cart_data_r :
                       wram_data_active ? wram_data_r :
                                          'haa;
/*
assign extbus_data_r = 'haa;
assign vram_data_r = 'haa;
*/

/* Hold reset line high on power-on for few clocks. */
initial reset_cnt = 0;
always @(posedge clk_4mhz)
    if (pll_locked && !&reset_cnt)
        reset_cnt <= reset_cnt + 1;
assign reset = !&reset_cnt;

/* Generate system clock signals. */
reg clk_16mhz_cnt;
reg clk_8mhz_cnt;
always @(posedge clk_16mhz) clk_16mhz_cnt <= clk_16mhz_cnt + 1;
always @(posedge clk_8mhz) clk_8mhz_cnt <= clk_8mhz_cnt + 1;
assign clk_8mhz = clk_16mhz_cnt;
assign clk_4mhz = clk_8mhz_cnt;

assign btn_a = 0;
assign btn_b = 0;
assign btn_start = 0;
assign btn_select = 0;
assign btn_up = 0;
assign btn_down = 0;
assign btn_left = 0;
assign btn_right = 0;

/* I/O pins. */
assign { P1A1, P1A2, P1A3, P1A4, P1A7, P1A8, P1A9, P1A10 } =
    { tft_cs, tft_rs, tft_wr, tft_rd, tft_rst, 1'b0, 1'b0, 1'b0 };
assign { P1B1, P1B2, P1B3, P1B4, P1B7, P1B8, P1B9, P1B10 } =
    { tft_data[0], tft_data[1], tft_data[2], tft_data[3],
      tft_data[4], tft_data[5], tft_data[6], tft_data[7] };

/* Debug output. */
assign {LED5, LED4, LED3, LED2, LED1} = dbg_pc[4:0];
assign LEDR_N = ~dbg_halted;
assign LEDG_N = reset;

endmodule
