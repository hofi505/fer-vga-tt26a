/*
 * FER Logo (bouncing) + Gaudeamus Igitur (Brahms) audio
 * SPDX-License-Identifier: Apache-2.0
 * Logo display powered by Uri Shaked (c) 2024 Tiny Tapeout LTD, Apache-2.0
 * Audio: soprano melody only, 1-bit square wave (no bass)
 * Needs in playground: fer_rom.v (FER logo, 128x64) + palette.v
 */
`default_nettype none

`define COLOR_WHITE 3'd7

module tt_um_fer_logo_music_vga  (
  
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  parameter LOGO_SIZE     = 128;
  parameter DISPLAY_WIDTH  = 640;
  parameter DISPLAY_HEIGHT = 480;

  // ── VGA signals ────────────────────────────────────────────────
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  reg  [1:0] R, G, B;

  wire cfg_tile  = ui_in[0];
  wire btn_music = ui_in[1];   // play / pause / stop the music
  wire btn_left  = ui_in[2];
  wire btn_right = ui_in[3];
  wire btn_up    = ui_in[4];
  wire btn_down  = ui_in[5];

  // ── Audio output on uio, RGB on uo ────────────────────────────
  wire sound;
  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = {sound, 7'b0};
  assign uio_oe  = 8'hff;

  wire _unused_ok = &{ena, ui_in[7:6], uio_in};

  // ── HVSync ────────────────────────────────────────────────────
  hvsync_generator vga_sync_gen (
      .clk(clk), .reset(~rst_n),
      .hsync(hsync), .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x), .vpos(pix_y)
  );

  // ── Tick signals (shared with audio) ──────────────────────────
  wire frame_tick = (pix_x == 0) && (pix_y == 0);  // ~60 Hz
  wire line_tick  = (pix_x == 0);                   // ~31.5 kHz

  // ══════════════════════════════════════════════════════════════
  //  MUSIC TRANSPORT CONTROL  (button ui_in[1])
  //  Each clean press advances:  STOPPED -> PLAYING -> PAUSED -> STOPPED ...
  //    press 1 = play (from start), press 2 = pause, press 3 = stop,
  //    press 4 = play from start again.
  //  ui_in[1] is synchronized + DEBOUNCED so a bouncy switch advances once.
  // ══════════════════════════════════════════════════════════════
  localparam [17:0] DEBOUNCE_MAX = 18'd250000;  // ~10 ms @ 25.175 MHz pixel clock
  reg        m_s1, m_s2;        // 2-FF synchronizer for async input
  reg        m_db, m_db_prev;   // debounced level + delayed copy (edge detect)
  reg [17:0] m_cnt;             // how long the input held a new level
  reg [1:0]  music_state;       // 0=STOPPED, 1=PLAYING, 2=PAUSED
  always @(posedge clk) begin
    if (~rst_n) begin
      m_s1 <= 1'b0; m_s2 <= 1'b0; m_db <= 1'b0; m_db_prev <= 1'b0; m_cnt <= 18'd0;
      music_state <= 2'd0;                 // STOPPED (silent until first press)
    end else begin
      m_s1 <= btn_music;
      m_s2 <= m_s1;
      if (m_s2 == m_db)                 m_cnt <= 18'd0;
      else if (m_cnt == DEBOUNCE_MAX) begin m_db <= m_s2; m_cnt <= 18'd0; end
      else                              m_cnt <= m_cnt + 1'b1;
      m_db_prev <= m_db;
      if (m_db & ~m_db_prev)                // exactly one rising edge per press
        music_state <= (music_state == 2'd2) ? 2'd0 : music_state + 2'd1;
    end
  end
  wire playing = (music_state == 2'd1);
  wire stopped = (music_state == 2'd0);
  // PAUSED (music_state == 2): note pointer & oscillator freeze, output muted.

  // ══════════════════════════════════════════════════════════════
  //  GAUDEAMUS AUDIO
  // ══════════════════════════════════════════════════════════════
  reg [9:0] rom_per [0:111];
  reg [9:0] rom_dur [0:111];
  reg [6:0] ptr;
  reg [9:0] tnote;
  wire [9:0] cur_per = rom_per[ptr];

  // note sequencer: STOPPED -> rewind to start, PAUSED -> hold, PLAYING -> advance
  always @(posedge clk) begin
    if (~rst_n)       begin ptr <= 0; tnote <= 0; end
    else if (stopped) begin ptr <= 0; tnote <= 0; end
    else if (playing && frame_tick) begin
      if (tnote + 1 >= rom_dur[ptr]) begin
        tnote <= 0; ptr <= (ptr == 111) ? 0 : ptr + 1'b1;
      end else tnote <= tnote + 1'b1;
    end
  end

  // square-wave oscillator: STOPPED -> reset, PAUSED -> hold, PLAYING -> run
  reg [9:0] cnt; reg wave;
  always @(posedge clk) begin
    if (~rst_n)       begin cnt <= 0; wave <= 0; end
    else if (stopped) begin cnt <= 0; wave <= 0; end
    else if (playing && line_tick) begin
      if (cur_per == 0) begin cnt <= 0; wave <= 0; end
      else if (cnt + 1 >= cur_per) begin cnt <= 0; wave <= ~wave; end
      else cnt <= cnt + 1'b1;
    end
  end
  assign sound = playing ? wave : 1'b0;   // silent while paused or stopped

  initial begin
    rom_per[0] = 10'd30; rom_dur[0] = 10'd40;
    rom_per[1] = 10'd40; rom_dur[1] = 10'd11;
    rom_per[2] = 10'd0; rom_dur[2] = 10'd2;
    rom_per[3] = 10'd40; rom_dur[3] = 10'd53;
    rom_per[4] = 10'd30; rom_dur[4] = 10'd53;
    rom_per[5] = 10'd36; rom_dur[5] = 10'd24;
    rom_per[6] = 10'd0; rom_dur[6] = 10'd2;
    rom_per[7] = 10'd36; rom_dur[7] = 10'd24;
    rom_per[8] = 10'd0; rom_dur[8] = 10'd2;
    rom_per[9] = 10'd36; rom_dur[9] = 10'd106;
    rom_per[10] = 10'd32; rom_dur[10] = 10'd26;
    rom_per[11] = 10'd30; rom_dur[11] = 10'd26;
    rom_per[12] = 10'd27; rom_dur[12] = 10'd53;
    rom_per[13] = 10'd32; rom_dur[13] = 10'd53;
    rom_per[14] = 10'd30; rom_dur[14] = 10'd26;
    rom_per[15] = 10'd24; rom_dur[15] = 10'd26;
    rom_per[16] = 10'd30; rom_dur[16] = 10'd104;
    rom_per[17] = 10'd0; rom_dur[17] = 10'd2;
    rom_per[18] = 10'd30; rom_dur[18] = 10'd40;
    rom_per[19] = 10'd40; rom_dur[19] = 10'd11;
    rom_per[20] = 10'd0; rom_dur[20] = 10'd2;
    rom_per[21] = 10'd40; rom_dur[21] = 10'd53;
    rom_per[22] = 10'd30; rom_dur[22] = 10'd53;
    rom_per[23] = 10'd36; rom_dur[23] = 10'd24;
    rom_per[24] = 10'd0; rom_dur[24] = 10'd2;
    rom_per[25] = 10'd36; rom_dur[25] = 10'd24;
    rom_per[26] = 10'd0; rom_dur[26] = 10'd2;
    rom_per[27] = 10'd36; rom_dur[27] = 10'd106;
    rom_per[28] = 10'd32; rom_dur[28] = 10'd26;
    rom_per[29] = 10'd30; rom_dur[29] = 10'd26;
    rom_per[30] = 10'd27; rom_dur[30] = 10'd53;
    rom_per[31] = 10'd32; rom_dur[31] = 10'd53;
    rom_per[32] = 10'd30; rom_dur[32] = 10'd26;
    rom_per[33] = 10'd24; rom_dur[33] = 10'd26;
    rom_per[34] = 10'd30; rom_dur[34] = 10'd51;
    rom_per[35] = 10'd0; rom_dur[35] = 10'd2;
    rom_per[36] = 10'd30; rom_dur[36] = 10'd13;
    rom_per[37] = 10'd27; rom_dur[37] = 10'd13;
    rom_per[38] = 10'd24; rom_dur[38] = 10'd13;
    rom_per[39] = 10'd21; rom_dur[39] = 10'd13;
    rom_per[40] = 10'd20; rom_dur[40] = 10'd26;
    rom_per[41] = 10'd21; rom_dur[41] = 10'd13;
    rom_per[42] = 10'd24; rom_dur[42] = 10'd13;
    rom_per[43] = 10'd27; rom_dur[43] = 10'd51;
    rom_per[44] = 10'd0; rom_dur[44] = 10'd2;
    rom_per[45] = 10'd27; rom_dur[45] = 10'd53;
    rom_per[46] = 10'd24; rom_dur[46] = 10'd26;
    rom_per[47] = 10'd30; rom_dur[47] = 10'd26;
    rom_per[48] = 10'd27; rom_dur[48] = 10'd51;
    rom_per[49] = 10'd0; rom_dur[49] = 10'd2;
    rom_per[50] = 10'd27; rom_dur[50] = 10'd53;
    rom_per[51] = 10'd32; rom_dur[51] = 10'd26;
    rom_per[52] = 10'd30; rom_dur[52] = 10'd26;
    rom_per[53] = 10'd27; rom_dur[53] = 10'd51;
    rom_per[54] = 10'd0; rom_dur[54] = 10'd2;
    rom_per[55] = 10'd27; rom_dur[55] = 10'd53;
    rom_per[56] = 10'd24; rom_dur[56] = 10'd26;
    rom_per[57] = 10'd30; rom_dur[57] = 10'd26;
    rom_per[58] = 10'd27; rom_dur[58] = 10'd51;
    rom_per[59] = 10'd0; rom_dur[59] = 10'd2;
    rom_per[60] = 10'd27; rom_dur[60] = 10'd53;
    rom_per[61] = 10'd30; rom_dur[61] = 10'd26;
    rom_per[62] = 10'd32; rom_dur[62] = 10'd26;
    rom_per[63] = 10'd36; rom_dur[63] = 10'd26;
    rom_per[64] = 10'd23; rom_dur[64] = 10'd26;
    rom_per[65] = 10'd24; rom_dur[65] = 10'd26;
    rom_per[66] = 10'd27; rom_dur[66] = 10'd26;
    rom_per[67] = 10'd24; rom_dur[67] = 10'd53;
    rom_per[68] = 10'd27; rom_dur[68] = 10'd53;
    rom_per[69] = 10'd30; rom_dur[69] = 10'd51;
    rom_per[70] = 10'd0; rom_dur[70] = 10'd2;
    rom_per[71] = 10'd30; rom_dur[71] = 10'd26;
    rom_per[72] = 10'd32; rom_dur[72] = 10'd26;
    rom_per[73] = 10'd36; rom_dur[73] = 10'd26;
    rom_per[74] = 10'd18; rom_dur[74] = 10'd26;
    rom_per[75] = 10'd23; rom_dur[75] = 10'd26;
    rom_per[76] = 10'd27; rom_dur[76] = 10'd26;
    rom_per[77] = 10'd20; rom_dur[77] = 10'd109;
    rom_per[78] = 10'd0; rom_dur[78] = 10'd2;
    rom_per[79] = 10'd20; rom_dur[79] = 10'd55;
    rom_per[80] = 10'd30; rom_dur[80] = 10'd14;
    rom_per[81] = 10'd0; rom_dur[81] = 10'd42;
    rom_per[82] = 10'd20; rom_dur[82] = 10'd42;
    rom_per[83] = 10'd30; rom_dur[83] = 10'd12;
    rom_per[84] = 10'd0; rom_dur[84] = 10'd2;
    rom_per[85] = 10'd30; rom_dur[85] = 10'd56;
    rom_per[86] = 10'd20; rom_dur[86] = 10'd42;
    rom_per[87] = 10'd30; rom_dur[87] = 10'd12;
    rom_per[88] = 10'd0; rom_dur[88] = 10'd2;
    rom_per[89] = 10'd30; rom_dur[89] = 10'd54;
    rom_per[90] = 10'd0; rom_dur[90] = 10'd2;
    rom_per[91] = 10'd30; rom_dur[91] = 10'd54;
    rom_per[92] = 10'd0; rom_dur[92] = 10'd2;
    rom_per[93] = 10'd30; rom_dur[93] = 10'd55;
    rom_per[94] = 10'd0; rom_dur[94] = 10'd2;
    rom_per[95] = 10'd30; rom_dur[95] = 10'd55;
    rom_per[96] = 10'd0; rom_dur[96] = 10'd2;
    rom_per[97] = 10'd30; rom_dur[97] = 10'd57;
    rom_per[98] = 10'd18; rom_dur[98] = 10'd57;
    rom_per[99] = 10'd15; rom_dur[99] = 10'd14;
    rom_per[100] = 10'd16; rom_dur[100] = 10'd14;
    rom_per[101] = 10'd18; rom_dur[101] = 10'd14;
    rom_per[102] = 10'd20; rom_dur[102] = 10'd14;
    rom_per[103] = 10'd18; rom_dur[103] = 10'd57;
    rom_per[104] = 10'd12; rom_dur[104] = 10'd108;
    rom_per[105] = 10'd0; rom_dur[105] = 10'd6;
    rom_per[106] = 10'd15; rom_dur[106] = 10'd14;
    rom_per[107] = 10'd0; rom_dur[107] = 10'd100;
    rom_per[108] = 10'd15; rom_dur[108] = 10'd55;
    rom_per[109] = 10'd0; rom_dur[109] = 10'd2;
    rom_per[110] = 10'd15; rom_dur[110] = 10'd57;
    rom_per[111] = 10'd30; rom_dur[111] = 10'd163;
  end

  // ══════════════════════════════════════════════════════════════
  //  FER LOGO (bouncing)
  // ══════════════════════════════════════════════════════════════
  reg [9:0] logo_left, logo_top;
  reg dir_x, dir_y;
  reg [2:0] color_index;

  wire pixel_value;
  wire [5:0] color;

  wire [9:0] lx = pix_x - logo_left;
  wire [9:0] ly = pix_y - logo_top;
  wire logo_pixels = cfg_tile || (lx[9:7] == 0 && ly[9:7] == 0);

  fer_rom rom_inst (
      .x(lx[6:0]),
      .y(ly[6:0]),
      .pixel(pixel_value)
  );

  palette palette_inst (
      .color_index(color_index),
      .rrggbb(color)
  );

  // RGB output
  always @(posedge clk) begin
    if (~rst_n) begin R <= 0; G <= 0; B <= 0; end
    else begin
      R <= 0; G <= 0; B <= 0;
      if (video_active && logo_pixels) begin
        R <= pixel_value ? color[5:4] : 0;
        G <= pixel_value ? color[3:2] : 0;
        B <= pixel_value ? color[1:0] : 0;
      end
    end
  end

  // Bouncing logic
  localparam X_MAX = DISPLAY_WIDTH  - LOGO_SIZE;  // 512
  localparam Y_MAX = DISPLAY_HEIGHT - LOGO_SIZE;  // 352

  reg [9:0] prev_y;
  reg       bounced_last;  // sprjecava visestruku promjenu boje na istom rubu

  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left    <= 200;
      logo_top     <= 200;
      dir_x        <= 1;
      dir_y        <= 0;
      color_index  <= 0;
      prev_y       <= 0;
      bounced_last <= 0;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != 0) begin

        if (btn_left | btn_right | btn_up | btn_down) begin
          if      (btn_left  && logo_left > 0)     logo_left <= logo_left - 1;
          else if (btn_right && logo_left < X_MAX) logo_left <= logo_left + 1;
          if      (btn_up    && logo_top  > 0)     logo_top  <= logo_top  - 1;
          else if (btn_down  && logo_top  < Y_MAX) logo_top  <= logo_top  + 1;
          bounced_last <= 0;

        end else begin
          // Pomak uz hard clamp
          logo_left <= dir_x ? (logo_left < X_MAX ? logo_left + 1 : logo_left)
                             : (logo_left > 0     ? logo_left - 1 : logo_left);
          logo_top  <= dir_y ? (logo_top  < Y_MAX ? logo_top  + 1 : logo_top)
                             : (logo_top  > 0     ? logo_top  - 1 : logo_top);

          // Detekcija ruba - okreni smjer
          if (logo_left <= 1)          dir_x <= 1;
          if (logo_left >= X_MAX - 1)  dir_x <= 0;
          if (logo_top  <= 1)          dir_y <= 1;
          if (logo_top  >= Y_MAX - 1)  dir_y <= 0;

          // Promjena boje samo jednom pri odbijanju (edge detect)
          if (logo_left <= 1 || logo_left >= X_MAX-1 ||
              logo_top  <= 1 || logo_top  >= Y_MAX-1) begin
            if (!bounced_last) begin
              color_index  <= color_index + 1;
              bounced_last <= 1;
            end
          end else begin
            bounced_last <= 0;
          end
        end

      end
    end
  end

endmodule