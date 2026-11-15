`timescale 1ns/1ps

module tb_bench;
    reg clk = 1'b0;
    always #18.518 clk = ~clk; // ~27 MHz

    reg        rst   = 1'b1;
    reg  [1:0] op    = 2'b00;
    reg  [2:0] delta = 3'd0;

    // 4 Ring instances
    wire [2:0] r_b3;
    wire [6:0] r_oh;
    wire [5:0] r_t2;
    wire [2:0] r_hg;

    ring_bin3      u_r_b3 (.clk(clk), .rst(rst), .op(op), .state(r_b3));
    ring_onehot7   u_r_oh (.clk(clk), .rst(rst), .op(op), .state(r_oh));
    ring_trit2b    u_r_t2 (.clk(clk), .rst(rst), .op(op), .state(r_t2));
    ring_hex_gray3 u_r_hg (.clk(clk), .rst(rst), .op(op), .state(r_hg));

    // 4 ALU instances
    wire [2:0] a_b3;
    wire [6:0] a_oh;
    wire [5:0] a_t2;
    wire [2:0] a_hg;

    alu_bin3      u_a_b3 (.clk(clk), .rst(rst), .delta(delta), .state(a_b3));
    alu_onehot7   u_a_oh (.clk(clk), .rst(rst), .delta(delta), .state(a_oh));
    alu_trit2b    u_a_t2 (.clk(clk), .rst(rst), .delta(delta), .state(a_t2));
    alu_hex_gray3 u_a_hg (.clk(clk), .rst(rst), .delta(delta), .state(a_hg));

    // Canonical decoders to verify 100% functional equivalence
    function integer dec_b3; input [2:0] s; begin
        dec_b3 = (s <= 3'd6) ? s : -1;
    end endfunction

    function integer dec_oh; input [6:0] s; begin
        case (s)
            7'b0000001: dec_oh = 0;
            7'b0000010: dec_oh = 1;
            7'b0000100: dec_oh = 2;
            7'b0001000: dec_oh = 3;
            7'b0010000: dec_oh = 4;
            7'b0100000: dec_oh = 5;
            7'b1000000: dec_oh = 6;
            default:    dec_oh = -1;
        endcase
    end endfunction

    function integer dec_t2; input [5:0] s; begin
        case (s)
            6'b00_00_00: dec_t2 = 0;
            6'b01_00_11: dec_t2 = 1;
            6'b00_01_11: dec_t2 = 2;
            6'b11_01_00: dec_t2 = 3;
            6'b11_00_01: dec_t2 = 4;
            6'b00_11_01: dec_t2 = 5;
            6'b01_11_00: dec_t2 = 6;
            default:     dec_t2 = -1;
        endcase
    end endfunction

    function integer dec_hg; input [2:0] s; begin
        case (s)
            3'b000:  dec_hg = 0;
            3'b001:  dec_hg = 1;
            3'b011:  dec_hg = 2;
            3'b010:  dec_hg = 3;
            3'b110:  dec_hg = 4;
            3'b111:  dec_hg = 5;
            3'b101:  dec_hg = 6;
            default: dec_hg = -1;
        endcase
    end endfunction

    function integer popcnt7; input [6:0] x; begin
        popcnt7 = x[0] + x[1] + x[2] + x[3] + x[4] + x[5] + x[6];
    end endfunction

    // Counters for switching activity
    reg [2:0] prev_rb3, prev_rhg;
    reg [6:0] prev_roh;
    reg [5:0] prev_rt2;
    reg [2:0] prev_ab3, prev_ahg;
    reg [6:0] prev_aoh;
    reg [5:0] prev_at2;

    integer flips_rb3 = 0, flips_roh = 0, flips_rt2 = 0, flips_rhg = 0;
    integer multi_rb3 = 0, multi_roh = 0, multi_rt2 = 0, multi_rhg = 0;
    integer flips_ab3 = 0, flips_aoh = 0, flips_at2 = 0, flips_ahg = 0;
    integer eq_errors = 0;

    integer cyc, hd;
    reg [31:0] prng = 32'hCAFE_BEEF;

    // -------------------------------------------------------------------------
    // CDC + Wire Skew stress testbench section
    // -------------------------------------------------------------------------
    reg clk_dst = 1'b0;
    always #12.144 clk_dst = ~clk_dst; // ~41.17 MHz async to 27 MHz

    reg cdc_enable = 1'b0;
    reg [2:0] cdc_prev_rb3 = 3'd1, cdc_prev_rhg = 3'b001;
    reg [6:0] cdc_prev_roh = 7'b0000010;
    reg [5:0] cdc_prev_rt2 = 6'b01_00_11;

    // Realistic routing skew (0 ns, 1.4 ns, 2.8 ns, 4.2 ns across FPGA fabric)
    wire [2:0] skew_rb3;
    wire [6:0] skew_roh;
    wire [5:0] skew_rt2;
    wire [2:0] skew_rhg;

    assign #(0.0) skew_rb3[0] = r_b3[0];
    assign #(1.6) skew_rb3[1] = r_b3[1];
    assign #(3.2) skew_rb3[2] = r_b3[2];

    assign #(0.0) skew_roh[0] = r_oh[0];
    assign #(1.1) skew_roh[1] = r_oh[1];
    assign #(2.2) skew_roh[2] = r_oh[2];
    assign #(3.3) skew_roh[3] = r_oh[3];
    assign #(1.4) skew_roh[4] = r_oh[4];
    assign #(2.8) skew_roh[5] = r_oh[5];
    assign #(3.9) skew_roh[6] = r_oh[6];

    assign #(0.0) skew_rt2[0] = r_t2[0];
    assign #(1.2) skew_rt2[1] = r_t2[1];
    assign #(2.4) skew_rt2[2] = r_t2[2];
    assign #(3.6) skew_rt2[3] = r_t2[3];
    assign #(1.8) skew_rt2[4] = r_t2[4];
    assign #(3.0) skew_rt2[5] = r_t2[5];

    assign #(0.0) skew_rhg[0] = r_hg[0];
    assign #(1.6) skew_rhg[1] = r_hg[1];
    assign #(3.2) skew_rhg[2] = r_hg[2];

    reg [2:0] cap_b3;
    reg [6:0] cap_oh;
    reg [5:0] cap_t2;
    reg [2:0] cap_hg;

    integer cdc_samples = 0;
    integer cdc_err_b3 = 0, cdc_err_oh = 0, cdc_err_t2 = 0, cdc_err_hg = 0;
    integer cdc_ill_b3 = 0, cdc_ill_oh = 0, cdc_ill_t2 = 0, cdc_ill_hg = 0;
    integer d_cap, d_cur, d_prv;

    always @(posedge clk_dst) begin
        if (cdc_enable) begin
            cap_b3 = skew_rb3;
            cap_oh = skew_roh;
            cap_t2 = skew_rt2;
            cap_hg = skew_rhg;
            cdc_samples = cdc_samples + 1;

            d_cur = dec_b3(r_b3);
            d_prv = dec_b3(cdc_prev_rb3);
            d_cap = dec_b3(cap_b3);
            if (d_cap < 0) cdc_ill_b3 = cdc_ill_b3 + 1;
            if (d_cap != d_cur && d_cap != d_prv) cdc_err_b3 = cdc_err_b3 + 1;

            d_cur = dec_oh(r_oh);
            d_prv = dec_oh(cdc_prev_roh);
            d_cap = dec_oh(cap_oh);
            if (d_cap < 0) cdc_ill_oh = cdc_ill_oh + 1;
            if (d_cap != d_cur && d_cap != d_prv) cdc_err_oh = cdc_err_oh + 1;

            d_cur = dec_t2(r_t2);
            d_prv = dec_t2(cdc_prev_rt2);
            d_cap = dec_t2(cap_t2);
            if (d_cap < 0) cdc_ill_t2 = cdc_ill_t2 + 1;
            if (d_cap != d_cur && d_cap != d_prv) cdc_err_t2 = cdc_err_t2 + 1;

            d_cur = dec_hg(r_hg);
            d_prv = dec_hg(cdc_prev_rhg);
            d_cap = dec_hg(cap_hg);
            if (d_cap < 0) cdc_ill_hg = cdc_ill_hg + 1;
            if (d_cap != d_cur && d_cap != d_prv) cdc_err_hg = cdc_err_hg + 1;
        end
    end

    task check_equiv;
        begin
            if (dec_b3(r_b3) != dec_oh(r_oh) ||
                dec_b3(r_b3) != dec_t2(r_t2) ||
                dec_b3(r_b3) != dec_hg(r_hg) ||
                dec_b3(r_b3) < 0) begin
                eq_errors = eq_errors + 1;
            end
            if (dec_b3(a_b3) != dec_oh(a_oh) ||
                dec_b3(a_b3) != dec_t2(a_t2) ||
                dec_b3(a_b3) != dec_hg(a_hg) ||
                dec_b3(a_b3) < 0) begin
                eq_errors = eq_errors + 1;
            end
        end
    endtask

    initial begin
        // Reset
        rst = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // ---------------------------------------------------------------------
        // Benchmark 1: Sequential Ring Steps (+60 CCW / -60 CW, 10,000 cycles)
        // ---------------------------------------------------------------------
        prev_rb3 = r_b3; prev_roh = r_oh; prev_rt2 = r_t2; prev_rhg = r_hg;
        for (cyc = 0; cyc < 10000; cyc = cyc + 1) begin
            @(negedge clk);
            op = (cyc < 5000) ? 2'b01 : 2'b10;
            @(posedge clk);
            #1;
            check_equiv();

            hd = popcnt7({4'd0, r_b3 ^ prev_rb3});
            flips_rb3 = flips_rb3 + hd;
            if (hd > 1) multi_rb3 = multi_rb3 + 1;

            hd = popcnt7(r_oh ^ prev_roh);
            flips_roh = flips_roh + hd;
            if (hd > 1) multi_roh = multi_roh + 1;

            hd = popcnt7({1'b0, r_t2 ^ prev_rt2});
            flips_rt2 = flips_rt2 + hd;
            if (hd > 1) multi_rt2 = multi_rt2 + 1;

            hd = popcnt7({4'd0, r_hg ^ prev_rhg});
            flips_rhg = flips_rhg + hd;
            if (hd > 1) multi_rhg = multi_rhg + 1;

            prev_rb3 = r_b3; prev_roh = r_oh; prev_rt2 = r_t2; prev_rhg = r_hg;
        end

        $display("BENCH_RING_SEQ cycles=10000 eq_err=%0d", eq_errors);
        $display("  bin3      flips=%0d multi=%0d alpha=%.4f", flips_rb3, multi_rb3, flips_rb3 / 10000.0);
        $display("  onehot7   flips=%0d multi=%0d alpha=%.4f", flips_roh, multi_roh, flips_roh / 10000.0);
        $display("  trit2b    flips=%0d multi=%0d alpha=%.4f", flips_rt2, multi_rt2, flips_rt2 / 10000.0);
        $display("  hex_gray3 flips=%0d multi=%0d alpha=%.4f", flips_rhg, multi_rhg, flips_rhg / 10000.0);

        // ---------------------------------------------------------------------
        // Benchmark 2: Mixed Ring + ALU Operations (10,000 cycles)
        // ---------------------------------------------------------------------
        flips_rb3 = 0; flips_roh = 0; flips_rt2 = 0; flips_rhg = 0;
        multi_rb3 = 0; multi_roh = 0; multi_rt2 = 0; multi_rhg = 0;
        prev_rb3 = r_b3; prev_roh = r_oh; prev_rt2 = r_t2; prev_rhg = r_hg;
        prev_ab3 = a_b3; prev_aoh = a_oh; prev_at2 = a_t2; prev_ahg = a_hg;

        for (cyc = 0; cyc < 10000; cyc = cyc + 1) begin
            @(negedge clk);
            prng = {prng[30:0], prng[31] ^ prng[21] ^ prng[1] ^ prng[0]};
            // Weighted realistic mix: mostly +-1 steps, occasional center/hold
            case (prng[3:0])
                4'd0, 4'd1, 4'd2, 4'd3, 4'd4: op = 2'b01;
                4'd5, 4'd6, 4'd7, 4'd8, 4'd9: op = 2'b10;
                4'd10, 4'd11:                 op = 2'b11;
                default:                      op = 2'b00;
            endcase
            case (prng[7:5])
                3'd0:    delta = 3'd0;
                3'd1:    delta = 3'd1;
                3'd2:    delta = 3'd2;
                3'd3:    delta = 3'd5;
                3'd4:    delta = 3'd6;
                3'd5:    delta = 3'd7;
                3'd6:    delta = 3'd1;
                default: delta = 3'd6;
            endcase

            @(posedge clk);
            #1;
            check_equiv();

            hd = popcnt7({4'd0, r_b3 ^ prev_rb3}); flips_rb3 = flips_rb3 + hd; if (hd > 1) multi_rb3 = multi_rb3 + 1;
            hd = popcnt7(r_oh ^ prev_roh);         flips_roh = flips_roh + hd; if (hd > 1) multi_roh = multi_roh + 1;
            hd = popcnt7({1'b0, r_t2 ^ prev_rt2}); flips_rt2 = flips_rt2 + hd; if (hd > 1) multi_rt2 = multi_rt2 + 1;
            hd = popcnt7({4'd0, r_hg ^ prev_rhg}); flips_rhg = flips_rhg + hd; if (hd > 1) multi_rhg = multi_rhg + 1;

            flips_ab3 = flips_ab3 + popcnt7({4'd0, a_b3 ^ prev_ab3});
            flips_aoh = flips_aoh + popcnt7(a_oh ^ prev_aoh);
            flips_at2 = flips_at2 + popcnt7({1'b0, a_t2 ^ prev_at2});
            flips_ahg = flips_ahg + popcnt7({4'd0, a_hg ^ prev_ahg});

            prev_rb3 = r_b3; prev_roh = r_oh; prev_rt2 = r_t2; prev_rhg = r_hg;
            prev_ab3 = a_b3; prev_aoh = a_oh; prev_at2 = a_t2; prev_ahg = a_hg;
        end

        $display("BENCH_MIXED cycles=10000 eq_err=%0d", eq_errors);
        $display("  ring_bin3      flips=%0d multi=%0d alpha=%.4f", flips_rb3, multi_rb3, flips_rb3 / 10000.0);
        $display("  ring_onehot7   flips=%0d multi=%0d alpha=%.4f", flips_roh, multi_roh, flips_roh / 10000.0);
        $display("  ring_trit2b    flips=%0d multi=%0d alpha=%.4f", flips_rt2, multi_rt2, flips_rt2 / 10000.0);
        $display("  ring_hex_gray3 flips=%0d multi=%0d alpha=%.4f", flips_rhg, multi_rhg, flips_rhg / 10000.0);
        $display("  alu_bin3       flips=%0d alpha=%.4f", flips_ab3, flips_ab3 / 10000.0);
        $display("  alu_onehot7    flips=%0d alpha=%.4f", flips_aoh, flips_aoh / 10000.0);
        $display("  alu_trit2b     flips=%0d alpha=%.4f", flips_at2, flips_at2 / 10000.0);
        $display("  alu_hex_gray3  flips=%0d alpha=%.4f", flips_ahg, flips_ahg / 10000.0);

        // ---------------------------------------------------------------------
        // Benchmark 3: CDC + Routing Skew (50,000 ring steps)
        // ---------------------------------------------------------------------
        @(negedge clk);
        rst = 1'b1;
        op = 2'b01;
        @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        cdc_prev_rb3 = r_b3; cdc_prev_roh = r_oh; cdc_prev_rt2 = r_t2; cdc_prev_rhg = r_hg;
        #10;
        cdc_enable = 1'b1;

        for (cyc = 0; cyc < 50000; cyc = cyc + 1) begin
            @(negedge clk);
            cdc_prev_rb3 = r_b3;
            cdc_prev_roh = r_oh;
            cdc_prev_rt2 = r_t2;
            cdc_prev_rhg = r_hg;
            op = 2'b01;
            @(posedge clk);
        end
        cdc_enable = 1'b0;

        $display("BENCH_CDC_SKEW samples=%0d eq_err=%0d", cdc_samples, eq_errors);
        $display("  bin3      torn_words=%0d illegal_words=%0d err_rate_ppm=%.1f",
                 cdc_err_b3, cdc_ill_b3, (cdc_err_b3 * 1000000.0) / cdc_samples);
        $display("  onehot7   torn_words=%0d illegal_words=%0d err_rate_ppm=%.1f",
                 cdc_err_oh, cdc_ill_oh, (cdc_err_oh * 1000000.0) / cdc_samples);
        $display("  trit2b    torn_words=%0d illegal_words=%0d err_rate_ppm=%.1f",
                 cdc_err_t2, cdc_ill_t2, (cdc_err_t2 * 1000000.0) / cdc_samples);
        $display("  hex_gray3 torn_words=%0d illegal_words=%0d err_rate_ppm=%.1f",
                 cdc_err_hg, cdc_ill_hg, (cdc_err_hg * 1000000.0) / cdc_samples);

        $finish;
    end
endmodule
