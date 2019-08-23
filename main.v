`include "cpu.v"
`include "ram.v"
`include "lram.v"
`include "bootrom.v"
`include "ioports.v"
`include "cart.v"

module main (
    input clk,

    output [15:0] dbg_pc,
    output [15:0] dbg_sp,
    output [15:0] dbg_AF,
    output [15:0] dbg_BC,
    output [15:0] dbg_DE,
    output [15:0] dbg_HL,
    output dbg_instruction_retired,
    output dbg_halted
);


wire cpu_do_write;
wire [15:0] cpu_addr;
reg [7:0] cpu_data_r;
wire [7:0] cpu_data_w;

wire [15:0] vram_addr; // For multiplexing between CPU and PPU

wire [7:0] bootrom_data_r;
wire [7:0] cart_data_r;
wire [7:0] io_data_r;
wire [7:0] vram_data_r;
wire [7:0] wram_data_r;
wire [7:0] hram_data_r;
wire [7:0] oam_data_r;

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
localparam VRAM_BASE = 'h8000, VRAM_SIZE = 'h2000;
localparam WRAM_BASE = 'hC000, WRAM_SIZE = 'h2000;
localparam HRAM_BASE = 'hFF80, HRAM_SIZE = 'h7F;
localparam  OAM_BASE = 'hFE00,  OAM_SIZE = 'hA0;

bootrom bootrom (clk, cpu_addr[7:0], bootrom_data_r);
cart cart (clk, cpu_addr, cart_data_r, cpu_data_w, cpu_do_write);
ioports ioports (clk, cpu_addr, io_data_r, cpu_data_w, cpu_do_write);
ram #(.base(VRAM_BASE), .size(VRAM_SIZE), .addrbits(13)) vram (clk, vram_addr, vram_data_r, cpu_data_w, cpu_do_write);
ram #(.base(WRAM_BASE), .size(WRAM_SIZE), .addrbits(13)) wram (clk, cpu_addr, wram_data_r, cpu_data_w, cpu_do_write);
lram #(.base(HRAM_BASE), .size(HRAM_SIZE), .addrbits(7)) hram (clk, cpu_addr, hram_data_r, cpu_data_w, cpu_do_write);
lram #(.base(OAM_BASE),  .size(OAM_SIZE),  .addrbits(8)) oam (clk, cpu_addr, oam_data_r, cpu_data_w, cpu_do_write);

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
    dbg_instruction_retired
);


always @(posedge clk)
    if (reset_cnt == 8'hff)
        reset <= 0;
    else
        reset_cnt <= reset_cnt + 1;

assign vram_addr = cpu_addr; // TODO mux with ppu

/* Mux for cpu reading memory. */
always @(*) begin
    case (cpu_addr[15:12])
        4'h0, 4'h1, 4'h2, 4'h3,
        4'h4, 4'h5, 4'h6, 4'h7: begin
            if (cpu_addr < BOOTROM_SIZE && bootrom_enabled)
                cpu_data_r = bootrom_data_r;
            else
                cpu_data_r = cart_data_r;
        end
        4'h8, 4'h9:
            cpu_data_r = vram_data_r;
        4'hA, 4'hB:
            cpu_data_r = cart_data_r;
        4'hC, 4'hD, 4'hE:
            cpu_data_r = wram_data_r;
        4'hF:
            if (cpu_addr == 16'hFFFF)
                cpu_data_r = {7'h0, interrupt_enable};
            else
                if (cpu_addr[11:9] == 3'b111)
                    case (cpu_addr[8:7])
                        'b00,
                        'b01: cpu_data_r = oam_data_r;
                        'b10: cpu_data_r = io_data_r;
                        'b11: cpu_data_r = hram_data_r;
                    endcase
                else
                    cpu_data_r = wram_data_r;
    endcase
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
