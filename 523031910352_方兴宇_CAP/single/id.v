// ============================================================
//  单周期 ID 阶段 — 支持完整 RV32I 指令集（除 FENCE/ECALL/EBREAK）
//
//  新增相对原版的指令：
//    R型  : SLT, SLTU, SRA
//    I型  : SLTI, SLTIU, SRAI, JALR
//    U型  : LUI, AUIPC
//    B型  : BNE, BGE, BGEU, BLTU
//    访存 : LB, LH, LBU, LHU, SB, SH
// ============================================================
module id_stage(
    input  wire [31:0] inst,
    input  wire [31:0] pc,
    input  wire [31:0] rdata1,
    input  wire [31:0] rdata2,

    output reg  [4:0]  rs1,
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,
    output reg  [31:0] imm,
    output reg  [31:0] src1,
    output reg  [31:0] src2,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  src2_sel,
    output reg         reg_we,
    output reg         mem_ce,
    output reg  [3:0]  mem_we,
    output reg         pc_we,
    output reg  [31:0] next_pc,
    output reg         inst_type,
    output reg  [2:0]  load_func3,   // func3 传至 MEM 阶段区分 LB/LH/LW/LBU/LHU
    output reg  [2:0]  store_func3   // func3 传至 MEM 阶段区分 SB/SH/SW
);

    wire [6:0] opcode = inst[6:0];
    wire [2:0] func3  = inst[14:12];
    wire [6:0] func7  = inst[31:25];

    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};
    wire [31:0] imm_j = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

    always @(*) begin
        // 默认值（NOP）
        rs1         = inst[19:15];
        rs2         = inst[24:20];
        rd          = inst[11:7];
        alu_op      = 4'b0;
        src2_sel    = 2'd0;
        reg_we      = 1'b0;
        mem_ce      = 1'b0;
        mem_we      = 4'b0;
        pc_we       = 1'b0;
        next_pc     = pc + 4;
        inst_type   = 1'b0;
        imm         = 32'b0;
        src1        = rdata1;
        src2        = rdata2;
        load_func3  = func3;
        store_func3 = func3;

        case (opcode)
            // ---- R 型 ------------------------------------------------
            7'b0110011: begin
                reg_we = 1'b1;
                src1   = rdata1;
                src2   = rdata2;
                case ({func7[5], func3})
                    4'b0000: alu_op = 4'd0;  // ADD
                    4'b1000: alu_op = 4'd1;  // SUB
                    4'b0111: alu_op = 4'd2;  // AND
                    4'b0110: alu_op = 4'd3;  // OR
                    4'b0100: alu_op = 4'd4;  // XOR
                    4'b0001: alu_op = 4'd5;  // SLL
                    4'b0101: alu_op = 4'd6;  // SRL
                    4'b1101: alu_op = 4'd9;  // SRA
                    4'b0010: alu_op = 4'd7;  // SLT
                    4'b0011: alu_op = 4'd8;  // SLTU
                    default: alu_op = 4'd0;
                endcase
            end

            // ---- I 型算术/逻辑 ----------------------------------------
            7'b0010011: begin
                reg_we   = 1'b1;
                src2_sel = 2'd1;
                imm      = imm_i;
                src1     = rdata1;
                src2     = imm_i;
                case (func3)
                    3'b000: alu_op = 4'd0;                           // ADDI
                    3'b010: alu_op = 4'd7;                           // SLTI
                    3'b011: alu_op = 4'd8;                           // SLTIU
                    3'b100: alu_op = 4'd4;                           // XORI
                    3'b110: alu_op = 4'd3;                           // ORI
                    3'b111: alu_op = 4'd2;                           // ANDI
                    3'b001: alu_op = 4'd5;                           // SLLI
                    3'b101: alu_op = func7[5] ? 4'd9 : 4'd6;        // SRAI / SRLI
                    default: alu_op = 4'd0;
                endcase
            end

            // ---- LOAD ------------------------------------------------
            7'b0000011: begin
                reg_we     = 1'b1;
                mem_ce     = 1'b1;
                src2_sel   = 2'd1;
                alu_op     = 4'd0;
                imm        = imm_i;
                src1       = rdata1;
                src2       = imm_i;
                load_func3 = func3;   // LB/LH/LW/LBU/LHU
            end

            // ---- STORE -----------------------------------------------
            7'b0100011: begin
                mem_ce      = 1'b1;
                mem_we      = 4'b1111;   // 标记为 STORE，mem 阶段按 store_func3 选字节使能
                src2_sel    = 2'd1;
                alu_op      = 4'd0;
                imm         = imm_s;
                src1        = rdata1;
                src2        = imm_s;
                store_func3 = func3;     // SB/SH/SW
            end

            // ---- 条件分支 ---------------------------------------------
            7'b1100011: begin
                pc_we     = 1'b1;
                src1      = rdata1;
                src2      = rdata2;
                imm       = imm_b;
                inst_type = 1'b1;
                case (func3)
                    3'b000: next_pc = (rdata1 == rdata2)                     ? (pc + imm_b) : (pc + 4);
                    3'b001: next_pc = (rdata1 != rdata2)                     ? (pc + imm_b) : (pc + 4);
                    3'b100: next_pc = ($signed(rdata1) <  $signed(rdata2))   ? (pc + imm_b) : (pc + 4);
                    3'b101: next_pc = ($signed(rdata1) >= $signed(rdata2))   ? (pc + imm_b) : (pc + 4);
                    3'b110: next_pc = (rdata1 <  rdata2)                     ? (pc + imm_b) : (pc + 4);
                    3'b111: next_pc = (rdata1 >= rdata2)                     ? (pc + imm_b) : (pc + 4);
                    default: next_pc = pc + 4;
                endcase
            end

            // ---- JAL -------------------------------------------------
            7'b1101111: begin
                rs1       = 5'b0;
                rs2       = 5'b0;
                reg_we    = 1'b1;
                alu_op    = 4'd0;
                imm       = imm_j;
                src1      = pc;
                src2      = 32'd4;
                pc_we     = 1'b1;
                next_pc   = pc + imm_j;
                inst_type = 1'b1;
            end

            // ---- JALR ------------------------------------------------
            7'b1100111: begin
                rs2       = 5'b0;
                reg_we    = 1'b1;
                alu_op    = 4'd0;
                imm       = imm_i;
                src1      = pc;            // ALU 计算 PC+4 作为返回地址写回 rd
                src2      = 32'd4;
                pc_we     = 1'b1;
                next_pc   = (rdata1 + imm_i) & ~32'h1;
                inst_type = 1'b1;
            end

            // ---- LUI -------------------------------------------------
            7'b0110111: begin
                rs1    = 5'b0;
                rs2    = 5'b0;
                reg_we = 1'b1;
                alu_op = 4'd0;
                imm    = imm_u;
                src1   = 32'b0;
                src2   = imm_u;
            end

            // ---- AUIPC -----------------------------------------------
            7'b0010111: begin
                rs1    = 5'b0;
                rs2    = 5'b0;
                reg_we = 1'b1;
                alu_op = 4'd0;
                imm    = imm_u;
                src1   = pc;
                src2   = imm_u;
            end

            default: begin end
        endcase
    end

endmodule
