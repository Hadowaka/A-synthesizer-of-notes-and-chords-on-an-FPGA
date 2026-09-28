`timescale 1ns/1ps

// ============================================================
// USB full-speed packet serializer, clk = 48 MHz (4 clk / bit)
// ============================================================

module usb_tx (
    input  wire       clk,
    input  wire       rst,

    input  wire       start,        // pulse: send one packet
    input  wire [7:0] tx_byte,
    input  wire       tx_last,
    output reg        tx_get = 1'b0,

    output reg        oe     = 1'b0,   // drive the bus
    output reg        dp_o   = 1'b1,
    output reg        dm_o   = 1'b0,

    output wire       busy,
    output reg        done   = 1'b0    // pulse when the packet is finished
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_SYNC = 3'd1;
    localparam [2:0] S_DATA = 3'd2;
    localparam [2:0] S_EOP  = 3'd3;

    // 12 MHz bit tick
    reg [1:0] phase = 2'd0;
    always @(posedge clk) phase <= rst ? 2'd0 : phase + 1'b1;
    wire tick = (phase == 2'd3);

    reg [2:0] st         = S_IDLE;
    reg       start_req  = 1'b0;
    reg [2:0] sync_i     = 3'd0;
    reg [7:0] sh         = 8'd0;
    reg [3:0] nbits      = 4'd0;
    reg       last_loaded = 1'b0;
    reg [2:0] ones       = 3'd0;
    reg       lvl        = 1'b1;      // 1 = J, 0 = K
    reg [1:0] eop_i      = 2'd0;

    assign busy = (st != S_IDLE) || start_req;

    wire bit_v = (nbits == 4'd0) ? tx_byte[0] : sh[0];

    always @(posedge clk) begin
        tx_get <= 1'b0;
        done   <= 1'b0;

        if (rst) begin
            st        <= S_IDLE;
            start_req <= 1'b0;
            oe        <= 1'b0;
            dp_o      <= 1'b1;
            dm_o      <= 1'b0;
            lvl       <= 1'b1;
            ones      <= 3'd0;
        end
        else begin

            if (start)
                start_req <= 1'b1;

            if (tick) begin
                case (st)

                    S_IDLE: begin
                        oe <= 1'b0;
                        if (start_req) begin
                            start_req   <= 1'b0;
                            // first SYNC bit (0): J -> K
                            lvl         <= 1'b0;
                            dp_o        <= 1'b0;
                            dm_o        <= 1'b1;
                            oe          <= 1'b1;
                            sync_i      <= 3'd1;
                            ones        <= 3'd0;
                            nbits       <= 4'd0;
                            last_loaded <= 1'b0;
                            st          <= S_SYNC;
                        end
                    end
                    S_SYNC: begin
                        if (sync_i == 3'd7) begin
                            // last SYNC bit is '1': level unchanged,
                            // and it counts as the first '1' for stuffing
                            ones <= 3'd1;
                            st   <= S_DATA;
                        end
                        else begin
                            lvl  <= ~lvl;
                            dp_o <= ~lvl;
                            dm_o <= lvl;
                        end
                        sync_i <= sync_i + 1'b1;
                    end

                    S_DATA: begin
                        if (ones == 3'd6) begin
                            // stuffed 0
                            lvl  <= ~lvl;
                            dp_o <= ~lvl;
                            dm_o <= lvl;
                            ones <= 3'd0;
                        end
                        else if (nbits == 4'd0 && last_loaded) begin
                            // end of payload -> EOP
                            dp_o  <= 1'b0;
                            dm_o  <= 1'b0;
                            eop_i <= 2'd0;
                            st    <= S_EOP;
                        end
                        else begin
                            if (nbits == 4'd0) begin
                                sh          <= {1'b0, tx_byte[7:1]};
                                nbits       <= 4'd7;
                                last_loaded <= tx_last;
                                tx_get      <= 1'b1;
                            end
                            else begin
                                sh    <= {1'b0, sh[7:1]};
                                nbits <= nbits - 1'b1;
                            end

                            if (bit_v)
                                ones <= ones + 1'b1;
                            else begin
                                lvl  <= ~lvl;
                                dp_o <= ~lvl;
                                dm_o <= lvl;
                                ones <= 3'd0;
                            end
                        end
                    end

                    S_EOP: begin
                        case (eop_i)
                            2'd0: eop_i <= 2'd1;              // 2nd SE0 bit time
                            2'd1: begin                        // J for one bit time
                                dp_o  <= 1'b1;
                                dm_o  <= 1'b0;
                                lvl   <= 1'b1;
                                eop_i <= 2'd2;
                            end
                            default: begin                     // release the bus
                                oe   <= 1'b0;
                                st   <= S_IDLE;
                                done <= 1'b1;
                            end
                        endcase
                    end

                    default: st <= S_IDLE;
                endcase
            end
        end
    end

endmodule
