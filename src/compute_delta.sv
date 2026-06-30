// -------------------------------------------------------------------------------------//
// compute_delta : computes Black-Scholes call delta = N(d1) from the five parameters.      //
//                                                                                      //
//   d1 = ( ln(S/K) + (r + sigma^2/2)*T ) / ( sigma*sqrt(T) )                           //
//   delta = N(d1)                                                                      //
//                                                                                      //
// Uses one hyperbolic CORDIC (reused for ln then sqrt), one linear CORDIC for the      //
// division, and the cdf module for N(d1). FSM-sequenced; one result per request.       //
//                                                                                      //
// Division range: CORDIC linear vectoring converges only for |num/den| < ~2. Since     //
// N(d1) saturates to 0/1 well before |d1|=4, ratios outside the convergent range are   //
// clamped to d1 = +/-4 with no loss of accuracy.                                       //
// -------------------------------------------------------------------------------------//

module compute_delta #(
    parameter WIDTH = 32  // Q16.16
) (
    input  logic clk,
    input  logic nrst,

    input  logic start,
    input  logic signed [WIDTH-1:0] S,      // spot
    input  logic signed [WIDTH-1:0] K,      // strike
    input  logic signed [WIDTH-1:0] sigma,  // volatility
    input  logic signed [WIDTH-1:0] r,      // rate
    input  logic signed [WIDTH-1:0] T,      // time to maturity (years)

    output logic done,
    output logic signed [WIDTH-1:0] delta   // N(d1), Q16.16, call delta
);

    localparam signed [WIDTH-1:0] QUARTER   =  32'h00004000;
    localparam signed [WIDTH-1:0] HALF      =  32'h00008000;
    localparam signed [WIDTH-1:0] TWO       =  32'h00020000;
    localparam signed [WIDTH-1:0] FOUR      =  32'h00040000;
    localparam signed [WIDTH-1:0] NEG_FOUR  =  32'hFFFC0000;

    localparam HYP_LATENCY = 18; // hyperbolic CORDIC pipeline depth
    localparam LIN_LATENCY = 16; // linear CORDIC pipeline depth

    // fixed-point multiply helper
    function automatic signed [WIDTH-1:0] qmul(input signed [WIDTH-1:0] a,
                                               input signed [WIDTH-1:0] b);
        logic signed [63:0] prod;
        prod = {{32{a[WIDTH-1]}}, a} * {{32{b[WIDTH-1]}}, b};
        return prod[47:16];
    endfunction

// ----------------------------------------------------------------------------------//
// CORDIC instances                                                                   //
// ----------------------------------------------------------------------------------//

    // hyperbolic vectoring core (ln then sqrt)
    logic signed [WIDTH-1:0] hyp_x_in, hyp_y_in, hyp_z_in;
    logic signed [WIDTH-1:0] hyp_x_out, hyp_y_out, hyp_z_out;

    cordic #(.MODE(1), .ROTATE(0), .ITERATIONS(16), .WIDTH(WIDTH)) hyp (
        .clk(clk), .nrst(nrst),
        .x_in(hyp_x_in), .y_in(hyp_y_in), .z_in(hyp_z_in),
        .x_out(hyp_x_out), .y_out(hyp_y_out), .z_out(hyp_z_out)
    );

    // linear vectoring core (division): z_out = y_in / x_in
    logic signed [WIDTH-1:0] lin_x_in, lin_y_in, lin_z_in;
    logic signed [WIDTH-1:0] lin_x_out, lin_y_out, lin_z_out;

    cordic #(.MODE(2), .ROTATE(0), .ITERATIONS(16), .WIDTH(WIDTH)) lin (
        .clk(clk), .nrst(nrst),
        .x_in(lin_x_in), .y_in(lin_y_in), .z_in(lin_z_in),
        .x_out(lin_x_out), .y_out(lin_y_out), .z_out(lin_z_out)
    );

    // CDF instantiation
    logic cdf_start, cdf_done;
    logic signed [WIDTH-1:0] cdf_d1, cdf_out;

    cdf #(.WIDTH(WIDTH)) cdf_inst (
        .clk(clk), .nrst(nrst),
        .start(cdf_start), .d1(cdf_d1),
        .done(cdf_done), .cdf_out(cdf_out)
    );

// ----------------------------------------------------------------------------------//
// Registers                                                                         //
// ----------------------------------------------------------------------------------//

    logic signed [WIDTH-1:0] s_reg, k_reg, sigma_reg, r_reg, t_reg;
    logic signed [WIDTH-1:0] ln_sk;     // ln(S/K)
    logic signed [WIDTH-1:0] sqrt_t;    // sqrt(T)
    logic signed [WIDTH-1:0] num;       // numerator of d1
    logic signed [WIDTH-1:0] den;       // denominator of d1
    logic signed [WIDTH-1:0] div_num;   // numerator actually fed to the divider (maybe halved)
    logic                    div_scale; // 1 if num was halved (double the result)
    logic signed [WIDTH-1:0] d1_val;

// ----------------------------------------------------------------------------------//
// FSM                                                                                //
// ----------------------------------------------------------------------------------//

    typedef enum logic [3:0] {
        IDLE,
        LN_LOAD,   // seed hyperbolic core for ln(S/K)
        LN_WAIT,   // wait pipeline, capture ln
        SQRT_LOAD, // seed hyperbolic core for sqrt(T)
        SQRT_WAIT, // wait pipeline, capture sqrt
        COMPUTE,   // numerator, denominator via multiplies/adds
        DIV_CHECK, // decide: in-range division or clamp
        DIV_LOAD,  // seed linear core for division
        DIV_WAIT,  // wait pipeline, capture d1
        CDF_START, // pulse cdf
        CDF_WAIT,  // wait for cdf done
        FINISH
    } state_t;

    state_t state;
    logic [4:0] wait_cnt;

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state     <= IDLE;
            done      <= 0;
            delta     <= 0;
            cdf_start <= 0;
            wait_cnt  <= 0;
        end else begin
            done      <= 0;
            cdf_start <= 0;

            case (state)
                IDLE: begin
                    if (start) begin
                        s_reg     <= S;
                        k_reg     <= K;
                        sigma_reg <= sigma;
                        r_reg     <= r;
                        t_reg     <= T;
                        state     <= LN_LOAD;
                    end
                end

                LN_LOAD: begin // ln(S/K): hyperbolic vectoring x=S+K, y=S-K -> z_out = ln(S/K)/2
                    hyp_x_in <= s_reg + k_reg;
                    hyp_y_in <= s_reg - k_reg;
                    hyp_z_in <= '0;
                    wait_cnt <= 0;
                    state    <= LN_WAIT;
                end

                LN_WAIT: begin
                    if (wait_cnt == HYP_LATENCY) begin
                        ln_sk <= hyp_z_out <<< 1; // z_out is ln/2, double it
                        state <= SQRT_LOAD;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                SQRT_LOAD: begin // sqrt(T): hyperbolic vectoring x=T+0.25, y=T-0.25 -> x_out = sqrt(T)
                    hyp_x_in <= t_reg + QUARTER;
                    hyp_y_in <= t_reg - QUARTER;
                    hyp_z_in <= '0;
                    wait_cnt <= 0;
                    state    <= SQRT_WAIT;
                end

                SQRT_WAIT: begin
                    if (wait_cnt == HYP_LATENCY) begin
                        sqrt_t <= hyp_x_out;
                        state  <= COMPUTE;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                COMPUTE: begin // num = ln(S/K) + (r + sigma^2/2)*T ; den = sigma*sqrt(T)
                    num <= ln_sk + qmul(r_reg + qmul(qmul(sigma_reg, sigma_reg), HALF), t_reg);
                    den <= qmul(sigma_reg, sqrt_t);
                    state <= DIV_CHECK;
                end

                /*  Division range handling. CORDIC linear vectoring converges only for
                    |num/den| < 2. We need d1 up to 4 (CDF clamps there), so:
                    ratio >= 4        -> clamp d1 to +/-4 (delta already saturated)
                    2 <= ratio < 4    -> halve num, divide (ratio now < 2), double result
                    ratio < 2         -> divide directly                                    */
                DIV_CHECK: begin
                    div_scale <= 0;
                    if (den == 0) begin
                        // degenerate; clamp by sign of num
                        d1_val <= num[WIDTH-1] ? NEG_FOUR : FOUR;
                        state  <= CDF_START;
                    end else if (abs_val(num) >= qmul(FOUR, abs_val(den))) begin
                        d1_val <= (num[WIDTH-1] ^ den[WIDTH-1]) ? NEG_FOUR : FOUR;
                        state  <= CDF_START;
                    end else if (abs_val(num) >= qmul(TWO, abs_val(den))) begin
                        // halve num so CORDIC converges, double result later
                        div_num   <= num >>> 1;
                        div_scale <= 1;
                        state     <= DIV_LOAD;
                    end else begin
                        div_num   <= num;
                        state     <= DIV_LOAD;
                    end
                end

                DIV_LOAD: begin // division via linear vectoring: x=den, y=num, z=0 -> z_out = num/den
                    lin_x_in <= den;
                    lin_y_in <= div_num;
                    lin_z_in <= '0;
                    wait_cnt <= 0;
                    state    <= DIV_WAIT;
                end

                DIV_WAIT: begin
                    if (wait_cnt == LIN_LATENCY) begin
                        // undo the halving if it was applied
                        d1_val <= div_scale ? (lin_z_out <<< 1) : lin_z_out;
                        state  <= CDF_START;
                    end else begin
                        wait_cnt <= wait_cnt + 1;
                    end
                end

                CDF_START: begin
                    cdf_d1    <= d1_val;
                    cdf_start <= 1;
                    state     <= CDF_WAIT;
                end

                CDF_WAIT: begin
                    if (cdf_done) begin
                        delta <= cdf_out;
                        state <= FINISH;
                    end
                end

                FINISH: begin
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // absolute value helper
    function automatic signed [WIDTH-1:0] abs_val(input signed [WIDTH-1:0] v);
        return v[WIDTH-1] ? -v : v;
    endfunction

endmodule