/*
 * SRAM of ~8-16K in size.
 *
 * TODO: Use external SRAM or on-chip PSRAM instead of implicit EBR.
 */

module ram (
    input clk,
    input [15:0] abs_addr,
    output reg [7:0] data_r,
    input [7:0] data_w,
    input write_enable
);

parameter base = 'hC000;
parameter size = 'h2000;
parameter addrbits = 13;

/* verilator lint_off UNUSED */
wire [15:0] rel_addr;
/* verilator lint_on UNUSED */
wire [addrbits-1:0] addr;

reg [7:0] mem [size-1:0];

`ifndef SYNTHESIS
integer i;
initial begin
    for (i = 0; i < size; i++)
        mem[i] = 8'hff;
end
`endif

assign rel_addr = abs_addr - base;
assign addr = rel_addr[addrbits-1:0];

always @(posedge clk) begin
    if (abs_addr >= base && abs_addr < base + size)
        if (write_enable)
            mem[addr] <= data_w;
end

always @(negedge clk)
    if (abs_addr >= base && abs_addr < base + size)
        data_r <= mem[addr];

endmodule
