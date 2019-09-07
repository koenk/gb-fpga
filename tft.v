/*
 * Driver for ILI9341 chip driving a 240x320 RGB display.
 *
 * This module takes the GameBoy's PPU output signals and converts them to
 * IL9341 signals following the 8-bit 8080-I serial parallel interface.
 *
 * The input clock should be 4 times the PPU's clock (i.e., 16 MHz).
 * The module will write data to the ILI9341 at half this speed (i.e., 8 MHz).
 */

module tft(
    input clk,
    input reset,
    output initialized,

    output tft_rst,
    output tft_cs,
    output tft_rs,
    output tft_wr,
    output tft_rd,
    output [7:0] tft_data,

    input lcd_vblank,
    input lcd_write,
    input [1:0] lcd_col
);

    localparam INIT_LEN = 49;
    reg [8:0] INIT_DAT [0:INIT_LEN-1];
    reg [5:0] init_cnt;

    localparam INIT2_LEN = 11;
    reg [8:0] INIT2_DAT [0:INIT2_LEN-1];
    reg [5:0] init2_cnt;

    initial begin
        // Display OFF
        INIT_DAT[0]   = {1'b0, 8'h28};
        // Power control A
        INIT_DAT[1]   = {1'b0, 8'hCB};
         INIT_DAT[2]  = {1'b1, 8'h39};
         INIT_DAT[3]  = {1'b1, 8'h2C};
         INIT_DAT[4]  = {1'b1, 8'h00};
         INIT_DAT[5]  = {1'b1, 8'h34};
         INIT_DAT[6]  = {1'b1, 8'h02};
        // Power control B
        INIT_DAT[7]   = {1'b0, 8'hCF};
         INIT_DAT[8]  = {1'b1, 8'h00};
         INIT_DAT[9]  = {1'b1, 8'hC1};
         INIT_DAT[10] = {1'b1, 8'h30};
        // Driver timing control A
        INIT_DAT[11]  = {1'b0, 8'hE8};
         INIT_DAT[12] = {1'b1, 8'h85};
         INIT_DAT[13] = {1'b1, 8'h00};
         INIT_DAT[14] = {1'b1, 8'h78};
        // Driver timing control B
        INIT_DAT[15]  = {1'b0, 8'hEA};
         INIT_DAT[16] = {1'b1, 8'h00};
         INIT_DAT[17] = {1'b1, 8'h00};
        // Power on sequence control
        INIT_DAT[18]  = {1'b0, 8'hED};
         INIT_DAT[19] = {1'b1, 8'h64};
         INIT_DAT[20] = {1'b1, 8'h03};
         INIT_DAT[21] = {1'b1, 8'h12};
         INIT_DAT[22] = {1'b1, 8'h81};
        // Pump ratio control
        INIT_DAT[23]  = {1'b0, 8'hF7};
         INIT_DAT[24] = {1'b1, 8'h20};
        // Power Control 1: 4.60 V
        INIT_DAT[25]  = {1'b0, 8'hC0};
         INIT_DAT[26] = {1'b1, 8'h23};
        // Power Control 2: AVDD=VCI*2, VGH=VCI*7, VGL=-VCI*4
        INIT_DAT[27]  = {1'b0, 8'hC1};
         INIT_DAT[28] = {1'b1, 8'h10};
        // VCOM Control 1: VMH=4.25V, VML=-1.5V
        INIT_DAT[29]  = {1'b0, 8'hC5};
         INIT_DAT[30] = {1'b1, 8'h3e};
         INIT_DAT[31] = {1'b1, 8'h28};
        // VCOM Control 2: VMH-58, VML-58
        INIT_DAT[32]  = {1'b0, 8'hC7};
         INIT_DAT[33] = {1'b1, 8'h86};
        // Memory Access Control: Flip Y, RGB bit order
        INIT_DAT[34]  = {1'b0, 8'h36};
         INIT_DAT[35] = {1'b1, 8'h88};
        // Pixel format: RGB565 (16 bits / pixel)
        INIT_DAT[36]  = {1'b0, 8'h3A};
         INIT_DAT[37] = {1'b1, 8'h55};
        // Frame Rate: 70 Hz
        INIT_DAT[38]  = {1'b0, 8'hB1};
         INIT_DAT[39] = {1'b1, 8'h00};
         INIT_DAT[40] = {1'b1, 8'h1B};
        // Display Function Control
        INIT_DAT[41]  = {1'b0, 8'hB6};
         INIT_DAT[42] = {1'b1, 8'h08};
         INIT_DAT[43] = {1'b1, 8'h82};
         INIT_DAT[44] = {1'b1, 8'h27};
         INIT_DAT[45] = {1'b1, 8'h00};
        // Exit sleep
        INIT_DAT[46] =  {1'b0, 8'h11};
        // Display ON
        INIT_DAT[47]  = {1'b0, 8'h29};
        // Start memory write (all following data is pixel data)
        INIT_DAT[48]  = {1'b0, 8'h2C};


        // Set column range: 40..199 (160 pix starting at x=40)
        INIT2_DAT[0]  = {1'b0, 8'h2A};
         INIT2_DAT[1] = {1'b1, 8'h00};
         INIT2_DAT[2] = {1'b1, 8'h28};
         INIT2_DAT[3] = {1'b1, 8'h00};
         INIT2_DAT[4] = {1'b1, 8'hc7};
        // Set row range: 40..183 (144 pix starting at y=40)
        INIT2_DAT[5]  = {1'b0, 8'h2B};
         INIT2_DAT[6] = {1'b1, 8'h00};
         INIT2_DAT[7] = {1'b1, 8'h28};
         INIT2_DAT[8] = {1'b1, 8'h00};
         INIT2_DAT[9] = {1'b1, 8'hb7};
        // Start memory write (all following data is pixel data)
        INIT2_DAT[10]  = {1'b0, 8'h2C};
    end

    localparam RESET_START = 0,
               RESET_LO    = 1,
               RESET_WAIT  = 2,
               RESET_INIT  = 3,
               RESET_CLEAR = 4,
               RESET_INIT2 = 5,
               RESET_DONE  = 6;
    localparam RESET_CLKS = 24'd500000; // ~30ms
    reg [2:0] reset_stage;
    reg [23:0] reset_clks;

    reg [17:0] clear_cnt;

    reg write_busy;
    reg [8:0] write_data;
    reg send_pix_lo;

    assign tft_rst = reset_stage != RESET_LO;
    assign tft_cs = 0; // Chip select enable (active low)
    assign tft_rd = 1; // Read disable (active low)
    assign tft_wr = ~write_busy; // Pulse write (active low)
    assign tft_rs = write_data[8]; // Command/Data select
    assign tft_data = write_data[7:0];
    assign initialized = !reset && reset_stage == RESET_DONE &&
                         !&reset_clks && init_cnt == INIT_LEN;

    /* Convert GameBoy 2-bit color to RGB565 color.
     * The following mapping is used:
     *  GB  RGB888  RGB565
     *  00  ffffff   ffff
     *  01  aaaaaa   ad55
     *  10  666666   632c
     *  11  111111   1082
     */
    function [7:0] col_hi(input [1:0] col); // RRRRRGGG bits
        case (col)
            2'b00: col_hi = 8'b11111111;
            2'b01: col_hi = 8'b10101101;
            2'b10: col_hi = 8'b01100011;
            2'b11: col_hi = 8'b00010000;
        endcase
    endfunction
    function [7:0] col_lo(input [1:0] col); // GGGBBBBB bits
        case (col)
            2'b00: col_lo = 8'b11111111;
            2'b01: col_lo = 8'b01010101;
            2'b10: col_lo = 8'b00101100;
            2'b11: col_lo = 8'b10000010;
        endcase
    endfunction

    always @ (posedge clk) begin
        if (reset) begin
            init_cnt <= 0;
            init2_cnt <= 0;
            write_busy <= 0;
            write_data <= 0;
            send_pix_lo <= 0;
            reset_stage <= RESET_START;
            reset_clks <= RESET_CLKS;
            clear_cnt <= 320*240*2;
        end else if (|reset_clks) begin
            reset_clks <= reset_clks - 1;
        end else if (reset_stage == RESET_START ||
                     reset_stage == RESET_LO ||
                     reset_stage == RESET_WAIT ||
                    (reset_stage == RESET_INIT && init_cnt == INIT_LEN) ||
                    (reset_stage == RESET_CLEAR && !|clear_cnt) ||
                    (reset_stage == RESET_INIT2 && init2_cnt == INIT2_LEN)) begin
            reset_stage <= reset_stage + 1;
            reset_clks <= RESET_CLKS;
        end else if (write_busy) begin
            write_busy <= 0;
        end else if (init_cnt < INIT_LEN) begin
            write_data <= INIT_DAT[init_cnt];
            write_busy <= 1;
            init_cnt <= init_cnt + 1;
        end else if (|clear_cnt) begin
            write_data <= {1'b1, 8'b0};
            write_busy <= 1;
            clear_cnt <= clear_cnt - 1;
        end else if (init2_cnt < INIT2_LEN) begin
            write_data <= INIT2_DAT[init2_cnt];
            write_busy <= 1;
            init2_cnt <= init2_cnt + 1;
        end else if (send_pix_lo) begin
            send_pix_lo <= 0;
            write_data <= {1'b1, col_lo(lcd_col)};
            write_busy <= 1;
        end else if (lcd_write) begin
            send_pix_lo <= 1;
            write_busy <= 1;
            write_data <= {1'b1, col_hi(lcd_col)};
        end
    end
endmodule
