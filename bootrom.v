/*
 * On-chip read-only memory area.
 */

module bootrom (
    input clk,
    input enabled,
    input [15:0] addr,
    output reg [7:0] data,
    output data_active
);

parameter size = 'h100;
//parameter contents_file = "build/bootrom.hex";
parameter contents_file = "dmg_boot.hex";

reg [7:0] mem [size-1:0];

initial begin
    $readmemh(contents_file, mem);
end

assign data_active = enabled && addr < size;

always @(negedge clk)
    data <= mem[addr[7:0]];

endmodule
