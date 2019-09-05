`include "main.v"
`include "uart.v"

module syn_top (
    input device_clk,
    output LEDR_N, LEDG_N,
    output LED1, output LED2, output LED3, output LED4, output LED5,
    output P1A1, output P1A2, output P1A3, output P1A4, output P1A7, output P1A8, output P1A9, output P1A10,
    output P1B1, output P1B2, output P1B3, output P1B4, output P1B7, output P1B8, output P1B9, output P1B10,
    input BTN_N,
    input RX, output TX
);

main main(
    clk,

    lcd_hblank,
    lcd_vblank,
    lcd_write,
    lcd_col,
    lcd_x,
    lcd_y,

    dbg_pc,
    dbg_sp,
    dbg_AF,
    dbg_BC,
    dbg_DE,
    dbg_HL,
    dbg_instruction_retired,
    dbg_halted,
    dbg_last_opcode,
    dbg_stage
);

wire lcd_hblank, lcd_vblank;
wire lcd_write;
wire [1:0] lcd_col;
wire [7:0] lcd_x, lcd_y;

/*
 * Clock.
 */
/* Slow down clock significantly. */
/*
wire clk;
reg [21:0] clk_cnt;
always @(posedge device_clk)
    clk_cnt = clk_cnt + 1;
assign clk = clk_cnt[21];
*/

/* Divide clock by 3, to 4MHz. */
wire clk;
reg [1:0] clk_pos_count, clk_neg_count;
initial begin
    clk_pos_count <= 0;
    clk_neg_count <= 0;
end
always @(posedge device_clk)
    if (clk_pos_count == 2) clk_pos_count <= 0;
    else clk_pos_count <= clk_pos_count + 1;
always @(negedge device_clk)
    if (clk_neg_count == 2) clk_neg_count <= 0;
    else clk_neg_count <= clk_neg_count + 1;
assign clk = ((clk_pos_count == 2) | (clk_neg_count == 2));

/* Clock on pushbutton. */
/*
reg clk;
reg [15:0] clk_cnt;
reg cur, last;
always @(posedge device_clk) begin
    last <= cur;
    cur <= ~BTN_N;

    if (clk != last) begin
        clk_cnt <= clk_cnt + 1;
        if (clk_cnt == 16'hffff)
            clk = ~clk;
    end else
        clk_cnt <= 0;
end
*/


/*
 * Debug output on pins.
 */
wire [15:0] dbg_pc, dbg_sp, dbg_AF, dbg_BC, dbg_DE, dbg_HL;
wire [7:0] dbg_last_opcode;
wire [5:0] dbg_stage;
reg dbg_instruction_retired;
wire dbg_halted;

assign {LED5, LED4, LED3, LED2, LED1} = dbg_pc[4:0];
assign LEDR_N = ~dbg_halted;
assign LEDG_N = clk;

assign {P1A1, P1A2, P1A3, P1A4, P1A7, P1A8, P1A9, P1A10 } =
    {2'b0, clk, lcd_write, lcd_hblank, lcd_vblank, lcd_col};
assign {P1B1, P1B2, P1B3, P1B4, P1B7, P1B8, P1B9, P1B10 } = dbg_pc[7:0];


/*
 * Serial debugging output.
 */
/*
wire reset = 0;
reg transmit;
reg [7:0] tx_byte;
wire received;
wire [7:0] rx_byte;
wire is_receiving;
wire is_transmitting;
wire recv_error;
reg [3:0] stage, next_stage;
always @(*)
    if (clk)
        next_stage = 0;
    else
        if (stage != 15)
            next_stage = stage + 1;
        else
            next_stage = stage;

always @(posedge device_clk)
    if (!transmit && !is_transmitting) begin
        case (next_stage)
             1: begin tx_byte <= {dbg_halted, dbg_instruction_retired, 1'b0, dbg_stage}; transmit <= 1; end
             2: begin tx_byte <= dbg_pc[15:8]; transmit <= 1; end
             3: begin tx_byte <= dbg_pc[7:0]; transmit <= 1; end
             4: begin tx_byte <= dbg_sp[15:8]; transmit <= 1; end
             5: begin tx_byte <= dbg_sp[7:0]; transmit <= 1; end
             6: begin tx_byte <= dbg_AF[15:8]; transmit <= 1; end
             7: begin tx_byte <= dbg_AF[7:0]; transmit <= 1; end
             8: begin tx_byte <= dbg_BC[15:8]; transmit <= 1; end
             9: begin tx_byte <= dbg_BC[7:0]; transmit <= 1; end
            10: begin tx_byte <= dbg_DE[15:8]; transmit <= 1; end
            11: begin tx_byte <= dbg_DE[7:0]; transmit <= 1; end
            12: begin tx_byte <= dbg_HL[15:8]; transmit <= 1; end
            13: begin tx_byte <= dbg_HL[7:0]; transmit <= 1; end
            14: begin tx_byte <= dbg_last_opcode; transmit <= 1; end
            default: transmit <= 0;
        endcase
        stage <= next_stage;
    end else
        transmit <= 0;

uart #(
    .baud_rate(115200),
    .sys_clk_freq(12000000)
    )
uart(
    .clk(device_clk),                 // The master clock for this module
    .rst(reset),                      // Synchronous reset
    .rx(RX),                          // Incoming serial line
    .tx(TX),                          // Outgoing serial line
    .transmit(transmit),              // Signal to transmit
    .tx_byte(tx_byte),                // Byte to transmit
    .received(received),              // Indicated that a byte has been received
    .rx_byte(rx_byte),                // Byte received
    .is_receiving(is_receiving),      // Low when receive line is idle
    .is_transmitting(is_transmitting),// Low when transmit line is idle
    .recv_error(recv_error)           // Indicates error in receiving packet.
);
*/

endmodule
