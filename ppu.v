module ppu (
    input clk,
    input reset,

    input [15:0] mem_addr,
    input [7:0] mem_data_write,
    output [7:0] mem_data_read,
    input mem_do_write,
    output mem_data_active
);

localparam VRAM_BASE = 'h8000, VRAM_SIZE = 'h2000;
localparam  OAM_BASE = 'hFE00,  OAM_SIZE = 'hA0;
localparam IO_START = 'hFF40, IO_END = 'hFF4B;

localparam REG_LCDC = 'hff40,
           REG_STAT = 'hff41,
           REG_SCY  = 'hff42,
           REG_SCX  = 'hff43,
           REG_LY   = 'hff44,
           REG_LYC  = 'hff45,
           REG_DMA  = 'hff46,
           REG_BGP  = 'hff47,
           REG_OBP0 = 'hff48,
           REG_OBP1 = 'hff49,
           REG_WX   = 'hff4a,
           REG_WY   = 'hff4b;

wire [15:0] vram_addr;
wire [7:0] vram_data_w, vram_data_r;
wire vram_do_write;
wire vram_data_active;

reg [8:0] cur_x;
reg [7:0] cur_y;                // LY
reg [7:0] control;              // LCDC
reg [7:0] status;               // STAT
reg [7:0] y_compare;            // LYC
reg [7:0] bg_x, bg_y;           // SCX, SCY
reg [7:0] win_x, win_y;         // SCX, SCY
reg [7:0] bg_pal;               // BGP
reg [7:0] obj_pal0, obj_pal1;   // OBP0, OBP1

wire do_reset_y;

reg [7:0] oam [OAM_SIZE-1:0];

ram #(.base(VRAM_BASE), .size(VRAM_SIZE), .addrbits(13))
    vram (clk, vram_addr, vram_data_r, vram_data_w, vram_do_write, vram_data_active);

// TODO multiplex these between PPU and CPU
assign vram_addr = mem_addr;
assign vram_data_w = mem_data_write;
assign vram_do_write = mem_do_write;

/* Main PPU logic - scan through pixels on screen. */
always @(posedge clk) begin
    if (reset) begin
        cur_x <= 0;
        cur_y <= 0;
    end else begin
        cur_x <= cur_x == 455 ? 0 : cur_x + 1;
        cur_y <= do_reset_y ? 0 :
            cur_x == 455 ? (cur_y == 153 ? 0 : cur_y + 1) : cur_y;
    end
end

assign do_reset_y = mem_do_write && mem_addr == REG_LY;

assign mem_data_active = !mem_do_write && (
    (mem_addr >= VRAM_BASE && mem_addr < VRAM_BASE + VRAM_SIZE) ||
    (mem_addr >= OAM_BASE && mem_addr < OAM_BASE + OAM_SIZE) ||
    (mem_addr >= IO_START && mem_addr <= IO_END));

/* Handle reads from VRAM/OAM/PPU I/O ports */
function [7:0] read(input [15:0] addr);
    read = 'hff;
    if (vram_data_active)
        read = vram_data_r;
    else if (addr >= OAM_BASE && addr < OAM_BASE + OAM_SIZE)
        read = oam[addr - OAM_BASE];
    else if (addr >= IO_START && addr <= IO_END)
        case (addr)
            REG_LCDC: read = control;
            REG_STAT: read = status;
            REG_SCY:  read = bg_y;
            REG_SCX:  read = bg_x;
            REG_LY:   read = cur_y;
            REG_LYC:  read = y_compare;
            //REG_DMA: not readable
            REG_BGP:  read = bg_pal;
            REG_OBP0: read = obj_pal0;
            REG_OBP1: read = obj_pal1;
            REG_WY:   read = win_y;
            REG_WX:   read = win_x;
        endcase
endfunction
assign mem_data_read = read(mem_addr);

/* Handle writes to VRAM/OAM/PPU I/O ports and resets */
always @(posedge clk)
    if (reset) begin
        control <= 0;
        status <= 0;
        y_compare <= 0;
        bg_x <= 0;
        bg_y <= 0;
        win_x <= 0;
        win_y <= 0;
        bg_pal <= 0;
        obj_pal0 <= 0;
        obj_pal1 <= 0;
    end else if (mem_do_write) begin
        if (mem_addr >= OAM_BASE && mem_addr < OAM_BASE + OAM_SIZE)
            oam[mem_addr - OAM_BASE] <= mem_data_write;
        else if (mem_addr > IO_START && mem_addr <= IO_END) begin
            case (mem_addr)
                REG_LCDC: control <= mem_data_write;
                REG_STAT: status <= mem_data_write;
                REG_SCY:  bg_y <= mem_data_write;
                REG_SCX:  bg_x <= mem_data_write;
                //REG_LY: reset handled above
                REG_LYC:  y_compare <= mem_data_write;
                `ifdef DEBUG
                REG_DMA: begin $display("DMA not implemented"); $finish; end
                `endif
                REG_BGP:  bg_pal <= mem_data_write;
                REG_OBP0: obj_pal0 <= mem_data_write;
                REG_OBP1: obj_pal1 <= mem_data_write;
                REG_WY:   win_y <= mem_data_write;
                REG_WX:   win_x <= mem_data_write;
            endcase
        end
    end

endmodule
