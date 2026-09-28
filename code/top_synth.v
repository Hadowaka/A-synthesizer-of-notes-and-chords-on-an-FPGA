`timescale 1ns/1ps

// ============================================================
// 25-voice synth, Tang Nano 20K (clk = 27 MHz)
//
// key: 0 = pressed, 1 = released
// key[i] = MIDI note 48+i  (C3 .. C5, chromatic)
//
// step = f * 2^24 / 27e6
// ============================================================
module top_synth(
    input  wire        clk,
    input  wire [24:0] key,
    output wire        audio
);

    localparam NUM_KEYS  = 25;
    localparam DECAY_DIV = 18'd131072;

    wire [23:0] note_step [0:NUM_KEYS-1];
    assign note_step[0]  = 24'd81;    // C3
    assign note_step[1]  = 24'd86;    // C#3
    assign note_step[2]  = 24'd91;    // D3
    assign note_step[3]  = 24'd97;    // D#3
    assign note_step[4]  = 24'd102;   // E3
    assign note_step[5]  = 24'd109;   // F3
    assign note_step[6]  = 24'd115;   // F#3
    assign note_step[7]  = 24'd122;   // G3
    assign note_step[8]  = 24'd129;   // G#3
    assign note_step[9]  = 24'd137;   // A3
    assign note_step[10] = 24'd145;   // A#3
    assign note_step[11] = 24'd153;   // B3
    assign note_step[12] = 24'd163;   // C4
    assign note_step[13] = 24'd172;   // C#4
    assign note_step[14] = 24'd182;   // D4
    assign note_step[15] = 24'd193;   // D#4
    assign note_step[16] = 24'd205;   // E4
    assign note_step[17] = 24'd217;   // F4
    assign note_step[18] = 24'd230;   // F#4
    assign note_step[19] = 24'd244;   // G4
    assign note_step[20] = 24'd258;   // G#4
    assign note_step[21] = 24'd273;   // A4
    assign note_step[22] = 24'd290;   // A#4
    assign note_step[23] = 24'd307;   // B4
    assign note_step[24] = 24'd325;   // C5

    // Key synchronizer / press detector
    reg [NUM_KEYS-1:0] key_sync1 = {NUM_KEYS{1'b1}};
    reg [NUM_KEYS-1:0] key_sync2 = {NUM_KEYS{1'b1}};
    reg [NUM_KEYS-1:0] key_prev  = {NUM_KEYS{1'b1}};
    always @(posedge clk) begin
        key_sync1 <= key;
        key_sync2 <= key_sync1;
        key_prev  <= key_sync2;
    end
    wire [NUM_KEYS-1:0] key_press = ~key_sync2 & key_prev;

    // Envelope slow-down
    reg [17:0] decay_cnt = 18'd0;
    always @(posedge clk) begin
        if (decay_cnt == DECAY_DIV - 1)
            decay_cnt <= 18'd0;
        else
            decay_cnt <= decay_cnt + 1'b1;
    end
    wire decay_tick = (decay_cnt == 18'd0);

    // Voices
    wire signed [10:0] voice_out [0:NUM_KEYS-1];
    genvar i;
    generate
        for (i = 0; i < NUM_KEYS; i = i + 1) begin : voice_gen
            voice #(.STEP_BITS(24)) voice_i (
                .clk(clk),
                .press(key_press[i]),
                .decay_tick(decay_tick),
                .note_step(note_step[i]),
                .audio_out(voice_out[i])
            );
        end
    endgenerate

    // Mixer: 5 groups of 5 voices, registered then a second registered stage.
    wire signed [13:0] gsum [0:4];
    genvar g;
    generate
        for (g = 0; g < 5; g = g + 1) begin : grp
            reg signed [13:0] s_q = 14'sd0;
            always @(posedge clk)
                s_q <= voice_out[5*g]   + voice_out[5*g+1] + voice_out[5*g+2] +
                       voice_out[5*g+3] + voice_out[5*g+4];
            assign gsum[g] = s_q;
        end
    endgenerate

    reg signed [15:0] sum_q = 16'sd0;
    always @(posedge clk)
        sum_q <= gsum[0] + gsum[1] + gsum[2] + gsum[3] + gsum[4];

    // Gain: sum/8 with clipping to +-255 (dividing by 25 made one note
    // almost inaudible; ~8 simultaneous full-level voices reach the limit).
    wire signed [15:0] scaled = sum_q >>> 3;
    wire signed [10:0] avg =
        (scaled >  16'sd255) ?  11'sd255 :
        (scaled < -16'sd255) ? -11'sd255 :
                                scaled[10:0];

    wire [8:0] pwm_level = avg + 9'd255;

    reg [8:0] pwm_counter = 9'd0;
    always @(posedge clk) pwm_counter <= pwm_counter + 1'b1;

    assign audio = (pwm_level > pwm_counter);

endmodule


module voice #(parameter STEP_BITS = 24) (
    input  wire                 clk,
    input  wire                 press,
    input  wire                 decay_tick,
    input  wire [STEP_BITS-1:0] note_step,
    output wire signed [10:0]   audio_out
);
    reg [STEP_BITS-1:0] phase    = {STEP_BITS{1'b0}};
    reg [7:0]           envelope = 8'd0;

    always @(posedge clk) begin
        if (press) begin
            phase    <= {STEP_BITS{1'b0}};
            envelope <= 8'd255;
        end
        else begin
            if (decay_tick && envelope != 8'd0)
                envelope <= envelope - 1'b1;
            phase <= phase + note_step;
        end
    end

    wire signed [10:0] env_s = {3'd0, envelope};
    assign audio_out = phase[STEP_BITS-1] ? -env_s : env_s;

endmodule
