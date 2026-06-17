// ============================================================
//  五级流水线 ID 阶段 — 支持完整 RV32I 指令集（除 FENCE/ECALL/EBREAK）
//
//  与单周期版的关键差异：
//    1. 条件分支（BEQ/BNE/BLT/BGE/BLTU/BGEU）不在 ID 评估跳转条件，
//       移至 EX 阶段用转发后的值判断，branch_type 3位编码传递给 ID/EX。
//    2. JALR 不在 ID 解析目标（需要 rs1 转发），jalr=1 信号传至 EX 处理。
//    3. 新增 write_pc4 信号：JALR 写回 PC+4 而非 ALU 结果。
//    4. branch_type 编码：
//         0=无  1=BEQ(sub==0)  2=BNE(sub!=0)
//         3=BLT(slt==1)  4=BGE(slt==0)
//         5=BLTU(sltu==1)  6=BGEU(sltu==0)
//    5. 对应 alu_op: BEQ/BNE 用 SUB(1), BLT/BGE 用 SLT(7), BLTU/BGEU 用 SLTU(8)
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
    output reg  [31:0] src1,        // 单周期兼容（流水线版不直接进 EX）
    output reg  [31:0] src2,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  src2_sel,    // 0=rs2, 1=imm, 2=pc(reserved), 3=4
    output reg         src1_sel,    // 0=rdata1, 1=PC（JAL/AUIPC）
    output reg         reg_we,
    output reg         mem_ce,
    output reg  [3:0]  mem_we,
    output reg         pc_we,       // 仅 JAL 置 1；条件分支/JALR 在 EX 处理
    output reg  [31:0] next_pc,     // 仅 JAL 有效
    output reg         inst_type,
    output reg  [2:0]  branch_type, // 3 位分支类型，传至 ID/EX 供 EX 判断
    output reg         jalr,        // JALR 标志，EX 阶段使用
    output reg         write_pc4,   // JALR：写回 PC+4 而非 ALU 结果
    output reg  [2:0]  load_func3,  // 传至 MEM 阶段区分 LB/LH/LW/LBU/LHU
    output reg  [2:0]  store_func3  // 传至 MEM 阶段区分 SB/SH/SW
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
        src1_sel    = 1'b0;
        reg_we      = 1'b0;
        mem_ce      = 1'b0;
        mem_we      = 4'b0;
        pc_we       = 1'b0;
        next_pc     = pc + 4;
        inst_type   = 1'b0;
        branch_type = 3'd0;
        jalr        = 1'b0;
        write_pc4   = 1'b0;
        imm         = 32'b0;
        src1        = rdata1;
        src2        = rdata2;
        load_func3  = func3;
        store_func3 = func3;

        case (opcode)
            // ---- R 型 ------------------------------------------------
            7'b0110011: begin
                reg_we   = 1'b1;
                src2_sel = 2'd0;
                src1     = rdata1;
                src2     = rdata2;
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
                    3'b000: alu_op = 4'd0;                      // ADDI
                    3'b010: alu_op = 4'd7;                      // SLTI
                    3'b011: alu_op = 4'd8;                      // SLTIU
                    3'b100: alu_op = 4'd4;                      // XORI
                    3'b110: alu_op = 4'd3;                      // ORI
                    3'b111: alu_op = 4'd2;                      // ANDI
                    3'b001: alu_op = 4'd5;                      // SLLI
                    3'b101: alu_op = func7[5] ? 4'd9 : 4'd6;   // SRAI/SRLI
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
                load_func3 = func3;
            end

            // ---- STORE -----------------------------------------------
            7'b0100011: begin
                mem_ce      = 1'b1;
                mem_we      = 4'b1111;
                src2_sel    = 2'd1;
                alu_op      = 4'd0;
                imm         = imm_s;
                src1        = rdata1;
                src2        = imm_s;
                store_func3 = func3;
            end

            // ---- 条件分支（EX 阶段用转发值判断，此处仅译码）----------
            7'b1100011: begin
                src2_sel  = 2'd0;   // EX 需要 rs2 参与运算
                imm       = imm_b;
                src1      = rdata1;
                src2      = rdata2;
                inst_type = 1'b1;
                // branch_type 决定 EX 如何判断跳转，alu_op 决定用哪种比较
                case (func3)
                    3'b000: begin branch_type = 3'd1; alu_op = 4'd1; end // BEQ: SUB==0
                    3'b001: begin branch_type = 3'd2; alu_op = 4'd1; end // BNE: SUB!=0
                    3'b100: begin branch_type = 3'd3; alu_op = 4'd7; end // BLT: SLT==1
                    3'b101: begin branch_type = 3'd4; alu_op = 4'd7; end // BGE: SLT==0
                    3'b110: begin branch_type = 3'd5; alu_op = 4'd8; end // BLTU: SLTU==1
                    3'b111: begin branch_type = 3'd6; alu_op = 4'd8; end // BGEU: SLTU==0
                    default: branch_type = 3'd0;
                endcase
            end

            // ---- JAL（ID 阶段直接跳转，目标已知）--------------------
            7'b1101111: begin
                rs1       = 5'b0;
                rs2       = 5'b0;
                reg_we    = 1'b1;
                src1_sel  = 1'b1;    // EX src1 = PC
                src2_sel  = 2'd3;    // EX src2 = 4 → alu_result = PC+4（返回地址）
                alu_op    = 4'd0;
                imm       = imm_j;
                src1      = pc;
                src2      = 32'd4;
                pc_we     = 1'b1;
                next_pc   = pc + imm_j;
                inst_type = 1'b1;
            end

            // ---- JALR（EX 阶段解析，需要转发 rs1）------------------
            7'b1100111: begin
                rs2       = 5'b0;
                reg_we    = 1'b1;
                src1_sel  = 1'b0;    // EX src1 = rs1（转发）
                src2_sel  = 2'd1;    // EX src2 = imm_i → alu_result = rs1+imm（目标）
                alu_op    = 4'd0;
                imm       = imm_i;
                src1      = rdata1;
                src2      = imm_i;
                jalr      = 1'b1;    // 通知 EX 跳转
                write_pc4 = 1'b1;    // WB 写回 PC+4 而非 alu_result
                inst_type = 1'b1;
            end

            // ---- LUI -------------------------------------------------
            7'b0110111: begin
                rs1      = 5'b0;
                rs2      = 5'b0;
                reg_we   = 1'b1;
                src1_sel = 1'b0;    // src1 = rdata1 = 0（rs1=x0）
                src2_sel = 2'd1;
                alu_op   = 4'd0;
                imm      = imm_u;
                src1     = 32'b0;
                src2     = imm_u;
            end

            // ---- AUIPC -----------------------------------------------
            7'b0010111: begin
                rs1      = 5'b0;
                rs2      = 5'b0;
                reg_we   = 1'b1;
                src1_sel = 1'b1;    // src1 = PC
                src2_sel = 2'd1;    // src2 = imm_u
                alu_op   = 4'd0;
                imm      = imm_u;
                src1     = pc;
                src2     = imm_u;
            end

            default: begin end
        endcase
    end

endmodule
