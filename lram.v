/*
 * Small local memory areas synthesized as latches or EBR depending on size.
 */

module lram (
    input clk,
    input [15:0] abs_addr,
    output reg [7:0] data_r,
    input [7:0] data_w,
    input write_enable,
    output data_active
);

parameter base = 'hFF80;
parameter size = 'h7F;
parameter addrbits = 7;

/* verilator lint_off UNUSED */
wire [15:0] rel_addr;
/* verilator lint_on UNUSED */
wire [addrbits-1:0] addr;

wire enable;

reg [7:0] mem [size-1:0];

`ifndef SYNTHESIS
integer i;
initial begin
    for (i = 0; i < size; i++)
        mem[i] = 8'hff;
end
`endif

assign enable = abs_addr >= base && abs_addr < base + size;

assign rel_addr = abs_addr - base;
assign addr = rel_addr[addrbits-1:0];

assign data_active = enable && !write_enable;

always @(posedge clk) begin
    if (enable && write_enable)
        mem[addr] <= data_w;
end

always @(negedge clk)
    if (enable)
        data_r <= mem[addr];

endmodule
