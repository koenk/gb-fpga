/* verilator lint_off UNUSED */
function [2:0] trunc_8to3(input [7:0] val8);
    trunc_8to3 = val8[2:0];
endfunction
/* verilator lint_on UNUSED */

/* verilator lint_off UNUSED */
function [7:0] trunc_16to8(input [15:0] val16);
    trunc_16to8 = val16[7:0];
endfunction
/* verilator lint_on UNUSED */

/* verilator lint_off UNUSED */
function [6:0] trunc_16to7(input [15:0] val16);
    trunc_16to7 = val16[6:0];
endfunction
/* verilator lint_on UNUSED */
