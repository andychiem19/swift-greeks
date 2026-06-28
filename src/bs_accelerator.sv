module bs_accelerator (
    input logic         clk,
    input logic         nrst,
    input logic [7:0]   packet,
    input logic         packet_valid,
    input logic         packet_end,

    output logic [31:0] delta,
    output logic        valid
);

endmodule