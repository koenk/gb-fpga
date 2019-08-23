module ioports (
    input clk,
    input [15:0] addr,
    output [7:0] data_r,
    input [7:0] data_w,
    input write_enable
);

reg [7:0] lcd_LCDC = 'h91; // FF40

function [7:0] port_read(input [7:0] port_addr);
    case (port_addr)
        'h40: port_read = lcd_LCDC;
        default: port_read = 'hff;
    endcase
endfunction

assign data_r = port_read(addr[7:0]);

always @(posedge clk) begin
    if (addr > 'hFF00 && addr < 'hFF80) begin
        if (write_enable)
            case (addr[7:0])
                'h40: lcd_LCDC <= data_w;
            endcase
    end
end

endmodule
