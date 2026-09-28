`timescale 1ns/1ps

// ============================================================
// Top level, Tang Nano 20K
//
// key[] crosses 48 -> 27 MHz; top_synth already double-registers
// it (key_sync1/key_sync2), and each bit is an independent slow
// level, so no further CDC logic is needed.
//
// LEDs (active low on Tang Nano 20K):
//   led[0]  on = keyboard enumerated (configured)
//   led[1]  flashes on every note on/off received
//   led[2]  on while any key is held
//   led[3]  on = D+ idles high (a full-speed device is attached)
//   led[4]  on = host is in reset/enumeration (stuck here = USB problem)
//   led[5]  blinks ~1.4 Hz = 48 MHz PLL is running
// ============================================================

module top (
    input  wire       clk27,
    inout  wire       usb_dp,     // pin 41
    inout  wire       usb_dm,     // pin 42
    output wire       audio,
    output wire [5:0] led
);

    // 48 MHz 
    wire clk48, pll_lock;
    usb_pll u_pll (.clk_in(clk27), .clk_out(clk48), .lock(pll_lock));

    // reset held until the PLL is locked, released synchronously
    reg [3:0] rst_sr = 4'hF;
    always @(posedge clk48 or negedge pll_lock)
        if (!pll_lock) rst_sr <= 4'hF;
        else           rst_sr <= {rst_sr[2:0], 1'b0};
    wire rst48 = rst_sr[3];

    // USB MIDI -> keys
    wire [24:0] key;
    wire        configured, midi_event;
    wire [5:0]  dbg_state;

    usb_midi_keys u_usb (
        .clk48(clk48), .rst(rst48),
        .usb_dp(usb_dp), .usb_dm(usb_dm),
        .key(key), .configured(configured),
        .midi_event(midi_event), .dbg_state(dbg_state)
    );

    // synth (27 MHz)
    top_synth u_synth (.clk(clk27), .key(key), .audio(audio));

    // debug LEDs
    reg [22:0] act_cnt = 23'd0;           // ~175 ms flash
    always @(posedge clk48)
        if (midi_event)          act_cnt <= {23{1'b1}};
        else if (act_cnt != 0)   act_cnt <= act_cnt - 1'b1;

    reg [24:0] hb = 25'd0;
    always @(posedge clk48) hb <= hb + 1'b1;

    reg [1:0] dp_sync = 2'b00;
    always @(posedge clk48) dp_sync <= {dp_sync[0], usb_dp};

    wire enumerating = (dbg_state != 6'd0) && !configured;

    assign led[0] = ~configured;
    assign led[1] = ~(act_cnt != 0);
    assign led[2] = ~(~&key);
    assign led[3] = ~dp_sync[1];
    assign led[4] = ~enumerating;
    assign led[5] = ~hb[24];

endmodule
