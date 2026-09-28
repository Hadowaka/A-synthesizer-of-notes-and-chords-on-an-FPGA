`timescale 1ns/1ps

// ============================================================
// USB full-speed packet receiver, clk = 48 MHz
// ============================================================

module usb_rx (
    input  wire       clk,
    input  wire       rst,

    input  wire       dp_i,         // already synchronized by the parent
    input  wire       dm_i,

    output reg        rx_active     = 1'b0,
    output reg [7:0]  rx_byte       = 8'd0,
    output reg        rx_byte_valid = 1'b0,   // byte 0 = PID, byte 1.. = payload/CRC
    output reg        rx_done       = 1'b0,   // 1-clk pulse at EOP
    output reg [7:0]  rx_bytes      = 8'd0,   // byte count for this packet (valid at rx_done)
    output reg        rx_crc16_ok   = 1'b0    // valid at rx_done
);

    function [15:0] crc16_byte;
        input [15:0] c_in;
        input [7:0]  d;
        integer i;
        reg [15:0] c;
        reg        fb;
        begin
            c = c_in;
            for (i = 0; i < 8; i = i + 1) begin
                fb = c[0] ^ d[i];
                c  = c >> 1;
                if (fb) c = c ^ 16'hA001;
            end
            crc16_byte = c;
        end
    endfunction

    wire line_j   = dp_i && !dm_i;
    wire line_se0 = !dp_i && !dm_i;

    //  edge-resynchronized sample phase 
    reg       dp_prev = 1'b1;
    reg [1:0] phase   = 2'd0;
    wire      edge_now = (dp_i != dp_prev);
    always @(posedge clk) begin
        dp_prev <= dp_i;
        phase   <= edge_now ? 2'd0 : phase + 1'b1;
    end
    wire tick = (phase == 2'd2);

    // state 
    reg        active        = 1'b0;
    reg        prev_level    = 1'b1;
    reg [2:0]  ones          = 3'd0;
    reg [2:0]  bit_idx       = 3'd0;
    reg [7:0]  shreg         = 8'd0;
    reg        discarded_sync = 1'b0;
    reg [7:0]  byte_cnt      = 8'd0;
    reg [15:0] crc_reg       = 16'hFFFF;

    wire bit_val    = (dp_i == prev_level);        // NRZI: no transition = 1
    wire [7:0] shreg_next = {bit_val, shreg[7:1]};

    reg  se0_prev = 1'b0;
    always @(posedge clk) se0_prev <= line_se0;
    wire eop = line_se0 && se0_prev;

    always @(posedge clk) begin
        rx_byte_valid <= 1'b0;
        rx_done       <= 1'b0;

        if (rst) begin
            active         <= 1'b0;
            discarded_sync <= 1'b0;
            byte_cnt       <= 8'd0;
        end
        else if (!active) begin
            rx_active <= 1'b0;
            if (!line_j && !line_se0) begin
                // transition away from idle: start of SYNC
                active         <= 1'b1;
                rx_active      <= 1'b1;
                prev_level     <= 1'b1;      // idle level before this bit
                ones           <= 3'd0;
                bit_idx        <= 3'd0;
                shreg          <= 8'd0;
                discarded_sync <= 1'b0;
                byte_cnt       <= 8'd0;
                crc_reg        <= 16'hFFFF;
            end
        end
        else begin
            // reception in progress
            if (eop) begin
                // EOP
                active    <= 1'b0;
                rx_active <= 1'b0;
                rx_done   <= 1'b1;
                rx_bytes  <= byte_cnt;
                rx_crc16_ok <= (crc_reg == 16'hB001);
            end
            else if (tick) begin
                if (ones == 3'd6) begin
                    // stuffed bit: discard, do not shift in
                    ones <= 3'd0;
                    prev_level <= dp_i;
                end
                else begin
                    shreg      <= shreg_next;
                    ones       <= bit_val ? (ones + 1'b1) : 3'd0;
                    prev_level <= dp_i;

                    if (bit_idx == 3'd7) begin
                        bit_idx <= 3'd0;
                        if (!discarded_sync)
                            discarded_sync <= 1'b1;      // this byte was 0x80, drop it
                        else begin
                            rx_byte       <= shreg_next;
                            rx_byte_valid <= 1'b1;
                            if (byte_cnt != 8'd0)
                                crc_reg <= crc16_byte(crc_reg, shreg_next);
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                    else
                        bit_idx <= bit_idx + 1'b1;
                end
            end
        end
    end

endmodule
