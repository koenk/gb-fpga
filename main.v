`include "cpu.v"
`include "ram.v"
`include "lram.v"
`include "bootrom.v"
`include "cart.v"
`include "ppu.v"

module main (
    input clk,
    input reset,

    output lcd_hblank,
    output lcd_vblank,
    output lcd_write,
    output [1:0] lcd_col,
    output [7:0] lcd_x,
    output [7:0] lcd_y,

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

wire intreq_lcd_vblank;
wire intreq_lcd_stat;
wire intreq_timer;
wire intreq_serial;
wire intreq_joypad;

reg [7:0] interrupts_enabled;
reg [4:0] interrupts_request;
wire [4:0] interrupts_ack;

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

ppu ppu(
    clk,
    reset,

    cpu_addr,
    cpu_data_w,
    ppu_data_r,
    cpu_do_write,
    ppu_data_active,

    intreq_lcd_vblank,
    intreq_lcd_stat,

    lcd_hblank,
    lcd_vblank,
    lcd_write,
    lcd_col,
    lcd_x,
    lcd_y
);

cpu cpu(
    clk,
    reset,

    cpu_addr,
    cpu_data_w,
    cpu_data_r,
    cpu_do_write,

    interrupts_enabled[4:0],
    interrupts_request,
    interrupts_ack,

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

assign intreq_timer = 0;
assign intreq_serial = 0;
assign intreq_joypad = 0;


/* Mux for cpu reading memory. */
always @(*) begin
    if (bootrom_data_active) cpu_data_r = bootrom_data_r;
    else if (cart_data_active) cpu_data_r = cart_data_r;
    else if (wram_data_active) cpu_data_r = wram_data_r;
    else if (hram_data_active) cpu_data_r = hram_data_r;
    else if (ppu_data_active) cpu_data_r = ppu_data_r;
    else if (cpu_addr == 16'hFF0F) // Interrupt Flag (IF)
        cpu_data_r = {3'b111, interrupts_request};
    else if (cpu_addr == 16'hFFFF) // Interrupt Enabled (IE)
        cpu_data_r = interrupts_enabled;
    else
        cpu_data_r = 8'hff;
end

always @(posedge clk) begin
    if (reset) begin
        bootrom_enabled <= 1;
        interrupts_enabled <= 8'h0;
        interrupts_request <= 5'h0;
    end else begin

        /* Process interrupt requests (from peripherals) and acknowlegdements
         * (from CPU). Can be overwritten in same cycle by write to FF0F. */
        if (intreq_lcd_vblank)  interrupts_request[0] <= 1;
        if (intreq_lcd_stat)    interrupts_request[1] <= 1;
        if (intreq_timer)       interrupts_request[2] <= 1;
        if (intreq_serial)      interrupts_request[3] <= 1;
        if (intreq_joypad)      interrupts_request[4] <= 1;

        if (interrupts_ack[0])  interrupts_request[0] <= 0;
        if (interrupts_ack[1])  interrupts_request[1] <= 0;
        if (interrupts_ack[2])  interrupts_request[2] <= 0;
        if (interrupts_ack[3])  interrupts_request[3] <= 0;
        if (interrupts_ack[4])  interrupts_request[4] <= 0;

        if (cpu_do_write) begin
            if (cpu_addr == 'hFFFE) // Disable (unmap) bootrom
                bootrom_enabled <= 0;
            else if (cpu_addr == 'hFF0F) // Interrupt Flag (IF)
                interrupts_request <= cpu_data_w[4:0];
            else if (cpu_addr == 'hFFFF) // Interrupt Enabled (IE)
                interrupts_enabled <= cpu_data_w;
        end

   end
end

endmodule
