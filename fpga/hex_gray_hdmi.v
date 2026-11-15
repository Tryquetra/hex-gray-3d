`timescale 1ns/1ps

// TMDS 8b/10b encoder per DVI 1.0 specification.
module hex_gray_tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire [1:0] ctrl,
    input  wire       de,
    output reg  [9:0] dout
);
    wire [3:0] n1_d = data[0] + data[1] + data[2] + data[3] +
                      data[4] + data[5] + data[6] + data[7];
    wire use_xnor = (n1_d > 4'd4) || ((n1_d == 4'd4) && (data[0] == 1'b0));

    wire [8:0] q_m;
    assign q_m[0] = data[0];
    assign q_m[1] = use_xnor ? (q_m[0] ~^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = use_xnor ? (q_m[1] ~^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = use_xnor ? (q_m[2] ~^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = use_xnor ? (q_m[3] ~^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = use_xnor ? (q_m[4] ~^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = use_xnor ? (q_m[5] ~^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = use_xnor ? (q_m[6] ~^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = ~use_xnor;

    wire [3:0] n1_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                       q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire signed [4:0] balance_qm = $signed({1'b0, n1_qm}) - 5'sd4;

    reg signed [4:0] dc_bias = 5'sd0;

    always @(posedge clk) begin
        if (rst) begin
            dc_bias <= 5'sd0;
            dout    <= 10'b1101010100;
        end else if (!de) begin
            dc_bias <= 5'sd0;
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                2'b11: dout <= 10'b1010101011;
            endcase
        end else begin
            if ((dc_bias == 5'sd0) || (n1_qm == 4'd4)) begin
                dout[9]   <= ~q_m[8];
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8] == 1'b0)
                    dc_bias <= dc_bias - (balance_qm <<< 1);
                else
                    dc_bias <= dc_bias + (balance_qm <<< 1);
            end else if (((dc_bias > 5'sd0) && (n1_qm > 4'd4)) ||
                         ((dc_bias < 5'sd0) && (n1_qm < 4'd4))) begin
                dout[9]   <= 1'b1;
                dout[8]   <= q_m[8];
                dout[7:0] <= ~q_m[7:0];
                dc_bias   <= dc_bias + (q_m[8] ? 5'sd2 : 5'sd0) - (balance_qm <<< 1);
            end else begin
                dout[9]   <= 1'b0;
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[7:0];
                dc_bias   <= dc_bias - (q_m[8] ? 5'sd0 : 5'sd2) + (balance_qm <<< 1);
            end
        end
    end
endmodule

// Procedural 640x480@60Hz HDMI generator for Hexagonal Gray Code (0 BRAM).
// Left:  2D oblique projection of Q3 hypercube highlighting the 6-cycle Hamiltonian ring.
// Mid:   3-wire bus (b[2], b[1], b[0]) glowing gold on changed wire(s) in last_delta.
// Right: 7-cell Tryte6 rosette using zero-overlap shift-only Voronoi selector + Sentinela badge.
module hex_gray_hdmi #(
    parameter integer SIM_ONLY = 0
) (
    input  wire       clk_pix,
    input  wire       clk_tmds,
    input  wire       rst_pix,
    input  wire [2:0] gray_state_sys,
    input  wire [2:0] last_delta_sys,
    input  wire       auto_orbit_sys,
    input  wire       activity_sys,
    output wire       O_tmds_clk_p,
    output wire       O_tmds_clk_n,
    output wire [2:0] O_tmds_data_p,
    output wire [2:0] O_tmds_data_n
);
    // 640x480 @ 60Hz timing (800x525 total)
    localparam [9:0] H_ACTIVE = 10'd640;
    localparam [9:0] H_FP     = 10'd16;
    localparam [9:0] H_SYNC   = 10'd96;
    localparam [9:0] H_TOTAL  = 10'd800;

    localparam [9:0] V_ACTIVE = 10'd480;
    localparam [9:0] V_FP     = 10'd10;
    localparam [9:0] V_SYNC   = 10'd2;
    localparam [9:0] V_TOTAL  = 10'd525;

    reg [9:0] hx = 10'd0;
    reg [9:0] vy = 10'd0;
    always @(posedge clk_pix) begin
        if (rst_pix) begin
            hx <= 10'd0;
            vy <= 10'd0;
        end else if (hx == H_TOTAL - 10'd1) begin
            hx <= 10'd0;
            if (vy == V_TOTAL - 10'd1)
                vy <= 10'd0;
            else
                vy <= vy + 10'd1;
        end else begin
            hx <= hx + 10'd1;
        end
    end

    wire raw_de = (hx < H_ACTIVE) && (vy < V_ACTIVE);
    wire raw_hs = (hx >= (H_ACTIVE + H_FP)) && (hx < (H_ACTIVE + H_FP + H_SYNC));
    wire raw_vs = (vy >= (V_ACTIVE + V_FP)) && (vy < (V_ACTIVE + V_FP + V_SYNC));

    // Synchronize system signals into clk_pix and latch at vblank
    reg [2:0] state_s1 = 3'b001, state_s2 = 3'b001, state_pix = 3'b001;
    reg [2:0] delta_s1 = 3'b000, delta_s2 = 3'b000, delta_pix = 3'b000;
    reg       orb_s1   = 1'b0,   orb_s2   = 1'b0,   orb_pix   = 1'b0;
    reg       act_s1   = 1'b0,   act_s2   = 1'b0,   act_pix   = 1'b0;

    always @(posedge clk_pix) begin
        state_s1 <= gray_state_sys;
        state_s2 <= state_s1;
        delta_s1 <= last_delta_sys;
        delta_s2 <= delta_s1;
        orb_s1   <= auto_orbit_sys;
        orb_s2   <= orb_s1;
        act_s1   <= activity_sys;
        act_s2   <= act_s1;
        if (vy == V_ACTIVE && hx == 10'd0) begin
            state_pix <= state_s2;
            delta_pix <= delta_s2;
            orb_pix   <= orb_s2;
            act_pix   <= act_s2;
        end
    end

    // Rosette geometry constants (Right panel center CX=475, CY=224, R=42)
    // Order:
    //  0: 3'b000 Centro    (475, 224)
    //  1: 3'b001 Ang 0     (553, 224)
    //  2: 3'b011 Ang 60    (514, 156)
    //  3: 3'b010 Ang 120   (436, 156)
    //  4: 3'b110 Ang 180   (397, 224)
    //  5: 3'b111 Ang 240   (436, 292)
    //  6: 3'b101 Ang 300   (514, 292)
    function [9:0] hex_cx;
        input [2:0] idx;
        begin
            case (idx)
                3'd0:    hex_cx = 10'd475;
                3'd1:    hex_cx = 10'd553;
                3'd2:    hex_cx = 10'd514;
                3'd3:    hex_cx = 10'd436;
                3'd4:    hex_cx = 10'd397;
                3'd5:    hex_cx = 10'd436;
                3'd6:    hex_cx = 10'd514;
                default: hex_cx = 10'd475;
            endcase
        end
    endfunction

    function [9:0] hex_cy;
        input [2:0] idx;
        begin
            case (idx)
                3'd0:    hex_cy = 10'd224;
                3'd1:    hex_cy = 10'd224;
                3'd2:    hex_cy = 10'd156;
                3'd3:    hex_cy = 10'd156;
                3'd4:    hex_cy = 10'd224;
                3'd5:    hex_cy = 10'd292;
                3'd6:    hex_cy = 10'd292;
                default: hex_cy = 10'd224;
            endcase
        end
    endfunction

    function [2:0] idx_to_gray;
        input [2:0] idx;
        begin
            case (idx)
                3'd0:    idx_to_gray = 3'b000;
                3'd1:    idx_to_gray = 3'b001;
                3'd2:    idx_to_gray = 3'b011;
                3'd3:    idx_to_gray = 3'b010;
                3'd4:    idx_to_gray = 3'b110;
                3'd5:    idx_to_gray = 3'b111;
                3'd6:    idx_to_gray = 3'b101;
                default: idx_to_gray = 3'b100;
            endcase
        end
    endfunction

    // Map active state to (q, r, s) balanced ternary sign encodings:
    // 2'b01 = 0, 2'b10 = +1, 2'b11 = -1
    reg [1:0] q_sign, r_sign, s_sign;
    always @(*) begin
        case (state_pix)
            3'b000: begin q_sign = 2'b01; r_sign = 2'b01; s_sign = 2'b01; end
            3'b001: begin q_sign = 2'b10; r_sign = 2'b01; s_sign = 2'b11; end
            3'b011: begin q_sign = 2'b01; r_sign = 2'b10; s_sign = 2'b11; end
            3'b010: begin q_sign = 2'b11; r_sign = 2'b10; s_sign = 2'b01; end
            3'b110: begin q_sign = 2'b11; r_sign = 2'b01; s_sign = 2'b10; end
            3'b111: begin q_sign = 2'b01; r_sign = 2'b11; s_sign = 2'b10; end
            3'b101: begin q_sign = 2'b10; r_sign = 2'b11; s_sign = 2'b01; end
            default: begin q_sign = 2'b00; r_sign = 2'b00; s_sign = 2'b00; end
        endcase
    end

    // Shift-only Voronoi distance helper: max(ax * 2, ay * 2 + ax)
    function [11:0] voronoi_score;
        input [9:0] ax;
        input [9:0] ay;
        reg [11:0] a;
        reg [11:0] b;
        begin
            a = {1'b0, ax, 1'b0};
            b = {1'b0, ay, 1'b0} + {2'b00, ax};
            voronoi_score = (a >= b) ? a : b;
        end
    endfunction

    // Stage 1 combinational Voronoi search across all 7 rosette cells
    reg [11:0] best_score;
    reg [2:0]  best_idx;
    reg signed [10:0] best_dx;
    reg signed [10:0] best_dy;
    integer k;
    reg [9:0] tmp_cx, tmp_cy, tmp_ax, tmp_ay;
    reg signed [10:0] tmp_dx, tmp_dy;
    reg [11:0] tmp_sc;

    always @(*) begin
        best_score = 12'd4095;
        best_idx   = 3'd0;
        best_dx    = 11'sd0;
        best_dy    = 11'sd0;
        for (k = 0; k < 7; k = k + 1) begin
            tmp_cx = hex_cx(k[2:0]);
            tmp_cy = hex_cy(k[2:0]);
            tmp_dx = $signed({1'b0, hx}) - $signed({1'b0, tmp_cx});
            tmp_dy = $signed({1'b0, vy}) - $signed({1'b0, tmp_cy});
            tmp_ax = tmp_dx[10] ? (~tmp_dx[9:0] + 10'd1) : tmp_dx[9:0];
            tmp_ay = tmp_dy[10] ? (~tmp_dy[9:0] + 10'd1) : tmp_dy[9:0];
            tmp_sc = voronoi_score(tmp_ax, tmp_ay);
            if (tmp_sc < best_score) begin
                best_score = tmp_sc;
                best_idx   = k[2:0];
                best_dx    = tmp_dx;
                best_dy    = tmp_dy;
            end
        end
    end

    // Stage 1 registers
    reg [9:0]         s1_hx = 10'd0, s1_vy = 10'd0;
    reg               s1_de = 1'b0, s1_hs = 1'b0, s1_vs = 1'b0;
    reg [2:0]         s1_hex_idx = 3'd0;
    reg signed [10:0] s1_hex_dx  = 11'sd0;
    reg signed [10:0] s1_hex_dy  = 11'sd0;

    always @(posedge clk_pix) begin
        s1_hx      <= hx;
        s1_vy      <= vy;
        s1_de      <= raw_de;
        s1_hs      <= raw_hs;
        s1_vs      <= raw_vs;
        s1_hex_idx <= best_idx;
        s1_hex_dx  <= best_dx;
        s1_hex_dy  <= best_dy;
    end

    // Stage 2: Exact pointy-top hexagon test on Stage-1 Voronoi owner
    wire [9:0] s1_hex_ax = s1_hex_dx[10] ? (~s1_hex_dx[9:0] + 10'd1) : s1_hex_dx[9:0];
    wire [9:0] s1_hex_ay = s1_hex_dy[10] ? (~s1_hex_dy[9:0] + 10'd1) : s1_hex_dy[9:0];
    wire [17:0] hex_m1   = {8'd0, s1_hex_ax} * 18'd74;
    wire [17:0] hex_m2   = ({8'd0, s1_hex_ay} * 18'd64) + ({8'd0, s1_hex_ax} * 18'd37);
    wire [17:0] hex_dist = (hex_m1 > hex_m2) ? hex_m1 : hex_m2;

    // R = 42 -> R * 64 = 2688, border 2496..2688
    wire in_hex_cell    = (s1_hx >= 10'd345) && (hex_dist <= 18'd2688);
    wire in_hex_border  = in_hex_cell && (hex_dist >= 18'd2496);
    wire [2:0] cell_code = idx_to_gray(s1_hex_idx);
    wire cell_is_active  = (cell_code == state_pix);

    // Sentinela (3'b100) corner octagonal/diamond badge at (578, 326), radius ~18
    wire signed [10:0] sent_dx = $signed({1'b0, s1_hx}) - 11'sd578;
    wire signed [10:0] sent_dy = $signed({1'b0, s1_vy}) - 11'sd326;
    wire [9:0] sent_ax = sent_dx[10] ? (~sent_dx[9:0] + 10'd1) : sent_dx[9:0];
    wire [9:0] sent_ay = sent_dy[10] ? (~sent_dy[9:0] + 10'd1) : sent_dy[9:0];
    wire [10:0] sent_l1 = {1'b0, sent_ax} + {1'b0, sent_ay};
    wire in_sent_badge  = (sent_l1 <= 11'd20) && (sent_ax <= 10'd15) && (sent_ay <= 10'd15);
    wire in_sent_ring   = in_sent_badge && ((sent_l1 >= 11'd17) || (sent_ax >= 10'd13) || (sent_ay >= 10'd13));
    wire in_sent_x      = (sent_l1 <= 11'd12) && ((sent_ax >= sent_ay ? sent_ax - sent_ay : sent_ay - sent_ax) <= 10'd2);

    // Glyph helper inside active/center cells
    wire glyph_plus_h = (s1_hex_ay <= 10'd2) && (s1_hex_ax <= 10'd11);
    wire glyph_plus_v = (s1_hex_ax <= 10'd2) && (s1_hex_ay <= 10'd11);
    wire glyph_ring   = ((s1_hex_ax <= 10'd8) && (s1_hex_ay <= 10'd8)) &&
                        ((s1_hex_ax >= 10'd6) || (s1_hex_ay >= 10'd6));

    // Left panel: Q3 Hypercube 2D projection around (155, 224)
    // Vertices (dx, dy) = (b2 ? +48 : -48) + (b0 ? +22 : -22), (b1 ? -48 : +48) + (b0 ? +22 : -22)
    // Back face (b0=0):
    //   000: ( 85, 250)   100: (181, 250) [Sentinel]
    //   010: ( 85, 154)   110: (181, 154)
    // Front face (b0=1):
    //   001: (129, 294)   101: (225, 294)
    //   011: (129, 202) -> wait: 224 - 48 + 22 = 198!
    // Let's verify exact arithmetic:
    //   y_back_top    (b1=1,b0=0) = 224 - 48 - 22 = 154
    //   y_back_bot    (b1=0,b0=0) = 224 + 48 - 22 = 250
    //   y_front_top   (b1=1,b0=1) = 224 - 48 + 22 = 198
    //   y_front_bot   (b1=0,b0=1) = 224 + 48 + 22 = 294
    //   x_back_left   (b2=0,b0=0) = 155 - 48 - 22 = 85
    //   x_back_right  (b2=1,b0=0) = 155 + 48 - 22 = 181
    //   x_front_left  (b2=0,b0=1) = 155 - 48 + 22 = 129
    //   x_front_right (b2=1,b0=1) = 155 + 48 + 22 = 225
    // Diagonal span is +44 in X and +44 in Y!

    function [9:0] q3_vx;
        input [2:0] code;
        begin
            q3_vx = 10'd155 + (code[2] ? 10'd48 : -10'd48) + (code[0] ? 10'd22 : -10'd22);
        end
    endfunction

    function [9:0] q3_vy;
        input [2:0] code;
        begin
            q3_vy = 10'd224 + (code[1] ? -10'd48 : 10'd48) + (code[0] ? 10'd22 : -10'd22);
        end
    endfunction

    // Active vertex highlight coordinates
    wire [9:0] act_vx = q3_vx(state_pix);
    wire [9:0] act_vy = q3_vy(state_pix);
    wire [9:0] act_ax = (s1_hx >= act_vx) ? (s1_hx - act_vx) : (act_vx - s1_hx);
    wire [9:0] act_ay = (s1_vy >= act_vy) ? (s1_vy - act_vy) : (act_vy - s1_vy);
    wire [10:0] act_l1 = {1'b0, act_ax} + {1'b0, act_ay};
    wire in_q3_active_halo = (act_l1 <= 11'd17) && (act_l1 >= 11'd13);

    // Check if pixel is inside any of the 8 Q3 vertices (diamond radius 9)
    reg in_q3_node;
    reg [2:0] q3_node_code;
    integer vi;
    reg [9:0] vdx, vdy;
    always @(*) begin
        in_q3_node   = 1'b0;
        q3_node_code = 3'd0;
        for (vi = 0; vi < 8; vi = vi + 1) begin
            vdx = (s1_hx >= q3_vx(vi[2:0])) ? (s1_hx - q3_vx(vi[2:0])) : (q3_vx(vi[2:0]) - s1_hx);
            vdy = (s1_vy >= q3_vy(vi[2:0])) ? (s1_vy - q3_vy(vi[2:0])) : (q3_vy(vi[2:0]) - s1_vy);
            if (({1'b0, vdx} + {1'b0, vdy}) <= 11'd9) begin
                in_q3_node   = 1'b1;
                q3_node_code = vi[2:0];
            end
        end
    end

    // 6-cycle Hamiltonian edges (thickened to +-2 px):
    //   e01: 001 <-> 011 : x=129, y in [198..294] (b1 flip)
    //   e12: 011 <-> 010 : y - x = 69, x in [85..129]  (b0 flip: 85->154, 129->198 -> y - x = 69)
    //   e23: 010 <-> 110 : y=154, x in [85..181]  (b2 flip)
    //   e34: 110 <-> 111 : y - x = -27, x in [181..225] (b0 flip: 181->154, 225->198 -> x - y = 27)
    //   e45: 111 <-> 101 : x=225, y in [198..294] (b1 flip)
    //   e50: 101 <-> 001 : y=294, x in [129..225] (b2 flip)
    wire diag_diff_011_010 = ((s1_vy - s1_hx) >= 10'd67) && ((s1_vy - s1_hx) <= 10'd71);
    wire diag_diff_110_111 = ((s1_hx - s1_vy) >= 10'd25) && ((s1_hx - s1_vy) <= 10'd29);

    wire in_ring_edge =
        ((s1_hx >= 10'd127 && s1_hx <= 10'd131) && (s1_vy >= 10'd198 && s1_vy <= 10'd294)) ||
        (diag_diff_011_010 && (s1_hx >= 10'd85 && s1_hx <= 10'd129)) ||
        ((s1_vy >= 10'd152 && s1_vy <= 10'd156) && (s1_hx >= 10'd85 && s1_hx <= 10'd181)) ||
        (diag_diff_110_111 && (s1_hx >= 10'd181 && s1_hx <= 10'd225)) ||
        ((s1_hx >= 10'd223 && s1_hx <= 10'd227) && (s1_vy >= 10'd198 && s1_vy <= 10'd294)) ||
        ((s1_vy >= 10'd292 && s1_vy <= 10'd296) && (s1_hx >= 10'd129 && s1_hx <= 10'd225));

    // Remaining 6 dim wireframe edges of Q3 (touching 000 or 100):
    //   000-001: y - x = 165, x in [85..129]
    //   100-101: y - x = 69,  x in [181..225]
    //   000-010: x=85,  y in [154..250]
    //   100-110: x=181, y in [154..250]
    //   000-100: y=250, x in [85..181]
    //   011-111: y=198, x in [129..225]
    wire diag_diff_000_001 = ((s1_vy - s1_hx) >= 10'd164) && ((s1_vy - s1_hx) <= 10'd166);
    wire diag_diff_100_101 = ((s1_vy - s1_hx) >= 10'd68)  && ((s1_vy - s1_hx) <= 10'd70);

    wire in_cube_dim_edge =
        (diag_diff_000_001 && (s1_hx >= 10'd85 && s1_hx <= 10'd129)) ||
        (diag_diff_100_101 && (s1_hx >= 10'd181 && s1_hx <= 10'd225)) ||
        ((s1_hx >= 10'd84  && s1_hx <= 10'd86)  && (s1_vy >= 10'd154 && s1_vy <= 10'd250)) ||
        ((s1_hx >= 10'd180 && s1_hx <= 10'd182) && (s1_vy >= 10'd154 && s1_vy <= 10'd250)) ||
        ((s1_vy >= 10'd249 && s1_vy <= 10'd251) && (s1_hx >= 10'd85  && s1_hx <= 10'd181)) ||
        ((s1_vy >= 10'd197 && s1_vy <= 10'd199) && (s1_hx >= 10'd129 && s1_hx <= 10'd225));

    // Middle Panel: 3-wire Bus (b[2] top y=168, b[1] mid y=224, b[0] bot y=280), x in [256..336]
    reg in_bus_frame, in_bus_fill;
    reg [1:0] bus_idx;
    always @(*) begin
        in_bus_frame = 1'b0;
        in_bus_fill  = 1'b0;
        bus_idx      = 2'd0;
        if (s1_hx >= 10'd256 && s1_hx <= 10'd336) begin
            if (s1_vy >= 10'd156 && s1_vy <= 10'd180) begin
                bus_idx = 2'd2;
                in_bus_frame = (s1_hx <= 10'd259) || (s1_hx >= 10'd333) ||
                               (s1_vy <= 10'd159) || (s1_vy >= 10'd177);
                in_bus_fill  = !in_bus_frame;
            end else if (s1_vy >= 10'd212 && s1_vy <= 10'd236) begin
                bus_idx = 2'd1;
                in_bus_frame = (s1_hx <= 10'd259) || (s1_hx >= 10'd333) ||
                               (s1_vy <= 10'd215) || (s1_vy >= 10'd233);
                in_bus_fill  = !in_bus_frame;
            end else if (s1_vy >= 10'd268 && s1_vy <= 10'd292) begin
                bus_idx = 2'd0;
                in_bus_frame = (s1_hx <= 10'd259) || (s1_hx >= 10'd333) ||
                               (s1_vy <= 10'd271) || (s1_vy >= 10'd289);
                in_bus_fill  = !in_bus_frame;
            end
        end
    end

    // Top HUD status pills (y=20..36)
    wire top_pill_role = (s1_vy >= 10'd20 && s1_vy <= 10'd36) && (s1_hx >= 10'd24  && s1_hx <= 10'd148);
    wire top_pill_orb  = (s1_vy >= 10'd20 && s1_vy <= 10'd36) && (s1_hx >= 10'd500 && s1_hx <= 10'd568);
    wire top_pill_act  = (s1_vy >= 10'd20 && s1_vy <= 10'd36) && (s1_hx >= 10'd584 && s1_hx <= 10'd616);

    // Bottom HUD bar (y=404..444):
    //  Slots 0..2: b[2], b[1], b[0] big tiles (x = 40 + i*54, w=46)
    //  Slots 3..5: dlt hamming segments (x = 236 + i*40, w=32)
    //  Slots 6..8: (q, r, s) balanced ternary sign tiles (x = 416 + i*60, w=50)
    reg in_bit_tile, in_bit_frame;
    reg [1:0] bit_tile_idx;
    reg in_dlt_tile;
    reg [1:0] dlt_seg_idx;
    reg in_qrs_tile;
    reg [1:0] qrs_tile_idx;

    wire [1:0] dlt_count = {1'b0, delta_pix[2]} + {1'b0, delta_pix[1]} + {1'b0, delta_pix[0]};

    always @(*) begin
        in_bit_tile  = 1'b0;
        in_bit_frame = 1'b0;
        bit_tile_idx = 2'd0;
        in_dlt_tile  = 1'b0;
        dlt_seg_idx  = 2'd0;
        in_qrs_tile  = 1'b0;
        qrs_tile_idx = 2'd0;

        if (s1_vy >= 10'd404 && s1_vy <= 10'd444) begin
            // 3 bit tiles: b[2] @ 40..86, b[1] @ 94..140, b[0] @ 148..194
            if (s1_hx >= 10'd40 && s1_hx <= 10'd86) begin
                in_bit_tile  = 1'b1;
                bit_tile_idx = 2'd2;
                in_bit_frame = (s1_hx <= 10'd43 || s1_hx >= 10'd83 || s1_vy <= 10'd407 || s1_vy >= 10'd441);
            end else if (s1_hx >= 10'd94 && s1_hx <= 10'd140) begin
                in_bit_tile  = 1'b1;
                bit_tile_idx = 2'd1;
                in_bit_frame = (s1_hx <= 10'd97 || s1_hx >= 10'd137 || s1_vy <= 10'd407 || s1_vy >= 10'd441);
            end else if (s1_hx >= 10'd148 && s1_hx <= 10'd194) begin
                in_bit_tile  = 1'b1;
                bit_tile_idx = 2'd0;
                in_bit_frame = (s1_hx <= 10'd151 || s1_hx >= 10'd191 || s1_vy <= 10'd407 || s1_vy >= 10'd441);
            end

            // 3 Hamming delta segments: seg1 @ 240..274, seg2 @ 282..316, seg3 @ 324..358
            if (s1_hx >= 10'd240 && s1_hx <= 10'd274) begin
                in_dlt_tile = 1'b1;
                dlt_seg_idx = 2'd1;
            end else if (s1_hx >= 10'd282 && s1_hx <= 10'd316) begin
                in_dlt_tile = 1'b1;
                dlt_seg_idx = 2'd2;
            end else if (s1_hx >= 10'd324 && s1_hx <= 10'd358) begin
                in_dlt_tile = 1'b1;
                dlt_seg_idx = 2'd3;
            end

            // 3 balanced ternary (q, r, s) tiles: q @ 416..466, r @ 476..526, s @ 536..586
            if (s1_hx >= 10'd416 && s1_hx <= 10'd466) begin
                in_qrs_tile  = 1'b1;
                qrs_tile_idx = 2'd0;
            end else if (s1_hx >= 10'd476 && s1_hx <= 10'd526) begin
                in_qrs_tile  = 1'b1;
                qrs_tile_idx = 2'd1;
            end else if (s1_hx >= 10'd536 && s1_hx <= 10'd586) begin
                in_qrs_tile  = 1'b1;
                qrs_tile_idx = 2'd2;
            end
        end
    end

    wire [1:0] cur_qrs_sign = (qrs_tile_idx == 2'd0) ? q_sign :
                              (qrs_tile_idx == 2'd1) ? r_sign : s_sign;

    // Stage 2: RGB color synthesis
    reg [7:0] pix_r = 8'd0;
    reg [7:0] pix_g = 8'd0;
    reg [7:0] pix_b = 8'd0;
    reg       s2_de = 1'b0;
    reg       s2_hs = 1'b0;
    reg       s2_vs = 1'b0;

    always @(posedge clk_pix) begin
        s2_de <= s1_de;
        s2_hs <= s1_hs;
        s2_vs <= s1_vs;

        if (!s1_de) begin
            pix_r <= 8'd0;
            pix_g <= 8'd0;
            pix_b <= 8'd0;
        end else if (in_hex_cell) begin
            if (cell_is_active) begin
                if (in_hex_border) begin
                    // Bright metallic white/gold rim on active hexagon
                    pix_r <= 8'd255; pix_g <= 8'd244; pix_b <= 8'd185;
                end else if (cell_code == 3'b000) begin
                    // Centro (0,0,0) active: glowing emerald with white circle glyph
                    if (glyph_ring) begin
                        pix_r <= 8'd245; pix_g <= 8'd255; pix_b <= 8'd250;
                    end else begin
                        pix_r <= 8'd22;  pix_g <= 8'd188; pix_b <= 8'd128;
                    end
                end else begin
                    // Gray Ring vertex active: glowing amber-gold with '+' beacon
                    if (glyph_plus_h || glyph_plus_v) begin
                        pix_r <= 8'd255; pix_g <= 8'd252; pix_b <= 8'd240;
                    end else begin
                        pix_r <= 8'd240; pix_g <= 8'd172; pix_b <= 8'd36;
                    end
                end
            end else begin
                // Inactive Tryte6 cell
                if (in_hex_border) begin
                    if (state_pix == 3'b100) begin
                        // Sentinel alert rim
                        pix_r <= 8'd178; pix_g <= 8'd54; pix_b <= 8'd72;
                    end else if (s1_hex_idx == 3'd0) begin
                        pix_r <= 8'd52;  pix_g <= 8'd134; pix_b <= 8'd108;
                    end else begin
                        pix_r <= 8'd62;  pix_g <= 8'd110; pix_b <= 8'd142;
                    end
                end else begin
                    if (s1_hex_idx == 3'd0) begin
                        pix_r <= 8'd16; pix_g <= 8'd42; pix_b <= 8'd40;
                    end else begin
                        pix_r <= 8'd22; pix_g <= 8'd34; pix_b <= 8'd54;
                    end
                end
            end
        end else if (in_sent_badge) begin
            if (state_pix == 3'b100) begin
                if (in_sent_x || in_sent_ring) begin
                    pix_r <= 8'd255; pix_g <= 8'd230; pix_b <= 8'd234;
                end else begin
                    pix_r <= 8'd224; pix_g <= 8'd42; pix_b <= 8'd68;
                end
            end else begin
                if (in_sent_ring) begin
                    pix_r <= 8'd148; pix_g <= 8'd44; pix_b <= 8'd58;
                end else if (in_sent_x) begin
                    pix_r <= 8'd130; pix_g <= 8'd48; pix_b <= 8'd60;
                end else begin
                    pix_r <= 8'd32;  pix_g <= 8'd18; pix_b <= 8'd26;
                end
            end
        end else if (in_q3_node) begin
            if (q3_node_code == state_pix) begin
                if (q3_node_code == 3'b000) begin
                    pix_r <= 8'd52; pix_g <= 8'd225; pix_b <= 8'd158;
                end else if (q3_node_code == 3'b100) begin
                    pix_r <= 8'd244; pix_g <= 8'd58; pix_b <= 8'd82;
                end else begin
                    pix_r <= 8'd250; pix_g <= 8'd194; pix_b <= 8'd56;
                end
            end else if (q3_node_code == 3'b000) begin
                pix_r <= 8'd30; pix_g <= 8'd118; pix_b <= 8'd92;
            end else if (q3_node_code == 3'b100) begin
                pix_r <= 8'd156; pix_g <= 8'd42; pix_b <= 8'd58;
            end else begin
                pix_r <= 8'd64; pix_g <= 8'd154; pix_b <= 8'd212;
            end
        end else if (in_q3_active_halo) begin
            if (state_pix == 3'b000) begin
                pix_r <= 8'd110; pix_g <= 8'd248; pix_b <= 8'd190;
            end else if (state_pix == 3'b100) begin
                pix_r <= 8'd255; pix_g <= 8'd98; pix_b <= 8'd118;
            end else begin
                pix_r <= 8'd255; pix_g <= 8'd220; pix_b <= 8'd108;
            end
        end else if (in_ring_edge) begin
            pix_r <= 8'd56; pix_g <= 8'd178; pix_b <= 8'd224;
        end else if (in_cube_dim_edge) begin
            pix_r <= 8'd44; pix_g <= 8'd56; pix_b <= 8'd82;
        end else if (in_bus_frame || in_bus_fill) begin
            if (in_bus_frame && delta_pix[bus_idx]) begin
                // Changed wire halo in gold
                pix_r <= 8'd250; pix_g <= 8'd192; pix_b <= 8'd52;
            end else if (in_bus_frame) begin
                pix_r <= 8'd48; pix_g <= 8'd64; pix_b <= 8'd92;
            end else if (state_pix[bus_idx]) begin
                pix_r <= 8'd52; pix_g <= 8'd198; pix_b <= 8'd236;
            end else begin
                pix_r <= 8'd22; pix_g <= 8'd30; pix_b <= 8'd48;
            end
        end else if (in_bit_tile) begin
            if (in_bit_frame && delta_pix[bit_tile_idx]) begin
                pix_r <= 8'd250; pix_g <= 8'd192; pix_b <= 8'd52;
            end else if (in_bit_frame) begin
                pix_r <= 8'd52; pix_g <= 8'd68; pix_b <= 8'd96;
            end else if (state_pix[bit_tile_idx]) begin
                pix_r <= 8'd56; pix_g <= 8'd206; pix_b <= 8'd240;
            end else begin
                pix_r <= 8'd24; pix_g <= 8'd32; pix_b <= 8'd50;
            end
        end else if (in_dlt_tile) begin
            if (dlt_seg_idx <= dlt_count) begin
                if (dlt_count == 2'd1) begin
                    pix_r <= 8'd42; pix_g <= 8'd212; pix_b <= 8'd146;
                end else begin
                    pix_r <= 8'd238; pix_g <= 8'd136; pix_b <= 8'd44;
                end
            end else begin
                pix_r <= 8'd24; pix_g <= 8'd32; pix_b <= 8'd50;
            end
        end else if (in_qrs_tile) begin
            if (cur_qrs_sign == 2'b10) begin
                // +1 Coral
                pix_r <= 8'd226; pix_g <= 8'd76; pix_b <= 8'd68;
            end else if (cur_qrs_sign == 2'b11) begin
                // -1 Blue
                pix_r <= 8'd46; pix_g <= 8'd136; pix_b <= 8'd240;
            end else if (cur_qrs_sign == 2'b01) begin
                // 0 Silver
                pix_r <= 8'd180; pix_g <= 8'd194; pix_b <= 8'd216;
            end else begin
                // Sentinela (void)
                pix_r <= 8'd190; pix_g <= 8'd36; pix_b <= 8'd56;
            end
        end else if (top_pill_role) begin
            if (state_pix == 3'b000) begin
                pix_r <= 8'd32; pix_g <= 8'd194; pix_b <= 8'd134;
            end else if (state_pix == 3'b100) begin
                pix_r <= 8'd222; pix_g <= 8'd48; pix_b <= 8'd68;
            end else begin
                pix_r <= 8'd224; pix_g <= 8'd170; pix_b <= 8'd46;
            end
        end else if (top_pill_orb) begin
            if (orb_pix) begin
                pix_r <= 8'd56; pix_g <= 8'd189; pix_b <= 8'd248;
            end else begin
                pix_r <= 8'd30; pix_g <= 8'd40; pix_b <= 8'd58;
            end
        end else if (top_pill_act) begin
            if (act_pix) begin
                pix_r <= 8'd52; pix_g <= 8'd211; pix_b <= 8'd153;
            end else begin
                pix_r <= 8'd28; pix_g <= 8'd36; pix_b <= 8'd52;
            end
        end else begin
            // Obsidian backdrop with subtle grid dots every 32 px
            if ((s1_hx[4:0] == 5'd0) && (s1_vy[4:0] == 5'd0)) begin
                pix_r <= 8'd30; pix_g <= 8'd40; pix_b <= 8'd62;
            end else begin
                pix_r <= 8'd10; pix_g <= 8'd14; pix_b <= 8'd24;
            end
        end
    end

    // TMDS encoders
    wire [9:0] tmds_blue, tmds_green, tmds_red;
    hex_gray_tmds_encoder u_enc_b (.clk(clk_pix), .rst(rst_pix), .data(pix_b), .ctrl({s2_vs, s2_hs}), .de(s2_de), .dout(tmds_blue));
    hex_gray_tmds_encoder u_enc_g (.clk(clk_pix), .rst(rst_pix), .data(pix_g), .ctrl(2'b00),          .de(s2_de), .dout(tmds_green));
    hex_gray_tmds_encoder u_enc_r (.clk(clk_pix), .rst(rst_pix), .data(pix_r), .ctrl(2'b00),          .de(s2_de), .dout(tmds_red));

    generate
        if (SIM_ONLY == 0) begin : gen_gowin_tmds
            wire ser_clk, ser_d0, ser_d1, ser_d2;

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_clk (
                .Q(ser_clk),
                .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
                .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_clk (.I(ser_clk), .O(O_tmds_clk_p), .OB(O_tmds_clk_n));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d0 (
                .Q(ser_d0),
                .D0(tmds_blue[0]), .D1(tmds_blue[1]), .D2(tmds_blue[2]), .D3(tmds_blue[3]), .D4(tmds_blue[4]),
                .D5(tmds_blue[5]), .D6(tmds_blue[6]), .D7(tmds_blue[7]), .D8(tmds_blue[8]), .D9(tmds_blue[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d0 (.I(ser_d0), .O(O_tmds_data_p[0]), .OB(O_tmds_data_n[0]));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d1 (
                .Q(ser_d1),
                .D0(tmds_green[0]), .D1(tmds_green[1]), .D2(tmds_green[2]), .D3(tmds_green[3]), .D4(tmds_green[4]),
                .D5(tmds_green[5]), .D6(tmds_green[6]), .D7(tmds_green[7]), .D8(tmds_green[8]), .D9(tmds_green[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d1 (.I(ser_d1), .O(O_tmds_data_p[1]), .OB(O_tmds_data_n[1]));

            OSER10 #(.GSREN("false"), .LSREN("true")) u_ser_d2 (
                .Q(ser_d2),
                .D0(tmds_red[0]), .D1(tmds_red[1]), .D2(tmds_red[2]), .D3(tmds_red[3]), .D4(tmds_red[4]),
                .D5(tmds_red[5]), .D6(tmds_red[6]), .D7(tmds_red[7]), .D8(tmds_red[8]), .D9(tmds_red[9]),
                .PCLK(clk_pix), .FCLK(clk_tmds), .RESET(rst_pix)
            );
            TLVDS_OBUF u_obuf_d2 (.I(ser_d2), .O(O_tmds_data_p[2]), .OB(O_tmds_data_n[2]));
        end else begin : gen_sim_tmds
            assign O_tmds_clk_p  = 1'b0;
            assign O_tmds_clk_n  = 1'b1;
            assign O_tmds_data_p = 3'b000;
            assign O_tmds_data_n = 3'b111;
        end
    endgenerate
endmodule
