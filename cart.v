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


parameter bank_size = 'h4000;

reg [7:0] bank0 [bank_size-1:0];

initial begin
    $readmemh(`"`ROMFILE`", bank0);
end


always @(negedge clk)
    if (addr < bank_size)
        data_r <= bank0[addr[13:0]];
    else
        data_r <= 'haa;


assign data_active = !write_enable && (
    (addr < 'h8000) ||
    (addr >= 'ha000 && addr < 'hbfff));

endmodule
