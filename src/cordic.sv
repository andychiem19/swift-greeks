module cordic #(
    parameter MODE          = 0,
    parameter ITERATIONS    = 16, // MAX 16
    parameter WIDTH         = 32
    // parameter FRAC_BITS     = 16 // Just going to hardcode 16
) (
    input logic     clk,
    input logic     nrst,

    /** CORDIC INPUTS **/
    input logic signed [WIDTH-1:0]  x_in,
    input logic signed [WIDTH-1:0]  y_in,
    input logic signed [WIDTH-1:0]  z_in,

    /** CORDIC OUTPUTS **/
    output logic signed [WIDTH-1:0] x_out,
    output logic signed [WIDTH-1:0] y_out,
    output logic signed [WIDTH-1:0] z_out
);

    logic signed [WIDTH-1:0] x_pipe [0:ITERATIONS];
    logic signed [WIDTH-1:0] y_pipe [0:ITERATIONS];
    logic signed [WIDTH-1:0] z_pipe [0:ITERATIONS];

    /* LOOKUP TABLE FOR UP TO 16 ITERATIONS */
    logic signed [WIDTH-1:0] lut [0:ITERATIONS-1];

    generate
        if (MODE == 0) begin : gen_lut_circular
            assign lut[0]  = 32'h0000C910;
            assign lut[1]  = 32'h000076B2;
            assign lut[2]  = 32'h00003EB7;
            assign lut[3]  = 32'h00001FD6;
            assign lut[4]  = 32'h00000FFB;
            assign lut[5]  = 32'h000007FF;
            assign lut[6]  = 32'h00000400;
            assign lut[7]  = 32'h00000200;
            assign lut[8]  = 32'h00000100;
            assign lut[9]  = 32'h00000080;
            assign lut[10] = 32'h00000040;
            assign lut[11] = 32'h00000020;
            assign lut[12] = 32'h00000010;
            assign lut[13] = 32'h00000008;
            assign lut[14] = 32'h00000004;
            assign lut[15] = 32'h00000002;
        end
        else if (MODE == 1) begin : gen_lut_hyperbolic
            assign lut[0]  = 32'h00008C9F;
            assign lut[1]  = 32'h00004163;
            assign lut[2]  = 32'h0000202B;
            assign lut[3]  = 32'h00001005;
            assign lut[4]  = 32'h00000801;
            assign lut[5]  = 32'h00000400;
            assign lut[6]  = 32'h00000200;
            assign lut[7]  = 32'h00000100;
            assign lut[8]  = 32'h00000080;
            assign lut[9]  = 32'h00000040;
            assign lut[10] = 32'h00000020;
            assign lut[11] = 32'h00000010;
            assign lut[12] = 32'h00000008;
            assign lut[13] = 32'h00000004;
            assign lut[14] = 32'h00000002;
            assign lut[15] = 32'h00000001;
        end
        else begin : gen_lut_linear
            assign lut[0]  = 32'h00010000;
            assign lut[1]  = 32'h00008000;
            assign lut[2]  = 32'h00004000;
            assign lut[3]  = 32'h00002000;
            assign lut[4]  = 32'h00001000;
            assign lut[5]  = 32'h00000800;
            assign lut[6]  = 32'h00000400;
            assign lut[7]  = 32'h00000200;
            assign lut[8]  = 32'h00000100;
            assign lut[9]  = 32'h00000080;
            assign lut[10] = 32'h00000040;
            assign lut[11] = 32'h00000020;
            assign lut[12] = 32'h00000010;
            assign lut[13] = 32'h00000008;
            assign lut[14] = 32'h00000004;
            assign lut[15] = 32'h00000002;
        end
    endgenerate

    always_comb begin

    end

endmodule