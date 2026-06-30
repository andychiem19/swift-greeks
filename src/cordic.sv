module cordic #(
    parameter MODE          = 0, // 0=circular, 1=hyperbolic, 2=linear
    parameter ROTATE        = 1, // 1=rotation (z->0), 0=vectoring(y->0)
    parameter ITERATIONS    = 16, // MAX 16
    parameter WIDTH         = 32
    // Q16 fixed-point hardcoded (16 fractional bits)
) (
    input logic     clk,
    input logic     nrst,

    // CORDIC INPUTS
    input logic signed [WIDTH-1:0]  x_in,
    input logic signed [WIDTH-1:0]  y_in,
    input logic signed [WIDTH-1:0]  z_in,

    // CORDIC OUTPUTS
    output logic signed [WIDTH-1:0] x_out,
    output logic signed [WIDTH-1:0] y_out,
    output logic signed [WIDTH-1:0] z_out
);

    // PIPE ARRAYS
    // hyperbolic needs 18 stages due to repeated iterations 4 and 13
    localparam STAGES = (MODE == 1) ? 18 : ITERATIONS;
    logic signed [WIDTH-1:0] x_pipe [0:STAGES];
    logic signed [WIDTH-1:0] y_pipe [0:STAGES];
    logic signed [WIDTH-1:0] z_pipe [0:STAGES];

// ----------------------------------------------------------------------------------//
// Lookup Table Values                                                               //
// ----------------------------------------------------------------------------------//

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

// ----------------------------------------------------------------------------------//
// Gain Correction                                                                   //
// ----------------------------------------------------------------------------------//

    /* Circular:   1/K = 1/1.64676 = 0.60725 → 0x00009B74
       Hyperbolic: 1/K = 1/0.82816 = 1.20750 → 0x00013500
       Linear:     no gain, pass through */
 
    logic signed [WIDTH-1:0] x_scaled, y_scaled;
    logic signed [63:0] x_tmp, y_tmp;
 
    generate
        if (MODE == 0) begin : gen_gain_circular
            localparam signed [WIDTH-1:0] GAIN_INV = 32'h00009B74;
            assign x_tmp    = {{32{x_in[WIDTH-1]}}, x_in} * {{32{GAIN_INV[WIDTH-1]}}, GAIN_INV};
            assign y_tmp    = {{32{y_in[WIDTH-1]}}, y_in} * {{32{GAIN_INV[WIDTH-1]}}, GAIN_INV};
            assign x_scaled = x_tmp[47:16];
            assign y_scaled = y_tmp[47:16];
        end else if (MODE == 1) begin : gen_gain_hyperbolic
            localparam signed [WIDTH-1:0] GAIN_INV = 32'h00013500;
            assign x_tmp    = {{32{x_in[WIDTH-1]}}, x_in} * {{32{GAIN_INV[WIDTH-1]}}, GAIN_INV};
            assign y_tmp    = {{32{y_in[WIDTH-1]}}, y_in} * {{32{GAIN_INV[WIDTH-1]}}, GAIN_INV};
            assign x_scaled = x_tmp[47:16];
            assign y_scaled = y_tmp[47:16];
        end else begin : gen_gain_linear
            assign x_tmp    = '0;
            assign y_tmp    = '0;
            assign x_scaled = x_in;
            assign y_scaled = y_in;
        end
    endgenerate

