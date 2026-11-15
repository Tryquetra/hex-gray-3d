`timescale 1ns/1ps

// Hexagonal Gray Code (3 bits in Q3 -> Centro 000 + 6-state Ring + Sentinela 100)
// Top-level for Sipeed Tang Nano 20K (Gowin GW2AR-18C).
module hex_gray_top #(
    parameter integer SIM_ONLY = 0
) (
    input  wire       I_clk,       // 27 MHz crystal oscillator (pin 4)
    input  wire [1:0] I_btn,       // Active-high pushbuttons (pins 88, 87)
    output wire [5:0] O_led_n,     // Active-low LEDs (pins 15..20)
    output wire       O_uart_tx,   // UART TX (pin 69)
    input  wire       I_uart_rx,   // UART RX (pin 70)
    output wire       O_tmds_clk_p,
    output wire       O_tmds_clk_n,
    output wire [2:0] O_tmds_data_p,
    output wire [2:0] O_tmds_data_n
);
    // Clocks: 27 MHz system, 126 MHz TMDS serial, 25.2 MHz pixel clock
    wire clk_sys = I_clk;
    wire clk_tmds;
    wire clk_pix;
    wire pll_lock;

    generate
        if (SIM_ONLY == 0) begin : gen_gowin_clks
            rPLL #(
                .FCLKIN("27.0"),
                .IDIV_SEL(2),
                .FBDIV_SEL(13),
                .ODIV_SEL(4),
                .CLKOUTD_BYPASS("false"),
                .CLKOUTD_SRC("CLKOUT"),
                .DYN_SDIV_SEL(6)
            ) u_pll_hdmi (
                .CLKIN(I_clk),
                .CLKFB(1'b0),
                .RESET(1'b0),
                .RESET_P(1'b0),
                .FBDSEL(6'b0),
                .IDSEL(6'b0),
                .ODSEL(6'b0),
                .PSDA(4'b0),
                .DUTYDA(4'b0),
                .FDLY(4'b0),
                .CLKOUT(clk_tmds),
                .LOCK(pll_lock),
                .CLKOUTP(),
                .CLKOUTD(),
                .CLKOUTD3()
            );

            CLKDIV #(
                .DIV_MODE("5"),
                .GSREN("false")
            ) u_div5 (
                .HCLKIN(clk_tmds),
                .RESETN(pll_lock),
                .CALIB(1'b0),
                .CLKOUT(clk_pix)
            );
        end else begin : gen_sim_clks
            assign clk_tmds = I_clk;
            assign clk_pix  = I_clk;
            assign pll_lock = 1'b1;
        end
    endgenerate

    // Power-on reset stretcher (~2.4 ms on hardware, 8 cycles in simulation)
    reg [15:0] por_cnt = 16'd0;
    wire por_done = (SIM_ONLY != 0) ? (por_cnt >= 16'd8) : (&por_cnt);
    always @(posedge clk_sys) begin
        if (!por_done)
            por_cnt <= por_cnt + 16'd1;
    end
    wire rst_sys = ~por_done;

    reg rst_pix_s0 = 1'b1;
    reg rst_pix    = 1'b1;
    always @(posedge clk_pix) begin
        rst_pix_s0 <= (~por_done) | (~pll_lock);
        rst_pix    <= rst_pix_s0;
    end

    // Core 3-bit Hexagonal Gray state registers
    reg [2:0] gray_state = 3'b001;
    reg [2:0] last_delta = 3'b000;
    reg       auto_orbit = 1'b0;

    // Pure combinational next-state lookup for 6-state Gray Ring
    // Every CCW/CW step from any state toggles strictly 1 bit.
    function [2:0] next_ccw;
        input [2:0] st;
        begin
            case (st)
                3'b001: next_ccw = 3'b011; //   0 ->  60 deg (flip b1)
                3'b011: next_ccw = 3'b010; //  60 -> 120 deg (flip b0)
                3'b010: next_ccw = 3'b110; // 120 -> 180 deg (flip b2)
                3'b110: next_ccw = 3'b111; // 180 -> 240 deg (flip b0)
                3'b111: next_ccw = 3'b101; // 240 -> 300 deg (flip b1)
                3'b101: next_ccw = 3'b001; // 300 ->   0 deg (flip b2)
                3'b000: next_ccw = 3'b001; // Centro ->   0 deg (flip b0)
                3'b100: next_ccw = 3'b101; // Sentinela -> 300 deg (flip b0)
            endcase
        end
    endfunction

    function [2:0] next_cw;
        input [2:0] st;
        begin
            case (st)
                3'b001: next_cw = 3'b101; //   0 -> 300 deg (flip b2)
                3'b101: next_cw = 3'b111; // 300 -> 240 deg (flip b1)
                3'b111: next_cw = 3'b110; // 240 -> 180 deg (flip b0)
                3'b110: next_cw = 3'b010; // 180 -> 120 deg (flip b2)
                3'b010: next_cw = 3'b011; // 120 ->  60 deg (flip b0)
                3'b011: next_cw = 3'b001; //  60 ->   0 deg (flip b1)
                3'b000: next_cw = 3'b010; // Centro -> 120 deg (flip b1)
                3'b100: next_cw = 3'b110; // Sentinela -> 180 deg (flip b1)
            endcase
        end
    endfunction

    // Debounce pushbuttons (~10 ms at 27 MHz)
    localparam integer DB_MAX   = (SIM_ONLY != 0) ? 4 : 270000;
    localparam integer HOLD_MAX = (SIM_ONLY != 0) ? 40 : 21600000; // 800 ms

    reg [1:0]  btn_sync0 = 2'b00, btn_sync1 = 2'b00, btn_deb = 2'b00;
    reg [18:0] db_cnt0   = 19'd0, db_cnt1   = 19'd0;
    reg        saw_b0    = 1'b0,  saw_b1    = 1'b0;
    reg        long_done = 1'b0;
    reg [24:0] hold_cnt  = 25'd0;

    reg        btn_evt_ccw    = 1'b0;
    reg        btn_evt_cw     = 1'b0;
    reg        btn_evt_center = 1'b0;
    reg        btn_evt_reset  = 1'b0;

    always @(posedge clk_sys) begin
        btn_evt_ccw    <= 1'b0;
        btn_evt_cw     <= 1'b0;
        btn_evt_center <= 1'b0;
        btn_evt_reset  <= 1'b0;

        if (rst_sys) begin
            btn_sync0 <= 2'b00;
            btn_sync1 <= 2'b00;
            btn_deb   <= 2'b00;
            db_cnt0   <= 19'd0;
            db_cnt1   <= 19'd0;
            saw_b0    <= 1'b0;
            saw_b1    <= 1'b0;
            long_done <= 1'b0;
            hold_cnt  <= 25'd0;
        end else begin
            btn_sync0 <= I_btn;
            btn_sync1 <= btn_sync0;

            if (btn_sync1[0] == btn_deb[0]) begin
                db_cnt0 <= 19'd0;
            end else if (db_cnt0 >= DB_MAX[18:0]) begin
                btn_deb[0] <= btn_sync1[0];
                db_cnt0    <= 19'd0;
            end else begin
                db_cnt0 <= db_cnt0 + 19'd1;
            end

            if (btn_sync1[1] == btn_deb[1]) begin
                db_cnt1 <= 19'd0;
            end else if (db_cnt1 >= DB_MAX[18:0]) begin
                btn_deb[1] <= btn_sync1[1];
                db_cnt1    <= 19'd0;
            end else begin
                db_cnt1 <= db_cnt1 + 19'd1;
            end

            if (btn_deb != 2'b00) begin
                if (btn_deb[0]) saw_b0 <= 1'b1;
                if (btn_deb[1]) saw_b1 <= 1'b1;

                if (btn_deb == 2'b11 && !long_done) begin
                    if (hold_cnt >= HOLD_MAX[24:0]) begin
                        btn_evt_reset <= 1'b1;
                        long_done     <= 1'b1;
                    end else begin
                        hold_cnt <= hold_cnt + 25'd1;
                    end
                end else if (btn_deb != 2'b11) begin
                    hold_cnt <= 25'd0;
                end
            end else begin
                if (saw_b0 || saw_b1) begin
                    if (!long_done) begin
                        if (saw_b0 && saw_b1)
                            btn_evt_center <= 1'b1;
                        else if (saw_b0)
                            btn_evt_ccw <= 1'b1;
                        else
                            btn_evt_cw  <= 1'b1;
                    end
                    saw_b0    <= 1'b0;
                    saw_b1    <= 1'b0;
                    long_done <= 1'b0;
                    hold_cnt  <= 25'd0;
                end
            end
        end
    end

    // Auto-orbit ~1 Hz ticker (27,000,000 cycles at 27 MHz)
    localparam integer ORBIT_MAX = (SIM_ONLY != 0) ? 64 : 27000000;
    reg [24:0] orbit_cnt  = 25'd0;
    reg        orbit_tick = 1'b0;
    always @(posedge clk_sys) begin
        orbit_tick <= 1'b0;
        if (rst_sys || !auto_orbit) begin
            orbit_cnt <= 25'd0;
        end else if (orbit_cnt >= ORBIT_MAX[24:0] - 25'd1) begin
            orbit_cnt  <= 25'd0;
            orbit_tick <= 1'b1;
        end else begin
            orbit_cnt <= orbit_cnt + 25'd1;
        end
    end

    // UART transceiver
    wire       uart_rx_valid;
    wire [7:0] uart_rx_data;
    reg        uart_tx_start = 1'b0;
    reg  [7:0] uart_tx_data  = 8'd0;
    wire       uart_tx_busy;

    hex_gray_uart u_uart (
        .clk      (clk_sys),
        .rst      (rst_sys),
        .rx       (I_uart_rx),
        .tx       (O_uart_tx),
        .tx_start (uart_tx_start),
        .tx_data  (uart_tx_data),
        .tx_busy  (uart_tx_busy),
        .rx_valid (uart_rx_valid),
        .rx_data  (uart_rx_data)
    );

    // Activity pulse (~150 ms) & PLL lock heartbeat
    reg [21:0] act_cnt  = 22'd0;
    reg [24:0] hb_cnt   = 25'd0;
    reg        emit_req = 1'b0;
    reg [1:0]  g_rem    = 2'd0;
    reg [2:0]  g_shift  = 3'd0;
    reg [2:0]  nxt_tmp  = 3'b001;
    reg        boot_emitted = 1'b0;

    always @(posedge clk_sys) begin
        emit_req <= 1'b0;
        if (rst_sys) begin
            gray_state   <= 3'b001;
            last_delta   <= 3'b000;
            auto_orbit   <= 1'b0;
            act_cnt      <= 22'd0;
            hb_cnt       <= 25'd0;
            g_rem        <= 2'd0;
            g_shift      <= 3'd0;
            boot_emitted <= 1'b0;
        end else begin
            hb_cnt <= hb_cnt + 25'd1;
            if (act_cnt != 22'd0)
                act_cnt <= act_cnt - 22'd1;

            if (!boot_emitted) begin
                boot_emitted <= 1'b1;
                emit_req     <= 1'b1;
            end else if (btn_evt_reset) begin
                last_delta <= gray_state ^ 3'b001;
                gray_state <= 3'b001;
                auto_orbit <= 1'b0;
                g_rem      <= 2'd0;
                act_cnt    <= 22'h3FFFFF;
                emit_req   <= 1'b1;
            end else if (btn_evt_center) begin
                nxt_tmp    = (gray_state == 3'b000) ? 3'b001 : 3'b000;
                last_delta <= gray_state ^ nxt_tmp;
                gray_state <= nxt_tmp;
                g_rem      <= 2'd0;
                act_cnt    <= 22'h3FFFFF;
                emit_req   <= 1'b1;
            end else if (btn_evt_ccw) begin
                nxt_tmp    = next_ccw(gray_state);
                last_delta <= gray_state ^ nxt_tmp;
                gray_state <= nxt_tmp;
                g_rem      <= 2'd0;
                act_cnt    <= 22'h3FFFFF;
                emit_req   <= 1'b1;
            end else if (btn_evt_cw) begin
                nxt_tmp    = next_cw(gray_state);
                last_delta <= gray_state ^ nxt_tmp;
                gray_state <= nxt_tmp;
                g_rem      <= 2'd0;
                act_cnt    <= 22'h3FFFFF;
                emit_req   <= 1'b1;
            end else if (uart_rx_valid) begin
                act_cnt <= 22'h3FFFFF;
                if (g_rem != 2'd0 && (uart_rx_data == "0" || uart_rx_data == "1")) begin
                    nxt_tmp = {g_shift[1:0], (uart_rx_data == "1")};
                    g_shift <= nxt_tmp;
                    if (g_rem == 2'd1) begin
                        g_rem      <= 2'd0;
                        last_delta <= gray_state ^ nxt_tmp;
                        gray_state <= nxt_tmp;
                        emit_req   <= 1'b1;
                    end else begin
                        g_rem <= g_rem - 2'd1;
                    end
                end else begin
                    g_rem <= 2'd0;
                    case (uart_rx_data)
                        "c", "C", "+", "f", "F": begin
                            nxt_tmp    = next_ccw(gray_state);
                            last_delta <= gray_state ^ nxt_tmp;
                            gray_state <= nxt_tmp;
                            emit_req   <= 1'b1;
                        end
                        "a", "A", "-", "b", "B": begin
                            nxt_tmp    = next_cw(gray_state);
                            last_delta <= gray_state ^ nxt_tmp;
                            gray_state <= nxt_tmp;
                            emit_req   <= 1'b1;
                        end
                        "0", "z", "Z": begin
                            last_delta <= gray_state ^ 3'b000;
                            gray_state <= 3'b000;
                            emit_req   <= 1'b1;
                        end
                        "1": begin
                            last_delta <= gray_state ^ 3'b001;
                            gray_state <= 3'b001;
                            emit_req   <= 1'b1;
                        end
                        "2": begin
                            last_delta <= gray_state ^ 3'b011;
                            gray_state <= 3'b011;
                            emit_req   <= 1'b1;
                        end
                        "3": begin
                            last_delta <= gray_state ^ 3'b010;
                            gray_state <= 3'b010;
                            emit_req   <= 1'b1;
                        end
                        "4": begin
                            last_delta <= gray_state ^ 3'b110;
                            gray_state <= 3'b110;
                            emit_req   <= 1'b1;
                        end
                        "5": begin
                            last_delta <= gray_state ^ 3'b111;
                            gray_state <= 3'b111;
                            emit_req   <= 1'b1;
                        end
                        "6": begin
                            last_delta <= gray_state ^ 3'b101;
                            gray_state <= 3'b101;
                            emit_req   <= 1'b1;
                        end
                        "s", "S", "x", "X": begin
                            last_delta <= gray_state ^ 3'b100;
                            gray_state <= 3'b100;
                            emit_req   <= 1'b1;
                        end
                        "r", "R": begin
                            last_delta <= gray_state ^ 3'b001;
                            gray_state <= 3'b001;
                            auto_orbit <= 1'b0;
                            emit_req   <= 1'b1;
                        end
                        "o", "O": begin
                            auto_orbit <= ~auto_orbit;
                            emit_req   <= 1'b1;
                        end
                        "g", "G": begin
                            g_rem   <= 2'd3;
                            g_shift <= 3'd0;
                        end
                        "?": begin
                            emit_req <= 1'b1;
                        end
                        default: begin
                            // Ignore whitespace / newline noise cleanly
                        end
                    endcase
                end
            end else if (orbit_tick) begin
                nxt_tmp    = next_ccw(gray_state);
                last_delta <= gray_state ^ nxt_tmp;
                gray_state <= nxt_tmp;
                act_cnt    <= 22'h3FFFFF;
                emit_req   <= 1'b1;
            end
        end
    end

    // Telemetry snapshot & 61-byte ASCII formatter:
    // "HG code=3'b011 qrs=( 0,+1,-1) ang=060 dlt=1 role=ring orb=0\r\n"
    reg       tx_active  = 1'b0;
    reg       tx_pending = 1'b0;
    reg [5:0] tx_idx     = 6'd0;
    reg [2:0] snap_st    = 3'b001;
    reg [2:0] snap_dlt   = 3'b000;
    reg       snap_orb   = 1'b0;

    wire [1:0] snap_dlt_cnt = {1'b0, snap_dlt[2]} + {1'b0, snap_dlt[1]} + {1'b0, snap_dlt[0]};

    function [7:0] q_c0; input [2:0] s; begin
        case (s)
            3'b001, 3'b101: q_c0 = "+";
            3'b010, 3'b110: q_c0 = "-";
            3'b100:         q_c0 = "?";
            default:        q_c0 = " ";
        endcase
    end endfunction

    function [7:0] q_c1; input [2:0] s; begin
        q_c1 = (s == 3'b100) ? "?" : ((s == 3'b000 || s == 3'b011 || s == 3'b111) ? "0" : "1");
    end endfunction

    function [7:0] r_c0; input [2:0] s; begin
        case (s)
            3'b011, 3'b010: r_c0 = "+";
            3'b111, 3'b101: r_c0 = "-";
            3'b100:         r_c0 = "?";
            default:        r_c0 = " ";
        endcase
    end endfunction

    function [7:0] r_c1; input [2:0] s; begin
        r_c1 = (s == 3'b100) ? "?" : ((s == 3'b000 || s == 3'b001 || s == 3'b110) ? "0" : "1");
    end endfunction

    function [7:0] s_c0; input [2:0] s; begin
        case (s)
            3'b110, 3'b111: s_c0 = "+";
            3'b001, 3'b011: s_c0 = "-";
            3'b100:         s_c0 = "?";
            default:        s_c0 = " ";
        endcase
    end endfunction

    function [7:0] s_c1; input [2:0] s; begin
        s_c1 = (s == 3'b100) ? "?" : ((s == 3'b000 || s == 3'b010 || s == 3'b101) ? "0" : "1");
    end endfunction

    function [23:0] ang_str; input [2:0] s; begin
        case (s)
            3'b000: ang_str = "nil";
            3'b001: ang_str = "000";
            3'b011: ang_str = "060";
            3'b010: ang_str = "120";
            3'b110: ang_str = "180";
            3'b111: ang_str = "240";
            3'b101: ang_str = "300";
            3'b100: ang_str = "err";
        endcase
    end endfunction

    function [31:0] role_str; input [2:0] s; begin
        case (s)
            3'b000:  role_str = "cntr";
            3'b100:  role_str = "sent";
            default: role_str = "ring";
        endcase
    end endfunction

    function [7:0] telem_byte;
        input [5:0] idx;
        input [2:0] st;
        input [1:0] dlt_cnt;
        input       orb;
        reg [23:0] a3;
        reg [31:0] r4;
        begin
            a3 = ang_str(st);
            r4 = role_str(st);
            case (idx)
                6'd0:  telem_byte = "H";
                6'd1:  telem_byte = "G";
                6'd2:  telem_byte = " ";
                6'd3:  telem_byte = "c";
                6'd4:  telem_byte = "o";
                6'd5:  telem_byte = "d";
                6'd6:  telem_byte = "e";
                6'd7:  telem_byte = "=";
                6'd8:  telem_byte = "3";
                6'd9:  telem_byte = "'";
                6'd10: telem_byte = "b";
                6'd11: telem_byte = st[2] ? "1" : "0";
                6'd12: telem_byte = st[1] ? "1" : "0";
                6'd13: telem_byte = st[0] ? "1" : "0";
                6'd14: telem_byte = " ";
                6'd15: telem_byte = "q";
                6'd16: telem_byte = "r";
                6'd17: telem_byte = "s";
                6'd18: telem_byte = "=";
                6'd19: telem_byte = "(";
                6'd20: telem_byte = q_c0(st);
                6'd21: telem_byte = q_c1(st);
                6'd22: telem_byte = ",";
                6'd23: telem_byte = r_c0(st);
                6'd24: telem_byte = r_c1(st);
                6'd25: telem_byte = ",";
                6'd26: telem_byte = s_c0(st);
                6'd27: telem_byte = s_c1(st);
                6'd28: telem_byte = ")";
                6'd29: telem_byte = " ";
                6'd30: telem_byte = "a";
                6'd31: telem_byte = "n";
                6'd32: telem_byte = "g";
                6'd33: telem_byte = "=";
                6'd34: telem_byte = a3[23:16];
                6'd35: telem_byte = a3[15:8];
                6'd36: telem_byte = a3[7:0];
                6'd37: telem_byte = " ";
                6'd38: telem_byte = "d";
                6'd39: telem_byte = "l";
                6'd40: telem_byte = "t";
                6'd41: telem_byte = "=";
                6'd42: telem_byte = 8'd48 + {6'd0, dlt_cnt};
                6'd43: telem_byte = " ";
                6'd44: telem_byte = "r";
                6'd45: telem_byte = "o";
                6'd46: telem_byte = "l";
                6'd47: telem_byte = "e";
                6'd48: telem_byte = "=";
                6'd49: telem_byte = r4[31:24];
                6'd50: telem_byte = r4[23:16];
                6'd51: telem_byte = r4[15:8];
                6'd52: telem_byte = r4[7:0];
                6'd53: telem_byte = " ";
                6'd54: telem_byte = "o";
                6'd55: telem_byte = "r";
                6'd56: telem_byte = "b";
                6'd57: telem_byte = "=";
                6'd58: telem_byte = orb ? "1" : "0";
                6'd59: telem_byte = 8'd13; // '\r'
                6'd60: telem_byte = 8'd10; // '\n'
                default: telem_byte = 8'd10;
            endcase
        end
    endfunction

    always @(posedge clk_sys) begin
        uart_tx_start <= 1'b0;
        if (rst_sys) begin
            tx_active  <= 1'b0;
            tx_pending <= 1'b0;
            tx_idx     <= 6'd0;
            snap_st    <= 3'b001;
            snap_dlt   <= 3'b000;
            snap_orb   <= 1'b0;
        end else begin
            if (emit_req) begin
                if (!tx_active) begin
                    tx_active  <= 1'b1;
                    tx_idx     <= 6'd0;
                    snap_st    <= gray_state;
                    snap_dlt   <= last_delta;
                    snap_orb   <= auto_orbit;
                end else begin
                    tx_pending <= 1'b1;
                end
            end

            if (tx_active && !uart_tx_busy && !uart_tx_start) begin
                uart_tx_data  <= telem_byte(tx_idx, snap_st, snap_dlt_cnt, snap_orb);
                uart_tx_start <= 1'b1;
                if (tx_idx == 6'd60) begin
                    if (tx_pending) begin
                        tx_pending <= 1'b0;
                        tx_idx     <= 6'd0;
                        snap_st    <= gray_state;
                        snap_dlt   <= last_delta;
                        snap_orb   <= auto_orbit;
                    end else begin
                        tx_active <= 1'b0;
                    end
                end else begin
                    tx_idx <= tx_idx + 6'd1;
                end
            end
        end
    end

    // Procedural HDMI generator
    wire act_flag = (act_cnt != 22'd0);
    hex_gray_hdmi #(
        .SIM_ONLY(SIM_ONLY)
    ) u_hdmi (
        .clk_pix        (clk_pix),
        .clk_tmds       (clk_tmds),
        .rst_pix        (rst_pix),
        .gray_state_sys (gray_state),
        .last_delta_sys (last_delta),
        .auto_orbit_sys (auto_orbit),
        .activity_sys   (act_flag),
        .O_tmds_clk_p   (O_tmds_clk_p),
        .O_tmds_clk_n   (O_tmds_clk_n),
        .O_tmds_data_p  (O_tmds_data_p),
        .O_tmds_data_n  (O_tmds_data_n)
    );

    // Active-low Tang Nano 20K LEDs
    assign O_led_n[2:0] = ~gray_state;
    assign O_led_n[3]   = ~(gray_state == 3'b100);
    assign O_led_n[4]   = ~(act_flag | auto_orbit);
    assign O_led_n[5]   = ~(pll_lock & hb_cnt[24]);
endmodule
