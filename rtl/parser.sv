module parser (
    input   logic clk,
    input   logic nrst,

    // AXI-Stream signals
    input   logic [7:0] tdata,
    input   logic tvalid,
    input   logic tlast,

    output  logic [7:0] packet,
    output  logic packet_valid,
    output  logic packet_end
);


/* ETHERNET FRAME STRUCTURE 

ERROR
-->
IDLE:
Preamble: 7 bytes of 0x55
SFD (Start Frame Delimiter): 1 byte of 0xD5

READ_ETH
Destination MAC: 6 bytes
Source MAC: 6 bytes
EtherType: 2 bytes

IP Header: 20 bytes, or IHL*4           // READ_IP
UDP Header: 8 bytes                     // READ_UDP
Payload: Data being transmitted         // PAYLOAD

tlast -> assert packet_end and transition back to IDLE

*/

typedef enum logic [2:0] {
    IDLE,
    READ_ETH,
    READ_IP,
    READ_UDP,
    PAYLOAD,
    ERROR
} parser_state;

// add necessary registers here
logic [2:0] preamble_count; 
logic [3:0] eth_count;
logic [5:0] ip_count; // IHL's max value is 15, so max IP header size is 15 * 4 = 60 bytes; but usually just 20 bytes
logic [2:0] udp_count; // 8 bytes

typedef struct packed {
    logic [15:0] ethertype;
    logic [5:0] ipbytes;
} protocol_t;

parser_state state;
protocol_t protocol;

// main parser FSM
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        state <= IDLE;

        // Initialize registers
        preamble_count <= 0;
        eth_count <= 0;
        ip_count <= 0;
        udp_count <= 0;

        // Default for IPv4
        protocol.ipbytes <= 20;
    end 
    
    else begin
        case(state)
            IDLE: begin
                if (tvalid) begin
                    if (preamble_count < 7) begin 
                        if (tdata == 8'h55) begin // checks for 7 consecutive preamble bits
                            preamble_count <= preamble_count + 1;
                        end 
                        
                        else begin
                            preamble_count <= 0;
                        end
                    end 
                    
                    else if (preamble_count == 7) begin
                        if (tdata == 8'hD5) begin // SFD detected, move to READ_ETH
                            preamble_count <= 0;
                            state <= READ_ETH;
                        end 
                        
                        else begin // wrong byte, resetting
                            preamble_count <= 0;
                        end
                    end
                end
            end

            READ_ETH: begin
                if (tvalid) begin
                    eth_count <= eth_count + 1;

                    if (eth_count == 12) begin // Reads Ethertype
                        protocol.ethertype[15:8] <= tdata;
                    end

                    if (eth_count == 13) begin
                        protocol.ethertype[7:0] <= tdata;
                        eth_count <= 0;

                        if (protocol.ethertype[15:8] == 8'h08 && tdata == 8'h00) // IPv4, needs to check against current tdata because bottom half is assigned in the same cycle
                            state <= READ_IP;
                        else
                            state <= ERROR; // unrecognized protocol
                    end
                end
            end

            READ_IP: begin
                if (tvalid) begin
                    ip_count <= ip_count + 1;

                    if (ip_count == 0) begin
                        protocol.ipbytes <= (tdata[3:0] * 4); 
                    end

                    if (ip_count == protocol.ipbytes - 1) begin
                        ip_count <= 0;
                        state <= READ_UDP;
                    end
                end
            end

            READ_UDP: begin
                if (tvalid) begin
                    udp_count <= udp_count + 1;

                    if (udp_count == 7) begin
                        udp_count <= 0;
                        state <= PAYLOAD;
                    end
                end
            end

            PAYLOAD: begin
                if (tvalid) begin
                    packet <= tdata;
                    if (tlast) begin
                        packet_end <= 1;
                        packet_valid <= 0;
                        state <= IDLE;
                    end else begin
                        packet_valid <= 1;
                        packet_end <= 0;
                    end
                end else begin
                    packet_valid <= 0;
                    packet_end <= 0;
                end
            end

            ERROR: begin
                // resets FSM and registers when an error state is reached
                state <= IDLE;
            end

            default: state <= ERROR;
        endcase
    end
end

endmodule
