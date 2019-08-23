/*
 * On-chip read-only memory area.
 */

module bootrom (
    input clk,
    input [7:0] addr,
    output reg [7:0] data
);

parameter size = 'h100;
parameter contents_file = "build/bootrom.hex";

reg [7:0] mem [size-1:0];

initial begin
    $readmemh(contents_file, mem);
end

always @(negedge clk)
    data <= mem[addr];

endmodule
