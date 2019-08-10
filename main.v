`include "cpu.v"

module main (
    input clk,

    output [7:0] dbg1,
    output [7:0] dbg2,
    output [7:0] dbg3,
    output [7:0] dbg4,

    output [15:0] dbg_pc,
    output [3:0] dbg_F,
    output [7:0] dbg_A,
    output [7:0] dbg_B,
    output [7:0] dbg_C,
    output dbg_instruction_retired,
    output dbg_halted
);


//reg [3:0] mem[0:1023];
reg [7:0] mem [127:0];
wire mem_do_write;
/* verilator lint_off UNUSED */
wire [15:0] mem_addr;
/* verilator lint_on UNUSED */
wire [7:0] mem_data_read, mem_data_write;

reg reset;
reg [7:0] reset_cnt;

//integer i;
initial begin
    reset = 1;
    reset_cnt = 0;

    //for (i = 0; i < 128; i++)
    //    mem[i] = 8'hff;
    $readmemh("build/code.hex", mem);
end

assign dbg1 = mem[0];
assign dbg2 = mem[1];
assign dbg3 = mem[2];
assign dbg4 = mem[3];

cpu cpu(
    clk,
    reset,

    mem_addr,
    mem_data_write,
    mem_data_read,
    mem_do_write,

    dbg_halted,

    dbg_pc,
    dbg_F,
    dbg_A,
    dbg_B,
    dbg_C,
    dbg_instruction_retired
);

always @(posedge clk)
    if (reset_cnt == 8'hff)
        reset <= 0;
    else
        reset_cnt <= reset_cnt + 1;

always @(posedge clk) begin
    if (mem_do_write)
        mem[mem_addr[6:0]] <= mem_data_write;
end

assign mem_data_read = mem[mem_addr[6:0]];

endmodule