// ----------------------------------------------------------------------------------//
// CORDIC Pipeline                                                                   //
// ----------------------------------------------------------------------------------//

    // connect inputs to stage 0
    assign x_pipe[0] = x_scaled;
    assign y_pipe[0] = y_scaled;
    assign z_pipe[0] = z_in;
    
    // connect final stage to outputs
    assign x_out = x_pipe[STAGES];
    assign y_out = y_pipe[STAGES];
    assign z_out = z_pipe[STAGES];

    genvar i;
    generate
        if (MODE != 1) begin : gen_stages_standard
            for (i = 0; i < ITERATIONS; i++) begin : gen_stage // one registered pipeline stage per cordic iteration

                // sigma=1 → positive direction; sigma=0 → negative direction
                // rotation: drive z→0, so direction = sign(z)
                // vectoring: drive y→0, so direction = -sign(y)
                logic sigma;
                if (ROTATE == 1)
                    assign sigma = ~z_pipe[i][WIDTH-1]; 
                else
                    assign sigma = y_pipe[i][WIDTH-1]; 

                // shift amount: others are 0-based
                logic signed [WIDTH-1:0] x_sh, y_sh;
                assign x_sh = x_pipe[i] >>> i;
                assign y_sh = y_pipe[i] >>> i;
                
                // cordic update equations
                logic signed [WIDTH-1:0] x_nxt, y_nxt, z_nxt;
                if (MODE == 0) begin : gen_circular
                    assign x_nxt = sigma ? x_pipe[i] - y_sh : x_pipe[i] + y_sh;
                    assign y_nxt = sigma ? y_pipe[i] + x_sh : y_pipe[i] - x_sh;
                end else begin : gen_linear
                    assign x_nxt = x_pipe[i];
                    assign y_nxt = sigma ? y_pipe[i] + x_sh : y_pipe[i] - x_sh;
                end

                // z update is same for all modes, just accumulates rotation
                assign z_nxt = sigma ? z_pipe[i] - lut[i] : z_pipe[i] + lut[i];

                always_ff @(posedge clk or negedge nrst) begin
                    if (!nrst) begin
                        x_pipe[i+1] <= '0;
                        y_pipe[i+1] <= '0;
                        z_pipe[i+1] <= '0;
                    end else begin
                        x_pipe[i+1] <= x_nxt;
                        y_pipe[i+1] <= y_nxt;
                        z_pipe[i+1] <= z_nxt;
                    end
                end
            end
        end else begin : gen_stages_hyperbolic
            // hyperbolic repeats iterations 4 and 13 (0-indexed: 3 and 12) for convergence
            for (i = 0; i < 18; i++) begin : gen_stage // one registered pipeline stage per cordic iteration

                // sigma=1 → positive direction; sigma=0 → negative direction
                // rotation: drive z→0, so direction = sign(z)
                // vectoring: drive y→0, so direction = -sign(y)
                logic sigma;
                if (ROTATE == 1)
                    assign sigma = ~z_pipe[i][WIDTH-1];
                else
                    assign sigma = y_pipe[i][WIDTH-1];

                // shift amount: hyperbolic is 1-based (iter+1)
                // iter index per stage, accounting for repeats at stages 4 and 14
                localparam int ITER = (i < 4) ? i :
                                      (i == 4) ? 3 :
                                      (i < 14) ? i - 1 :
                                      (i == 14) ? 12 :
                                      i - 2;
                logic signed [WIDTH-1:0] x_sh, y_sh;
                assign x_sh = x_pipe[i] >>> (ITER + 1);
                assign y_sh = y_pipe[i] >>> (ITER + 1);

                // cordic update equations
                logic signed [WIDTH-1:0] x_nxt, y_nxt, z_nxt;
                assign x_nxt = sigma ? x_pipe[i] + y_sh : x_pipe[i] - y_sh;
                assign y_nxt = sigma ? y_pipe[i] + x_sh : y_pipe[i] - x_sh;

                // z update is same for all modes, just accumulates rotation
                assign z_nxt = sigma ? z_pipe[i] - lut[ITER] : z_pipe[i] + lut[ITER];

                always_ff @(posedge clk or negedge nrst) begin
                    if (!nrst) begin
                        x_pipe[i+1] <= '0;
                        y_pipe[i+1] <= '0;
                        z_pipe[i+1] <= '0;
                    end else begin
                        x_pipe[i+1] <= x_nxt;
                        y_pipe[i+1] <= y_nxt;
                        z_pipe[i+1] <= z_nxt;
                    end
                end
            end
        end
    endgenerate

endmodule