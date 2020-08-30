/*
 * External cartridge containing the game's code/data (in ROM) and optionally
 * (battery backed) external RAM and/or a real-time clock.
 *
 * 0000-3FFF ROM bank 0
 * 4000-7FFF ROM bank n
 * A000-BFFF EXTRAM/RTC
 */

/* verilator lint_off UNUSED */
module cart (
    input clk,
    input [15:0] addr,
    output reg [7:0] data_r,
    input [7:0] data_w,
    input write_enable,
    output data_active
);
/* verilator lint_on UNUSED */

assign data_active = !write_enable && (
    (addr < 'h8000) ||
    (addr >= 'ha000 && addr < 'hc000));

parameter rom_size = 'h3000;

reg [7:0] rom [rom_size-1:0];

initial begin
    $readmemh("roms/build/obj.hex", rom);
end

always @(posedge clk)
    data_r <= rom[addr];

endmodule
