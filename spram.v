/*
 * SPRAM of max 16KB in size.
 *
 * Note: SPRAM is actually 32KB, with 16K * 16-bit words. This code ignores the
 * upper byte, but we could cram more data in if needed.
 */

module spram (
    input clk,
    input [15:0] abs_addr,
    output reg [7:0] data_r,
    input [7:0] data_w,
    input write_enable,
    output data_active
);

parameter base = 'hC000;
parameter size = 'h2000;
parameter addrbits = 13;

wire [15:0] rel_addr;
wire [addrbits-1:0] addr;

wire enable;
wire ram_wren;

assign enable = abs_addr >= base && abs_addr < base + size;
assign ram_wren = enable && write_enable;

assign rel_addr = abs_addr - base;
assign addr = rel_addr[addrbits-1:0];

assign data_active = enable && !write_enable;

SB_SPRAM256KA spram
(
    .CLOCK(clk),
    .ADDRESS(addr),
    .DATAIN(data_w),
    .DATAOUT(data_r),
    .WREN(ram_wren),
    .MASKWREN(4'b1111),
    .CHIPSELECT(1'b1),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
);

endmodule
