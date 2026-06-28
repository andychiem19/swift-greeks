module cdf #(
    parameter WIDTH      = 32,  // Q16.16 fixed-point
    parameter LUT_N      = 128, // number of LUT intervals (129 entries)
    parameter X_MAX_Q16  = 32'h00040000 // 4.0 in Q16.16, table domain [0, X_MAX]
) (
    input  logic clk,
    input  logic nrst,

    input  logic start,                   // pulse high to begin a computation
    input  logic signed [WIDTH-1:0] d1,   // input value (Q16.16)

    output logic done,                    // pulses high when result is ready
    output logic signed [WIDTH-1:0] cdf_out // N(d1) in Q16.16
);

// ----------------------------------------------------------------------------------//
// Approximation Constants (Abramowitz & Stegun 26.2.17, Q16.16)                      //
// ----------------------------------------------------------------------------------//

    localparam signed [WIDTH-1:0] B1 = 32'h000051C3; //  0.319381530
    localparam signed [WIDTH-1:0] B2 = 32'hFFFFA4B8; // -0.356563782
    localparam signed [WIDTH-1:0] B3 = 32'h0001C80F; //  1.781477937
    localparam signed [WIDTH-1:0] B4 = 32'hFFFE2DC2; // -1.821255978
    localparam signed [WIDTH-1:0] B5 = 32'h0001548D; //  1.330274429
    localparam signed [WIDTH-1:0] ONE = 32'h00010000; //  1.0

// ----------------------------------------------------------------------------------//
// Lookup Tables (loaded from hex init files)                                         //
// ----------------------------------------------------------------------------------//

    // phi_lut[i] = e^(-x^2/2)/sqrt(2pi) at x = i*(X_MAX/LUT_N)
    // t_lut[i]   = 1/(1 + 0.2316419*x) at x = i*(X_MAX/LUT_N)
    logic signed [WIDTH-1:0] phi_lut [0:LUT_N];
    logic signed [WIDTH-1:0] t_lut   [0:LUT_N];

    initial begin
        $readmemh("phi_lut.memh", phi_lut);
        $readmemh("t_lut.memh",   t_lut);
    end

// ----------------------------------------------------------------------------------//
// Fixed-point multiply helper (Q16.16): (a*b) >> 16 with full-width intermediate     //
// ----------------------------------------------------------------------------------//

    function automatic signed [WIDTH-1:0] qmul(input signed [WIDTH-1:0] a,
                                               input signed [WIDTH-1:0] b);
        logic signed [63:0] prod;
        prod = {{32{a[WIDTH-1]}}, a} * {{32{b[WIDTH-1]}}, b};
        return prod[47:16];
    endfunction

// ----------------------------------------------------------------------------------//
// Datapath registers                                                                 //
// ----------------------------------------------------------------------------------//

    logic sign;                          // 1 if d1 was negative
    logic signed [WIDTH-1:0] absx;       // |d1|, clamped to [0, X_MAX]
    logic signed [WIDTH-1:0] phi_val;    // interpolated phi(absx)
    logic signed [WIDTH-1:0] t_val;      // interpolated t(absx)
    logic signed [WIDTH-1:0] poly;       // horner accumulator
    logic signed [WIDTH-1:0] result;     // 1 - phi*poly (for positive branch)

    // interpolation working values
    logic [$clog2(LUT_N+1)-1:0] idx;     // table index
    logic signed [WIDTH-1:0] frac;       // fractional position within interval (Q16.16)
    logic signed [WIDTH-1:0] lo_phi, hi_phi, lo_t, hi_t;

