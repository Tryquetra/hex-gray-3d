`timescale 1ns/1ps

// Four state-encoding implementations sharing identical 7-state ring semantics:
//   idx 0: Centro (0, 0, 0)
//   idx 1..6: Ring 0, 60, 120, 180, 240, 300 deg
//   op: 2'b00 = hold, 2'b01 = +60 CCW, 2'b10 = -60 CW, 2'b11 = toggle/jump Centro

// -----------------------------------------------------------------------------
// 1. BIN3 (Natural 3-bit binary: 0..6, 7 unused)
// -----------------------------------------------------------------------------
module ring_bin3 (
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] op,
    output reg  [2:0] state = 3'd1
);
    reg [2:0] nxt;
    always @(*) begin
        case (op)
            2'b00: nxt = state;
            2'b01: begin // +60 CCW
                case (state)
                    3'd1: nxt = 3'd2;
                    3'd2: nxt = 3'd3;
                    3'd3: nxt = 3'd4;
                    3'd4: nxt = 3'd5;
                    3'd5: nxt = 3'd6;
                    3'd6: nxt = 3'd1;
                    3'd0: nxt = 3'd1;
                    default: nxt = 3'd1;
                endcase
            end
            2'b10: begin // -60 CW
                case (state)
                    3'd1: nxt = 3'd6;
                    3'd6: nxt = 3'd5;
                    3'd5: nxt = 3'd4;
                    3'd4: nxt = 3'd3;
                    3'd3: nxt = 3'd2;
                    3'd2: nxt = 3'd1;
                    3'd0: nxt = 3'd3;
                    default: nxt = 3'd1;
                endcase
            end
            2'b11: nxt = (state == 3'd0) ? 3'd1 : 3'd0;
        endcase
    end
    always @(posedge clk) begin
        if (rst) state <= 3'd1;
        else     state <= nxt;
    end
endmodule

// -----------------------------------------------------------------------------
// 2. ONEHOT7 (7-bit One-Hot: bit 0 = Centro, bits 1..6 = Ring 1..6)
// -----------------------------------------------------------------------------
module ring_onehot7 (
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] op,
    output reg  [6:0] state = 7'b0000010
);
    reg [6:0] nxt;
    always @(*) begin
        case (op)
            2'b00: nxt = state;
            2'b01: begin // +60 CCW
                if (state[0])
                    nxt = 7'b0000010;
                else
                    nxt = {state[5:1], state[6], 1'b0};
            end
            2'b10: begin // -60 CW
                if (state[0])
                    nxt = 7'b0001000;
                else
                    nxt = {state[1], state[6:2], 1'b0};
            end
            2'b11: nxt = state[0] ? 7'b0000010 : 7'b0000001;
        endcase
    end
    always @(posedge clk) begin
        if (rst) state <= 7'b0000010;
        else     state <= nxt;
    end
endmodule

// -----------------------------------------------------------------------------
// 3. TRIT2B_CUBE (6-bit standard binary-coded cube trits {q, r, s}, 2 bits/trit)
// Encoding per trit: 00 = 0, 01 = +1, 11 = -1 (10 unused)
// -----------------------------------------------------------------------------
module ring_trit2b (
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] op,
    output reg  [5:0] state = 6'b01_00_11
);
    localparam [5:0] C_CTR = 6'b00_00_00;
    localparam [5:0] C_R1  = 6'b01_00_11;
    localparam [5:0] C_R2  = 6'b00_01_11;
    localparam [5:0] C_R3  = 6'b11_01_00;
    localparam [5:0] C_R4  = 6'b11_00_01;
    localparam [5:0] C_R5  = 6'b00_11_01;
    localparam [5:0] C_R6  = 6'b01_11_00;

    reg [5:0] nxt;
    always @(*) begin
        case (op)
            2'b00: nxt = state;
            2'b01: begin
                case (state)
                    C_R1:    nxt = C_R2;
                    C_R2:    nxt = C_R3;
                    C_R3:    nxt = C_R4;
                    C_R4:    nxt = C_R5;
                    C_R5:    nxt = C_R6;
                    C_R6:    nxt = C_R1;
                    C_CTR:   nxt = C_R1;
                    default: nxt = C_R1;
                endcase
            end
            2'b10: begin
                case (state)
                    C_R1:    nxt = C_R6;
                    C_R6:    nxt = C_R5;
                    C_R5:    nxt = C_R4;
                    C_R4:    nxt = C_R3;
                    C_R3:    nxt = C_R2;
                    C_R2:    nxt = C_R1;
                    C_CTR:   nxt = C_R3;
                    default: nxt = C_R1;
                endcase
            end
            2'b11: nxt = (state == C_CTR) ? C_R1 : C_CTR;
        endcase
    end
    always @(posedge clk) begin
        if (rst) state <= C_R1;
        else     state <= nxt;
    end
endmodule

// -----------------------------------------------------------------------------
// 4. HEX_GRAY3 (3-bit Hexagonal Gray Code: 1-bit transitions along Q3 6-cycle)
// -----------------------------------------------------------------------------
module ring_hex_gray3 (
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] op,
    output reg  [2:0] state = 3'b001
);
    reg [2:0] nxt;
    always @(*) begin
        case (op)
            2'b00: nxt = state;
            2'b01: begin
                case (state)
                    3'b001: nxt = 3'b011;
                    3'b011: nxt = 3'b010;
                    3'b010: nxt = 3'b110;
                    3'b110: nxt = 3'b111;
                    3'b111: nxt = 3'b101;
                    3'b101: nxt = 3'b001;
                    3'b000: nxt = 3'b001;
                    3'b100: nxt = 3'b101;
                endcase
            end
            2'b10: begin
                case (state)
                    3'b001: nxt = 3'b101;
                    3'b101: nxt = 3'b111;
                    3'b111: nxt = 3'b110;
                    3'b110: nxt = 3'b010;
                    3'b010: nxt = 3'b011;
                    3'b011: nxt = 3'b001;
                    3'b000: nxt = 3'b010;
                    3'b100: nxt = 3'b110;
                endcase
            end
            2'b11: nxt = (state == 3'b000) ? 3'b001 : 3'b000;
        endcase
    end
    always @(posedge clk) begin
        if (rst) state <= 3'b001;
        else     state <= nxt;
    end
endmodule

// =============================================================================
// ALU / Multi-step Phase Accumulator Workload (delta in {-2,-1,0,+1,+2} or CTR)
// delta[2:0]: 0=0, 1=+1, 2=+2, 5=-2, 6=-1, 7=jump Centro
// =============================================================================
module alu_bin3 (
    input  wire       clk,
    input  wire       rst,
    input  wire [2:0] delta,
    output reg  [2:0] state = 3'd1
);
    reg [2:0] nxt;
    wire [2:0] base_idx = (state == 3'd0 || state == 3'd7) ? 3'd0 : (state - 3'd1);
    reg [3:0] sum_mod;
    always @(*) begin
        if (delta == 3'd7) begin
            nxt = 3'd0;
        end else if (state == 3'd0 || state == 3'd7) begin
            case (delta)
                3'd0:    nxt = 3'd0;
                3'd1:    nxt = 3'd1;
                3'd2:    nxt = 3'd2;
                3'd5:    nxt = 3'd5;
                3'd6:    nxt = 3'd6;
                default: nxt = 3'd1;
            endcase
        end else begin
            case (delta)
                3'd0:    sum_mod = {1'b0, base_idx};
                3'd1:    sum_mod = {1'b0, base_idx} + 4'd1;
                3'd2:    sum_mod = {1'b0, base_idx} + 4'd2;
                3'd5:    sum_mod = {1'b0, base_idx} + 4'd4;
                3'd6:    sum_mod = {1'b0, base_idx} + 4'd5;
                default: sum_mod = {1'b0, base_idx};
            endcase
            if (sum_mod >= 4'd6) nxt = sum_mod[2:0] - 3'd6 + 3'd1;
            else                 nxt = sum_mod[2:0] + 3'd1;
        end
    end
    always @(posedge clk) begin
        if (rst) state <= 3'd1;
        else     state <= nxt;
    end
endmodule

module alu_onehot7 (
    input  wire       clk,
    input  wire       rst,
    input  wire [2:0] delta,
    output reg  [6:0] state = 7'b0000010
);
    wire [5:0] ring = state[6:1];
    reg  [6:0] nxt;
    always @(*) begin
        if (delta == 3'd7) begin
            nxt = 7'b0000001;
        end else if (state[0]) begin
            case (delta)
                3'd0:    nxt = 7'b0000001;
                3'd1:    nxt = 7'b0000010;
                3'd2:    nxt = 7'b0000100;
                3'd5:    nxt = 7'b0100000;
                3'd6:    nxt = 7'b1000000;
                default: nxt = 7'b0000010;
            endcase
        end else begin
            case (delta)
                3'd0:    nxt = {ring, 1'b0};
                3'd1:    nxt = {ring[4:0], ring[5], 1'b0};
                3'd2:    nxt = {ring[3:0], ring[5:4], 1'b0};
                3'd5:    nxt = {ring[1:0], ring[5:2], 1'b0};
                3'd6:    nxt = {ring[0],   ring[5:1], 1'b0};
                default: nxt = {ring, 1'b0};
            endcase
        end
    end
    always @(posedge clk) begin
        if (rst) state <= 7'b0000010;
        else     state <= nxt;
    end
endmodule

module alu_trit2b (
    input  wire       clk,
    input  wire       rst,
    input  wire [2:0] delta,
    output reg  [5:0] state = 6'b01_00_11
);
    function [2:0] dec; input [5:0] s; begin
        case (s)
            6'b00_00_00: dec = 3'd0;
            6'b01_00_11: dec = 3'd1;
            6'b00_01_11: dec = 3'd2;
            6'b11_01_00: dec = 3'd3;
            6'b11_00_01: dec = 3'd4;
            6'b00_11_01: dec = 3'd5;
            6'b01_11_00: dec = 3'd6;
            default:     dec = 3'd0;
        endcase
    end endfunction

    function [5:0] enc; input [2:0] i; begin
        case (i)
            3'd0:    enc = 6'b00_00_00;
            3'd1:    enc = 6'b01_00_11;
            3'd2:    enc = 6'b00_01_11;
            3'd3:    enc = 6'b11_01_00;
            3'd4:    enc = 6'b11_00_01;
            3'd5:    enc = 6'b00_11_01;
            3'd6:    enc = 6'b01_11_00;
            default: enc = 6'b00_00_00;
        endcase
    end endfunction

    reg [2:0] idx;
    reg [3:0] sum_mod;
    reg [5:0] nxt;
    always @(*) begin
        idx = dec(state);
        if (delta == 3'd7) begin
            nxt = enc(3'd0);
        end else if (idx == 3'd0) begin
            case (delta)
                3'd0:    nxt = enc(3'd0);
                3'd1:    nxt = enc(3'd1);
                3'd2:    nxt = enc(3'd2);
                3'd5:    nxt = enc(3'd5);
                3'd6:    nxt = enc(3'd6);
                default: nxt = enc(3'd1);
            endcase
        end else begin
            case (delta)
                3'd0:    sum_mod = {1'b0, idx - 3'd1};
                3'd1:    sum_mod = {1'b0, idx - 3'd1} + 4'd1;
                3'd2:    sum_mod = {1'b0, idx - 3'd1} + 4'd2;
                3'd5:    sum_mod = {1'b0, idx - 3'd1} + 4'd4;
                3'd6:    sum_mod = {1'b0, idx - 3'd1} + 4'd5;
                default: sum_mod = {1'b0, idx - 3'd1};
            endcase
            if (sum_mod >= 4'd6) nxt = enc(sum_mod[2:0] - 3'd6 + 3'd1);
            else                 nxt = enc(sum_mod[2:0] + 3'd1);
        end
    end
    always @(posedge clk) begin
        if (rst) state <= 6'b01_00_11;
        else     state <= nxt;
    end
endmodule

module alu_hex_gray3 (
    input  wire       clk,
    input  wire       rst,
    input  wire [2:0] delta,
    output reg  [2:0] state = 3'b001
);
    function [2:0] dec; input [2:0] s; begin
        case (s)
            3'b000: dec = 3'd0;
            3'b001: dec = 3'd1;
            3'b011: dec = 3'd2;
            3'b010: dec = 3'd3;
            3'b110: dec = 3'd4;
            3'b111: dec = 3'd5;
            3'b101: dec = 3'd6;
            default: dec = 3'd0;
        endcase
    end endfunction

    function [2:0] enc; input [2:0] i; begin
        case (i)
            3'd0:    enc = 3'b000;
            3'd1:    enc = 3'b001;
            3'd2:    enc = 3'b011;
            3'd3:    enc = 3'b010;
            3'd4:    enc = 3'b110;
            3'd5:    enc = 3'b111;
            3'd6:    enc = 3'b101;
            default: enc = 3'b100;
        endcase
    end endfunction

    reg [2:0] idx;
    reg [3:0] sum_mod;
    reg [2:0] nxt;
    always @(*) begin
        idx = dec(state);
        if (delta == 3'd7) begin
            nxt = 3'b000;
        end else if (idx == 3'd0) begin
            case (delta)
                3'd0:    nxt = enc(3'd0);
                3'd1:    nxt = enc(3'd1);
                3'd2:    nxt = enc(3'd2);
                3'd5:    nxt = enc(3'd5);
                3'd6:    nxt = enc(3'd6);
                default: nxt = enc(3'd1);
            endcase
        end else begin
            case (delta)
                3'd0:    sum_mod = {1'b0, idx - 3'd1};
                3'd1:    sum_mod = {1'b0, idx - 3'd1} + 4'd1;
                3'd2:    sum_mod = {1'b0, idx - 3'd1} + 4'd2;
                3'd5:    sum_mod = {1'b0, idx - 3'd1} + 4'd4;
                3'd6:    sum_mod = {1'b0, idx - 3'd1} + 4'd5;
                default: sum_mod = {1'b0, idx - 3'd1};
            endcase
            if (sum_mod >= 4'd6) nxt = enc(sum_mod[2:0] - 3'd6 + 3'd1);
            else                 nxt = enc(sum_mod[2:0] + 3'd1);
        end
    end
    always @(posedge clk) begin
        if (rst) state <= 3'b001;
        else     state <= nxt;
    end
endmodule

// =============================================================================
// Parameterized 64-lane routed array benchmark for nextpnr-himbaechel Fmax
// MODEL: 0=bin3, 1=onehot7, 2=trit2b, 3=hex_gray3
// MODE:  0=ring, 1=alu
// =============================================================================
module bank64_bench #(
    parameter integer MODEL = 3,
    parameter integer MODE  = 0
) (
    input  wire       I_clk,
    input  wire       I_rst,
    input  wire       I_ser_in,
    output reg        O_obs = 1'b0
);
    // 64-bit shift chain distributes distinct per-lane commands without LUT folding
    reg [191:0] cmd_sr = 192'hA55A_3C96_1234_5678_9ABC_DEF0_0F1E_2D3C_4B5A_6978_8796_A5B4;
    always @(posedge I_clk) begin
        if (I_rst) cmd_sr <= 192'hA55A_3C96_1234_5678_9ABC_DEF0_0F1E_2D3C_4B5A_6978_8796_A5B4;
        else       cmd_sr <= {cmd_sr[190:0], I_ser_in ^ cmd_sr[191] ^ cmd_sr[120] ^ cmd_sr[63]};
    end

    wire [63:0] lane_parity;
    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : gen_lane
            wire [1:0] op_i = cmd_sr[i*2 +: 2];
            wire [2:0] dlt_i_raw = cmd_sr[i*3 +: 3];
            wire [2:0] dlt_i = (dlt_i_raw == 3'd3) ? 3'd1 :
                               (dlt_i_raw == 3'd4) ? 3'd6 : dlt_i_raw;

            if (MODE == 0) begin : gen_ring
                if (MODEL == 0) begin : m_b3
                    wire [2:0] st;
                    ring_bin3 u (.clk(I_clk), .rst(I_rst), .op(op_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else if (MODEL == 1) begin : m_oh
                    wire [6:0] st;
                    ring_onehot7 u (.clk(I_clk), .rst(I_rst), .op(op_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else if (MODEL == 2) begin : m_t2
                    wire [5:0] st;
                    ring_trit2b u (.clk(I_clk), .rst(I_rst), .op(op_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else begin : m_hg
                    wire [2:0] st;
                    ring_hex_gray3 u (.clk(I_clk), .rst(I_rst), .op(op_i), .state(st));
                    assign lane_parity[i] = ^st;
                end
            end else begin : gen_alu
                if (MODEL == 0) begin : m_b3
                    wire [2:0] st;
                    alu_bin3 u (.clk(I_clk), .rst(I_rst), .delta(dlt_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else if (MODEL == 1) begin : m_oh
                    wire [6:0] st;
                    alu_onehot7 u (.clk(I_clk), .rst(I_rst), .delta(dlt_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else if (MODEL == 2) begin : m_t2
                    wire [5:0] st;
                    alu_trit2b u (.clk(I_clk), .rst(I_rst), .delta(dlt_i), .state(st));
                    assign lane_parity[i] = ^st;
                end else begin : m_hg
                    wire [2:0] st;
                    alu_hex_gray3 u (.clk(I_clk), .rst(I_rst), .delta(dlt_i), .state(st));
                    assign lane_parity[i] = ^st;
                end
            end
        end
    endgenerate

    always @(posedge I_clk) begin
        O_obs <= ^lane_parity;
    end
endmodule
