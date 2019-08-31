`include "cpu.v"
`include "ram.v"
`include "lram.v"
`include "bootrom.v"
`include "cart.v"
`include "ppu.v"

module main (
    input clk,

    output [15:0] dbg_pc,
    output [15:0] dbg_sp,
    output [15:0] dbg_AF,
    output [15:0] dbg_BC,
    output [15:0] dbg_DE,
    output [15:0] dbg_HL,
    output dbg_instruction_retired,
    output dbg_halted,
    output [7:0] dbg_last_opcode,
    output [5:0] dbg_stage
);


wire cpu_do_write;
wire [15:0] cpu_addr;
reg [7:0] cpu_data_r;
wire [7:0] cpu_data_w;

wire [7:0] bootrom_data_r;
wire [7:0] cart_data_r;
wire [7:0] ppu_data_r;
wire [7:0] wram_data_r;
wire [7:0] hram_data_r;

wire bootrom_data_active;
wire cart_data_active;
wire wram_data_active;
wire hram_data_active;
wire ppu_data_active;

reg bootrom_enabled;

reg interrupt_enable;

reg reset;
reg [7:0] reset_cnt;

initial begin
    reset = 1;
    reset_cnt = 0;
end

/*
 * 0000-0100 BOOTROM (only during boot)
 * 0000-3FFF ROM bank 0
 * 4000-7FFF ROM bank n
 * 8000-9FFF VRAM
 * A000-BFFF EXTRAM/RTC
 * C000-DFFF WRAM
 * E000-FDFF ECHO (same as C000-DDFF)
 * FE00-FE9F OAM
 * FEA0-FEFF -unusable-
 * FF00-FF7F I/O ports
 * FF80-FFFE HRAM
 * FFFF      Interrupt enable
 */
localparam                  BOOTROM_SIZE = 'h100;
localparam WRAM_BASE = 'hC000, WRAM_SIZE = 'h2000;
localparam HRAM_BASE = 'hFF80, HRAM_SIZE = 'h7F;

bootrom bootrom (clk, bootrom_enabled, cpu_addr, bootrom_data_r, bootrom_data_active);
cart cart (clk, cpu_addr, cart_data_r, cpu_data_w, cpu_do_write, cart_data_active);
ram #(.base(WRAM_BASE), .size(WRAM_SIZE), .addrbits(13))
    wram (clk, cpu_addr, wram_data_r, cpu_data_w, cpu_do_write, wram_data_active);
lram #(.base(HRAM_BASE), .size(HRAM_SIZE), .addrbits(7))
    hram (clk, cpu_addr, hram_data_r, cpu_data_w, cpu_do_write, hram_data_active);

ppu ppu(clk, reset, cpu_addr, cpu_data_w, ppu_data_r, cpu_do_write, ppu_data_active);

cpu cpu(
    clk,
    reset,

    cpu_addr,
    cpu_data_w,
    cpu_data_r,
    cpu_do_write,

    dbg_halted,

    dbg_pc,
    dbg_sp,
    dbg_AF,
    dbg_BC,
    dbg_DE,
    dbg_HL,
    dbg_instruction_retired,
    dbg_last_opcode,
    dbg_stage
);


/*
 * Hold reset line high for first few cycles.
 */
always @(posedge clk)
    if (reset_cnt == 8'h0f)
        reset <= 0;
    else
        reset_cnt <= reset_cnt + 1;

/* Mux for cpu reading memory. */
always @(*) begin
    if (bootrom_data_active) cpu_data_r = bootrom_data_r;
    else if (cart_data_active) cpu_data_r = cart_data_r;
    else if (wram_data_active) cpu_data_r = wram_data_r;
    else if (hram_data_active) cpu_data_r = hram_data_r;
    else if (ppu_data_active) cpu_data_r = ppu_data_r;
    else if (cpu_addr == 16'hFFFF)
        cpu_data_r = {7'h0, interrupt_enable};
    else
        cpu_data_r = 8'hff;
end

always @(posedge clk) begin
    if (reset) begin
        bootrom_enabled <= 1;
        interrupt_enable <= 0;
    end else begin
        if (cpu_do_write) begin
            if (cpu_addr == 'hFFFF)
                interrupt_enable <= cpu_data_w[0];
        end
   end
end

endmodule