// ----------------------------------------------------------------------------------//
// FSM                                                                                //
// ----------------------------------------------------------------------------------//

    typedef enum logic [2:0] {
        IDLE,
        PREP,     // compute sign, |x|, clamp, table index + frac
        FETCH,    // register the two LUT endpoints for phi and t
        INTERP,   // linear interpolation of phi and t
        HORNER,   // evaluate polynomial via horner's method (multi-cycle)
        COMBINE,  // result = 1 - phi*poly
        FINISH    // apply sign: N(x) = sign ? 1-result : result
    } state_t;

    state_t state;
    logic [2:0] horner_step;

    // LUT_N intervals span [0, X_MAX], so step = X_MAX/LUT_N
    // index = absx / step = absx * LUT_N / X_MAX
    // with X_MAX = 4.0 and LUT_N = 128, step = 0.03125 = 1/32, so index = absx * 32
    // frac = absx*32 - index  (fractional part)
    localparam signed [WIDTH-1:0] SCALE = (LUT_N << 16) / (X_MAX_Q16 >>> 16); // = LUT_N/X_MAX in Q16.16... handled below

    logic signed [WIDTH-1:0] scaled_idx;

    // integer table index: bits [16 +: addr_width] of scaled_idx, sized to the table
    // this avoids a wide-slice-into-narrow-index width warning
    logic [$clog2(LUT_N+1)-1:0] int_idx;
    assign int_idx = scaled_idx[16 +: $clog2(LUT_N+1)];

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state       <= IDLE;
            done        <= 0;
            cdf_out     <= 0;
            horner_step <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        sign <= d1[WIDTH-1];
                        // |d1|
                        absx <= d1[WIDTH-1] ? -d1 : d1;
                        state <= PREP;
                    end
                end

                PREP: begin
                    // clamp to X_MAX, then scale to table index in the same cycle
                    // scaled index = clamped_absx * (LUT_N / X_MAX) = clamped_absx * 32
                    // = clamped_absx << 5, since LUT_N/X_MAX = 128/4 = 32
                    if (absx > X_MAX_Q16)
                        scaled_idx <= X_MAX_Q16 <<< 5;
                    else
                        scaled_idx <= absx <<< 5;
                    state <= FETCH;
                end

                FETCH: begin
                    // bound index to LUT_N-1 so the +1 interpolation tap stays in range
                    // (at exactly X_MAX the integer index is LUT_N, frac is 0, so clamping
                    //  to LUT_N-1 with frac forced to 0 still returns the endpoint value)
                    // int_idx is the integer table index, sized to the table address width
                    if (int_idx >= LUT_N) begin
                        idx    <= LUT_N - 1;
                        frac   <= ONE;                       // frac=1 -> returns hi = phi_lut[LUT_N]
                        lo_phi <= phi_lut[LUT_N-1];
                        hi_phi <= phi_lut[LUT_N];
                        lo_t   <= t_lut[LUT_N-1];
                        hi_t   <= t_lut[LUT_N];
                    end else begin
                        idx    <= int_idx;
                        frac   <= {16'b0, scaled_idx[15:0]};
                        lo_phi <= phi_lut[int_idx];
                        hi_phi <= phi_lut[int_idx + 1];
                        lo_t   <= t_lut[int_idx];
                        hi_t   <= t_lut[int_idx + 1];
                    end
                    state <= INTERP;
                end

                INTERP: begin
                    // lo + frac*(hi - lo)
                    phi_val <= lo_phi + qmul(frac, hi_phi - lo_phi);
                    t_val   <= lo_t   + qmul(frac, hi_t   - lo_t);
                    poly    <= 0;
                    horner_step <= 0;
                    state <= HORNER;
                end

                HORNER: begin
                    // poly = t*(b1 + t*(b2 + t*(b3 + t*(b4 + t*b5))))
                    // build inner-to-outer: acc = b5; acc = b4 + t*acc; ... ; poly = t*acc
                    case (horner_step)
                        0: begin poly <= B5;                          horner_step <= 1; end
                        1: begin poly <= B4 + qmul(t_val, poly);      horner_step <= 2; end
                        2: begin poly <= B3 + qmul(t_val, poly);      horner_step <= 3; end
                        3: begin poly <= B2 + qmul(t_val, poly);      horner_step <= 4; end
                        4: begin poly <= B1 + qmul(t_val, poly);      horner_step <= 5; end
                        5: begin poly <= qmul(t_val, poly);           state <= COMBINE; end
                    endcase
                end

                COMBINE: begin
                    // result = 1 - phi*poly
                    result <= ONE - qmul(phi_val, poly);
                    state <= FINISH;
                end

                FINISH: begin
                    cdf_out <= sign ? (ONE - result) : result;
                    done    <= 1;
                    state   <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule