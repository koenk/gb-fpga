/*
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   16.777 MHz
 * Achieved output frequency:    16.875 MHz
 */

module pll(
    input  clock_in,
    output clock_out,
    output locked
);

SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR =  0
        .DIVF(7'b0101100),      // DIVF = 44
        .DIVQ(3'b101),          // DIVQ =  5
        .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1

    ) uut (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .PACKAGEPIN(clock_in),
        .PLLOUTCORE(clock_out)
    );

endmodule
