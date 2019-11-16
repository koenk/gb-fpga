module ppu (
    input clk,
    input reset,

    input [15:0] mem_addr,
    input [7:0] mem_data_write,
    output [7:0] mem_data_read,
    input mem_do_write,
    output mem_data_active,

    output reg intreq_vblank,
    output reg intreq_stat,

    output reg lcd_hblank,
    output reg lcd_vblank,
    output reg lcd_write,
    output reg [1:0] lcd_col,
    output reg [7:0] lcd_x,
    output reg [7:0] lcd_y
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

localparam OAM_CYCLES = 80, // Per line, for scanning 40 sprites
           PIX_X = 160, // Visible area (one clk per pixel)
           PIX_Y = 144,
           CYCLES_X = 456, // Total scanning area (OAM + pix + hblank)
           CYCLES_Y = 154; //   (pix + vblank)

localparam MODE_HBLANK = 'b00,
           MODE_VBLANK = 'b01,
           MODE_OAM    = 'b10,
           MODE_PIX    = 'b11;

wire [15:0] vram_addr;
wire [7:0] vram_data_w, vram_data_r;
wire vram_do_write;
/* verilator lint_off UNUSED */
wire vram_data_active;
/* verilator lint_on UNUSED */

reg [8:0] cur_x_clk;            // 0..455 (OAM -> transfer -> hblank)
reg [7:0] cur_x_px;             // 0..159
reg [7:0] cur_y;                // LY
reg [7:0] y_compare;            // LYC
reg [7:0] bg_x, bg_y;           // SCX, SCY
reg [7:0] win_x, win_y;         // WX, WY
reg [7:0] bg_pal;               // BGP
reg [7:0] obj_pal0, obj_pal1;   // OBP0, OBP1

wire [8:0] next_x_clk;
wire [7:0] next_y;

// LCDC
reg display_enabled;
reg win_tilemap_select;
reg win_enabled;
reg bgwin_tiledata_select;
reg bg_tilemap_select;
reg obj_size_select;
reg obj_enabled;
reg bg_enabled;

wire [15:0] bg_tilemap_addr;
wire [15:0] bgwin_tiledata_addr;
/* verilator lint_off UNUSED */
wire [15:0] win_tilemap_addr;
wire [7:0] obj_height;
/* verilator lint_on UNUSED */

assign win_tilemap_addr    = win_tilemap_select    ? 16'h9c00 : 16'h9800;
assign bg_tilemap_addr     = bg_tilemap_select     ? 16'h9c00 : 16'h9800;
assign bgwin_tiledata_addr = bgwin_tiledata_select ? 16'h8000 : 16'h9000;
assign obj_height = obj_size_select ? 16 : 8;

// STAT
reg int_y_coincidence;
reg int_oam;
reg int_vblank;
reg int_hblank;
wire y_coincidence;
wire [1:0] mode;

assign y_coincidence = cur_y == y_compare;
assign mode = cur_y >= PIX_Y ? MODE_VBLANK :
              cur_x_clk < OAM_CYCLES ? MODE_OAM :
              cur_x_px < PIX_X ? MODE_PIX : MODE_HBLANK;

wire do_reset_y;

wire pixfetch_active;
reg [15:0] pixfetch_addr;
reg [7:0] pixfetch_tileidx;
reg [7:0] pixfetch_tiledata1, pixfetch_tiledata2;
reg pixfetch_done;
reg [4:0] pixfetch_bg_tile_x;
wire [4:0] pixfetch_bg_tile_x_next;
wire [4:0] pixfetch_bg_tile_y;
wire [15:0] pixfetch_bg_tile_xy, pixfetch_bg_tile_xy_next;

reg pixfifo_pushed;
reg pixfifo_abort;
reg pixfifo_start;
reg [15:0] pixfifo1, pixfifo2;
reg [4:0] pixfifo_size;
reg [2:0] pixfifo_discard_cnt;

reg [7:0] oam [OAM_SIZE-1:0];

ram #(.base(VRAM_BASE), .size(VRAM_SIZE), .addrbits(13))
    vram (clk, vram_addr, vram_data_r, vram_data_w, vram_do_write, vram_data_active);

assign vram_addr = pixfetch_active ? pixfetch_addr : mem_addr;
assign vram_data_w = pixfetch_active ? 0 : mem_data_write;
assign vram_do_write = pixfetch_active ? 0 : mem_do_write;

assign next_x_clk = cur_x_clk == CYCLES_X - 1 ? 0 : cur_x_clk + 1;
assign next_y = do_reset_y ? 0 :
            cur_x_clk < CYCLES_X - 1 ? cur_y :
            cur_y == CYCLES_Y - 1 ? 0 : cur_y + 1;

assign pixfetch_active = pixfetch_stage != PF_STOPPED;

// 8x8 pixels per tile, 32x32 titles total
wire [7:0] pixfetch_bg_y = cur_y + bg_y;
assign pixfetch_bg_tile_y = pixfetch_bg_y[7:3];
assign pixfetch_bg_tile_xy = {6'b0, pixfetch_bg_tile_y, pixfetch_bg_tile_x};
assign pixfetch_bg_tile_x_next = pixfetch_bg_tile_x + 1;
assign pixfetch_bg_tile_xy_next = {6'b0, pixfetch_bg_tile_y, pixfetch_bg_tile_x_next};

/* Primary timing for display. */
always @(posedge clk) begin
    if (reset) begin
        cur_x_clk <= 0;
        cur_y <= 0;
    end else if (display_enabled) begin
        cur_x_clk <= next_x_clk;
        cur_y <= next_y;
    end
end

/* Pixel pipeline fetcher stages. */
localparam PF_STOPPED    = 0,
           PF_START      = 1,
           PF_WAIT_BGMAP = 2,
           PF_READ_BGMAP = 3,
           PF_WAIT_TILE1 = 4,
           PF_READ_TILE1 = 5,
           PF_WAIT_TILE2 = 6,
           PF_READ_TILE2 = 7,
           PF_WAIT_FIFO  = 8;
reg [3:0] pixfetch_stage, pixfetch_stage_next;

/* Pixel fifo fetcher. */
always @(*)
    if (reset)
        pixfetch_stage_next = PF_STOPPED;
    else if (!display_enabled)
        pixfetch_stage_next = pixfetch_stage;
    else if (pixfifo_abort)
        pixfetch_stage_next = PF_STOPPED;
    else case (pixfetch_stage)
        PF_STOPPED:
            pixfetch_stage_next = pixfifo_start ? PF_START : PF_STOPPED;
        PF_START,
        PF_WAIT_BGMAP, PF_READ_BGMAP,
        PF_WAIT_TILE1, PF_READ_TILE1,
        PF_WAIT_TILE2:
            pixfetch_stage_next = pixfetch_stage + 1;
        PF_READ_TILE2,
        PF_WAIT_FIFO:
            pixfetch_stage_next = pixfifo_pushed ? PF_WAIT_BGMAP : PF_WAIT_FIFO;
        default:
            pixfetch_stage_next = PF_STOPPED;
    endcase
always @(posedge clk) begin
    if (reset) begin
        pixfetch_stage <= PF_STOPPED;
        pixfetch_done <= 0;
        pixfetch_bg_tile_x <= 0;
    end else begin
        pixfetch_stage <= pixfetch_stage_next;
        case (pixfetch_stage_next)
            PF_STOPPED: begin
                pixfetch_done <= 0;
                pixfetch_bg_tile_x <= bg_x[7:3];
            end
            PF_WAIT_BGMAP:
                pixfetch_done <= 0;
            PF_START: begin
                `ifdef DEBUG_PPU_FETCH
                    $display("[PPU] Fetching tile %04x + %04x",
                        bg_tilemap_addr, pixfetch_bg_tile_xy);
                `endif
                pixfetch_addr <= bg_tilemap_addr + pixfetch_bg_tile_xy;
            end
            PF_READ_BGMAP: begin
                `ifdef DEBUG_PPU_FETCH
                    $display("[PPU] Fetch got tileidx %02x", vram_data_r);
                    $display("[PPU] Fetching tiledata %04x + %04x",
                        bgwin_tiledata_addr, {8'b0, vram_data_r} << 4);
                `endif
                pixfetch_tileidx <= vram_data_r;
                // TODO this stuff can be signed
                pixfetch_addr <= bgwin_tiledata_addr +
                    {4'b0, vram_data_r, pixfetch_bg_y[2:0], 1'b0};
            end
            PF_READ_TILE1: begin
                `ifdef DEBUG_PPU_FETCH
                    $display("[PPU] Fetch got tiledata1 %02x", vram_data_r);
                    $display("[PPU] Fetching tiledata %04x + %04x", bgwin_tiledata_addr, ({8'b0, pixfetch_tileidx} << 4) + 1);
                `endif
                pixfetch_tiledata1 <= vram_data_r;
                pixfetch_addr <= bgwin_tiledata_addr +
                    {4'b0, pixfetch_tileidx, pixfetch_bg_y[2:0], 1'b1};
            end
            PF_READ_TILE2: begin
                `ifdef DEBUG_PPU_FETCH
                    $display("[PPU] Fetch got tiledata2 %02x", vram_data_r);
                    $display("[PPU] Fetcher completed fetch, starting new fetch from %04x", pixfetch_bg_tile_xy_next);
                `endif
                pixfetch_tiledata2 <= vram_data_r;
                pixfetch_done <= 1;
                pixfetch_bg_tile_x <= pixfetch_bg_tile_x + 1; // TODO what if we get aborted here
                pixfetch_addr <= bg_tilemap_addr + pixfetch_bg_tile_xy_next; // TODO also maybe do this later?
            end
        endcase
    end
end

/* Push pixels to screen from fifo. */
always @(posedge clk) begin
    pixfifo_abort <= 0;
    pixfifo_start <= 0;
    pixfifo_pushed <= 0;
    lcd_write <= 0;
    lcd_hblank <= 0;
    lcd_vblank <= 0;

    if (reset) begin
        cur_x_px <= PIX_X; // Pause until end of OAM cycle
        pixfifo_size <= 0;
        pixfifo1 <= 0;
        pixfifo2 <= 0;
    end else if (!display_enabled) begin
    end else if (cur_y >= PIX_Y) begin
        lcd_vblank <= 1;
    end else if (cur_x_clk == OAM_CYCLES) begin
        `ifdef DEBUG_PPU_FIFO
            $display("[PPU] Starting line %d", cur_y);
        `endif
        pixfifo_discard_cnt <= bg_x[2:0];
        cur_x_px <= 0;
        pixfifo_start <= 1;
    end else if (cur_x_px == PIX_X) begin
        pixfifo_abort <= 1;
        pixfifo_size <= 0;
        lcd_hblank <= 1;
    end else if (pixfifo_size == 0 && pixfetch_done && !pixfifo_pushed) begin
        `ifdef DEBUG_PPU_FIFO
            $display("[PPU] First fetch push row %d: %02x %02x", cur_y,
                pixfetch_tiledata1, pixfetch_tiledata2);
        `endif
        pixfifo_size <= 8;
        pixfifo1 <= {pixfetch_tiledata1, 8'b0};
        pixfifo2 <= {pixfetch_tiledata2, 8'b0};
        pixfifo_pushed <= 1;
    end else if (pixfifo_size == 8 && pixfetch_done && !pixfifo_pushed) begin
        `ifdef DEBUG_PPU_FIFO
            $display("[PPU] Second fetch push row %d: %02x, %02x", cur_y,
                pixfetch_tiledata1, pixfetch_tiledata2);
        `endif
        pixfifo_size <= 16;
        pixfifo1 <= {pixfifo1[15:8], pixfetch_tiledata1};
        pixfifo2 <= {pixfifo2[15:8], pixfetch_tiledata2};
        pixfifo_pushed <= 1;
    end else if (pixfifo_size > 8) begin
        `ifdef DEBUG_PPU_FIFO
            $display("[PPU] Push pixel to %d %d, sz=%d", cur_x_px, cur_y,
                pixfifo_size);
        `endif
        case ({pixfifo2[15], pixfifo1[15]})
            2'b11: lcd_col <= bg_pal[7:6];
            2'b10: lcd_col <= bg_pal[5:4];
            2'b01: lcd_col <= bg_pal[3:2];
            2'b00: lcd_col <= bg_pal[1:0];
        endcase

        lcd_x <= cur_x_px;
        lcd_y <= cur_y;

        if (|pixfifo_discard_cnt)
            pixfifo_discard_cnt <= pixfifo_discard_cnt - 1;
        else begin
            lcd_write <= 1;
            cur_x_px <= cur_x_px + 1;
        end

        if (pixfifo_size - 1 == 8 && pixfetch_done) begin
            `ifdef DEBUG_PPU_FIFO
                $display("[PPU] Fetch push during pixel push");
            `endif
            // Push fetched data into fifo
            pixfifo_size <= 16;
            pixfifo1 <= {pixfifo1[14:7], pixfetch_tiledata1};
            pixfifo2 <= {pixfifo2[14:7], pixfetch_tiledata2};
            pixfifo_pushed <= 1;
        end else begin
            pixfifo_size <= pixfifo_size - 1;
            pixfifo1 <= {pixfifo1[14:0], 1'b0};
            pixfifo2 <= {pixfifo2[14:0], 1'b0};
        end
    end
end

/* Request interrupts on vblank and LY=LYC */
always @(posedge clk) begin
    intreq_vblank <= 0;
    intreq_stat <= 0;

    if (!reset) begin
        if (next_y != cur_y && next_y == PIX_Y)
            intreq_vblank <= 1;
    end
end


assign do_reset_y = mem_do_write && mem_addr == REG_LY;

assign mem_data_active = !mem_do_write && (
    (mem_addr >= VRAM_BASE && mem_addr < VRAM_BASE + VRAM_SIZE) ||
    (mem_addr >= OAM_BASE && mem_addr < OAM_BASE + OAM_SIZE) ||
    (mem_addr >= IO_START && mem_addr <= IO_END));


/* Handle reads from VRAM/OAM/PPU I/O ports */
function [7:0] read(input [15:0] addr);
    if (addr >= VRAM_BASE && addr < VRAM_BASE + VRAM_SIZE)
        read = pixfetch_active ? 'hff : vram_data_r;
    else if (addr >= OAM_BASE && addr < OAM_BASE + OAM_SIZE)
        read = oam[addr - OAM_BASE];
    else if (addr >= IO_START && addr <= IO_END)
        case (addr)
            REG_LCDC: read = {display_enabled, win_tilemap_select, win_enabled,
                              bgwin_tiledata_select, bg_tilemap_select,
                              obj_size_select, obj_enabled, bg_enabled};
            REG_STAT: read = {1'b0, int_y_coincidence, int_oam, int_vblank,
                              int_hblank, y_coincidence, mode};
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
            default:  read = 'hff;
        endcase
    else
        read = 'hff;
endfunction
assign mem_data_read = read(mem_addr);


/* Handle writes to VRAM/OAM/PPU I/O ports and resets */
always @(posedge clk)
    if (reset) begin
        display_enabled <= 0;
        win_tilemap_select <= 0;
        win_enabled <= 0;
        bgwin_tiledata_select <= 0;
        bg_tilemap_select <= 0;
        obj_size_select <= 0;
        obj_enabled <= 0;
        bg_enabled <= 0;
        int_y_coincidence <= 0;
        int_oam <= 0;
        int_vblank <= 0;
        int_hblank <= 0;
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
        else if (mem_addr >= IO_START && mem_addr <= IO_END) begin
            `ifdef DEBUG_PPU
                $display("[PPU] IO Write %04x, val=%02x", mem_addr, mem_data_write);
            `endif
            case (mem_addr)
                REG_LCDC: {display_enabled, win_tilemap_select, win_enabled,
                           bgwin_tiledata_select, bg_tilemap_select,
                           obj_size_select, obj_enabled, bg_enabled}
                            <= mem_data_write;
                REG_STAT: {int_y_coincidence, int_oam, int_vblank, int_hblank}
                            <= mem_data_write[6:3];
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
