module top_synth(
    input wire clk,              // 27 МГц
    input wire [13:0] key,       // кнопки: key[0]=C4, key[1]=D4 ... key[13]=B5
    output wire audio            // пин 73
);

    // Параметры
    localparam NUM_KEYS = 14;
    localparam DECAY_DIV = 18'd131072; // 2^17, затухание ~2.5 с

    // Массив приращений частоты (25 бит, фактически 24 значащих)
    wire [23:0] note_step [0:NUM_KEYS-1];
    assign note_step[0]  = 24'd163;   // C4
    assign note_step[1]  = 24'd183;   // D4
    assign note_step[2]  = 24'd205;   // E4
    assign note_step[3]  = 24'd217;   // F4
    assign note_step[4]  = 24'd244;   // G4
    assign note_step[5]  = 24'd273;   // A4
    assign note_step[6]  = 24'd307;   // B4
    assign note_step[7]  = 24'd325;   // C5
    assign note_step[8]  = 24'd365;   // D5
    assign note_step[9]  = 24'd410;   // E5
    assign note_step[10] = 24'd434;   // F5
    assign note_step[11] = 24'd487;   // G5
    assign note_step[12] = 24'd547;   // A5
    assign note_step[13] = 24'd614;   // B5

    // Синхронизация кнопок и детектор нажатия
    reg [NUM_KEYS-1:0] key_sync1, key_sync2, key_prev;
    always @(posedge clk) begin
        key_sync1 <= key;
        key_sync2 <= key_sync1;
        key_prev  <= key_sync2;
    end
    wire [NUM_KEYS-1:0] key_press;  // импульс длительностью 1 такт при нажатии
    genvar i;
    generate
        for (i = 0; i < NUM_KEYS; i = i + 1) begin
            assign key_press[i] = ~key_sync2[i] & key_prev[i];  // переход 1->0
        end
    endgenerate

    // Замедление для огибающей для огибающей
    reg [17:0] decay_cnt;
    wire decay_tick;
    always @(posedge clk) begin
        if (decay_cnt == DECAY_DIV - 1)
            decay_cnt <= 0;
        else
            decay_cnt <= decay_cnt + 1;
    end
    assign decay_tick = (decay_cnt == 0);

    // Звук
  wire signed [10:0] voice_out [0:NUM_KEYS-1]; // достаточно для +-255

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

    // Суммирование звука
    wire signed [15:0] sum_all;
    assign sum_all = voice_out[0] + voice_out[1] + voice_out[2] + voice_out[3] +
                     voice_out[4] + voice_out[5] + voice_out[6] + voice_out[7] +
                     voice_out[8] + voice_out[9] + voice_out[10] + voice_out[11] +
                     voice_out[12] + voice_out[13];

    // Усредняем до диапазона +-255
    wire signed [10:0] avg = sum_all / NUM_KEYS;   // [-255 .. 255]

    // Преобразуем 
    wire [8:0] pwm_level = avg + 9'd255;

    // 9-битный ШИМ-генератор
    reg [8:0] pwm_counter;
    always @(posedge clk) pwm_counter <= pwm_counter + 1;
    assign audio = (pwm_level > pwm_counter) ? 1'b1 : 1'b0;

endmodule


// Модуль одного звука
module voice #(parameter STEP_BITS = 24) (
    input wire clk,
    input wire press,            // импульс нажатия
    input wire decay_tick,       // разрешение уменьшения огибающей
    input wire [STEP_BITS-1:0] note_step,
    output wire signed [10:0] audio_out  // -255..255
);
    reg [STEP_BITS-1:0] phase;
    reg [7:0] envelope;          // 0..255

    always @(posedge clk) begin
        if (press) begin
            phase    <= 0;
            envelope <= 8'd255;
        end else begin
            if (decay_tick && envelope > 0)
                envelope <= envelope - 1;
            phase <= phase + note_step;
        end
    end

    // выходной знаковый сигнал: фаза[старший бит] определяет знак
    assign audio_out = phase[STEP_BITS-1] ? -{3'd0, envelope} : {3'd0, envelope};
endmodule
