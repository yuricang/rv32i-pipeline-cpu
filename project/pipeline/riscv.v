// ============================================================
//  五级流水线 RISC-V 处理器顶层 — 支持完整 RV32I 指令集
//
//  流水线结构：
//    IF ─[IF/ID]─ ID ─[ID/EX]─ EX ─[EX/MEM]─ MEM ─[MEM/WB]─ WB
//
//  冲突处理策略：
//    ① Load-Use 数据冲突（stall_req）
//       检测：ID/EX 寄存器为 LOAD 且 ID 阶段指令依赖其结果
//       处理：冻结 PC、IF/ID；向 ID/EX 插入气泡，暂停 1 拍
//    ② 一般 RAW 数据冲突（转发 Forwarding）
//       EX/MEM→EX：解决距离 1 拍的写后读
//       MEM/WB→EX：解决距离 2 拍的写后读
//       ID/EX 捕获转发：解决距离 3 拍（WB 与 ID 同周期）
//    ③ 控制冲突（条件分支 / JALR）
//       检测：EX 阶段确认跳转（ex_branch_taken）
//       处理：冲刷 IF/ID 和 ID/EX，损失 2 拍
//    ④ 控制冲突（JAL）
//       检测：ID 阶段即可确认跳转（pc_we）
//       处理：冲刷 IF/ID，损失 1 拍
//    ⑤ JALR 写回
//       JALR 目标在 EX 计算（rs1+imm），返回地址 PC+4 经 write_pc4 链传至 WB
// ============================================================

module riscv(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] inst_i,
    output wire [31:0] inst_addr_o,
    output wire        inst_ce_o,

    input  wire [31:0] data_i,
    output wire [3:0]  data_we_o,
    output wire        data_ce_o,
    output wire [31:0] data_addr_o,
    output wire [31:0] data_o
);

    // ==========================================================
    // 信号声明
    // ==========================================================

    // IF 阶段
    wire [31:0] pc_if;
    wire        pc_we;          // JAL 在 ID 产生
    wire [31:0] next_pc;        // JAL 跳转目标
    wire        stall_req;

    // EX 阶段分支解析（条件分支 + JALR）
    wire        ex_branch_taken;
    wire [31:0] ex_branch_target;
    wire        pc_we_final     = ex_branch_taken | pc_we;
    wire [31:0] next_pc_final   = ex_branch_taken ? ex_branch_target : next_pc;

    // IF/ID 流水线寄存器
    reg  [31:0] if_id_inst;
    reg  [31:0] if_id_pc;

    // ID 阶段输出
    wire [4:0]  rs1, rs2, rd;
    wire [31:0] imm;
    wire [31:0] src1_id, src2_id;
    wire [3:0]  alu_op;
    wire [1:0]  src2_sel;
    wire        src1_sel;
    wire        reg_we_id;
    wire        mem_ce_id;
    wire [3:0]  mem_we_id;
    wire        inst_type_id;
    wire [2:0]  branch_type_id;
    wire        jalr_id;
    wire        write_pc4_id;
    wire [2:0]  load_func3_id;
    wire [2:0]  store_func3_id;
    wire [31:0] rdata1, rdata2;

    // ID/EX 流水线寄存器
    reg  [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg  [31:0] id_ex_rdata1, id_ex_rdata2;
    reg  [31:0] id_ex_imm;
    reg  [3:0]  id_ex_alu_op;
    reg  [1:0]  id_ex_src2_sel;
    reg         id_ex_src1_sel;
    reg         id_ex_reg_we;
    reg         id_ex_mem_ce;
    reg  [3:0]  id_ex_mem_we;
    reg  [31:0] id_ex_pc;
    reg  [2:0]  id_ex_branch_type;
    reg         id_ex_jalr;
    reg         id_ex_write_pc4;
    reg  [2:0]  id_ex_load_func3;
    reg  [2:0]  id_ex_store_func3;

    // EX 阶段
    wire [31:0] ex_rdata1_fwd;
    wire [31:0] ex_rdata2_fwd;
    wire [31:0] ex_src1, ex_src2;
    wire [31:0] alu_result;

    // EX/MEM 流水线寄存器
    reg  [4:0]  ex_mem_rd;
    reg  [31:0] ex_mem_alu_result;
    reg  [31:0] ex_mem_rdata2;
    reg         ex_mem_reg_we;
    reg         ex_mem_mem_ce;
    reg  [3:0]  ex_mem_mem_we;
    reg  [2:0]  ex_mem_load_func3;
    reg  [2:0]  ex_mem_store_func3;
    reg         ex_mem_write_pc4;
    reg  [31:0] ex_mem_return_pc;   // JALR 返回地址 = id_ex_pc + 4

    // MEM 阶段
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_we_o;
    wire        mem_ce_o;
    wire [31:0] load_data;

    // MEM/WB 流水线寄存器
    reg  [4:0]  mem_wb_rd;
    reg  [31:0] mem_wb_alu_result;
    reg  [31:0] mem_wb_load_data;
    reg         mem_wb_reg_we;
    reg         mem_wb_mem_ce;
    reg  [3:0]  mem_wb_mem_we;
    reg         mem_wb_write_pc4;
    reg  [31:0] mem_wb_return_pc;

    // WB
    wire [31:0] wb_data;

    assign inst_ce_o   = 1'b1;
    assign inst_addr_o = pc_if;

    // ==========================================================
    // ① IF 阶段
    // ==========================================================
    if_stage if_stage_inst(
        .clk     (clk),
        .rst     (rst),
        .next_pc (next_pc_final),
        .pc_we   (pc_we_final),
        .stall   (stall_req),
        .pc      (pc_if),
        .pc_next ()
    );

    // IF/ID 流水线寄存器
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_inst <= 32'b0;
            if_id_pc   <= 32'b0;
        end else if (stall_req) begin
            // Load-Use：冻结 IF/ID
            if_id_inst <= if_id_inst;
            if_id_pc   <= if_id_pc;
        end else if (ex_branch_taken) begin
            // 条件分支/JALR 冲刷：清空 IF 取入的错误指令
            if_id_inst <= 32'b0;
            if_id_pc   <= 32'b0;
        end else if (pc_we) begin
            // JAL 冲刷：清空 IF 取入的错误指令
            if_id_inst <= 32'b0;
            if_id_pc   <= 32'b0;
        end else begin
            if_id_inst <= inst_i;
            if_id_pc   <= pc_if;
        end
    end

    // ==========================================================
    // ② ID 阶段
    // ==========================================================
    register register_inst(
        .clk    (clk),
        .rst    (rst),
        .raddr1 (rs1),
        .raddr2 (rs2),
        .rdata1 (rdata1),
        .rdata2 (rdata2),
        .waddr  (mem_wb_rd),
        .wdata  (wb_data),
        .we     (mem_wb_reg_we)
    );

    id_stage id_stage_inst(
        .inst        (if_id_inst),
        .pc          (if_id_pc),
        .rdata1      (rdata1),
        .rdata2      (rdata2),
        .rs1         (rs1),
        .rs2         (rs2),
        .rd          (rd),
        .imm         (imm),
        .src1        (src1_id),
        .src2        (src2_id),
        .alu_op      (alu_op),
        .src2_sel    (src2_sel),
        .src1_sel    (src1_sel),
        .reg_we      (reg_we_id),
        .mem_ce      (mem_ce_id),
        .mem_we      (mem_we_id),
        .pc_we       (pc_we),
        .next_pc     (next_pc),
        .inst_type   (inst_type_id),
        .branch_type (branch_type_id),
        .jalr        (jalr_id),
        .write_pc4   (write_pc4_id),
        .load_func3  (load_func3_id),
        .store_func3 (store_func3_id)
    );

    // Load-Use 冲突检测
    assign stall_req = id_ex_mem_ce           &&
                       (id_ex_mem_we == 4'b0) &&
                       (id_ex_rd != 5'b0)     &&
                       ((id_ex_rd == rs1) || (id_ex_rd == rs2));

    // ID/EX 流水线寄存器
    always @(posedge clk or posedge rst) begin
        if (rst || stall_req) begin
            // 复位 或 Load-Use 阻塞：插入气泡
            id_ex_rs1         <= 5'b0;
            id_ex_rs2         <= 5'b0;
            id_ex_rd          <= 5'b0;
            id_ex_rdata1      <= 32'b0;
            id_ex_rdata2      <= 32'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= 4'b0;
            id_ex_src2_sel    <= 2'b0;
            id_ex_src1_sel    <= 1'b0;
            id_ex_reg_we      <= 1'b0;
            id_ex_mem_ce      <= 1'b0;
            id_ex_mem_we      <= 4'b0;
            id_ex_pc          <= 32'b0;
            id_ex_branch_type <= 3'b0;
            id_ex_jalr        <= 1'b0;
            id_ex_write_pc4   <= 1'b0;
            id_ex_load_func3  <= 3'b0;
            id_ex_store_func3 <= 3'b0;
        end else if (ex_branch_taken) begin
            // 条件分支/JALR 冲刷 ID/EX：清空 ID 阶段的错误指令
            id_ex_rs1         <= 5'b0;
            id_ex_rs2         <= 5'b0;
            id_ex_rd          <= 5'b0;
            id_ex_rdata1      <= 32'b0;
            id_ex_rdata2      <= 32'b0;
            id_ex_imm         <= 32'b0;
            id_ex_alu_op      <= 4'b0;
            id_ex_src2_sel    <= 2'b0;
            id_ex_src1_sel    <= 1'b0;
            id_ex_reg_we      <= 1'b0;
            id_ex_mem_ce      <= 1'b0;
            id_ex_mem_we      <= 4'b0;
            id_ex_pc          <= 32'b0;
            id_ex_branch_type <= 3'b0;
            id_ex_jalr        <= 1'b0;
            id_ex_write_pc4   <= 1'b0;
            id_ex_load_func3  <= 3'b0;
            id_ex_store_func3 <= 3'b0;
        end else begin
            id_ex_rs1         <= rs1;
            id_ex_rs2         <= rs2;
            id_ex_rd          <= rd;
            // 距离 3 拍 RAW：在 ID/EX 捕获时直接转发 WB 数据，避免写优先组合链
            id_ex_rdata1      <= (mem_wb_reg_we && mem_wb_rd == rs1 && mem_wb_rd != 5'b0)
                                  ? wb_data : rdata1;
            id_ex_rdata2      <= (mem_wb_reg_we && mem_wb_rd == rs2 && mem_wb_rd != 5'b0)
                                  ? wb_data : rdata2;
            id_ex_imm         <= imm;
            id_ex_alu_op      <= alu_op;
            id_ex_src2_sel    <= src2_sel;
            id_ex_src1_sel    <= src1_sel;
            id_ex_reg_we      <= reg_we_id;
            id_ex_mem_ce      <= mem_ce_id;
            id_ex_mem_we      <= mem_we_id;
            id_ex_pc          <= if_id_pc;
            id_ex_branch_type <= branch_type_id;
            id_ex_jalr        <= jalr_id;
            id_ex_write_pc4   <= write_pc4_id;
            id_ex_load_func3  <= load_func3_id;
            id_ex_store_func3 <= store_func3_id;
        end
    end

    // ==========================================================
    // ③ EX 阶段
    // ==========================================================

    // 数据转发（距离 1/2 拍）
    assign ex_rdata1_fwd =
        (id_ex_rs1 != 5'b0 && id_ex_rs1 == ex_mem_rd && ex_mem_reg_we) ? ex_mem_alu_result :
        (id_ex_rs1 != 5'b0 && id_ex_rs1 == mem_wb_rd && mem_wb_reg_we) ? wb_data            :
        id_ex_rdata1;

    assign ex_rdata2_fwd =
        (id_ex_rs2 != 5'b0 && id_ex_rs2 == ex_mem_rd && ex_mem_reg_we) ? ex_mem_alu_result :
        (id_ex_rs2 != 5'b0 && id_ex_rs2 == mem_wb_rd && mem_wb_reg_we) ? wb_data            :
        id_ex_rdata2;

    // ALU 操作数选择
    assign ex_src1 = id_ex_src1_sel ? id_ex_pc        : ex_rdata1_fwd;
    assign ex_src2 = (id_ex_src2_sel == 2'd0) ? ex_rdata2_fwd :
                     (id_ex_src2_sel == 2'd1) ? id_ex_imm      :
                     (id_ex_src2_sel == 2'd2) ? id_ex_pc       :
                                                 32'd4;

    ex_stage ex_stage_inst(
        .src1       (ex_src1),
        .src2       (ex_src2),
        .alu_op     (id_ex_alu_op),
        .alu_result (alu_result)
    );

    // ---- EX 阶段分支/JALR 解析 ----
    // branch_type 编码：
    //   1=BEQ(sub==0)  2=BNE(sub!=0)
    //   3=BLT(slt==1)  4=BGE(slt==0)
    //   5=BLTU(sltu==1) 6=BGEU(sltu==0)
    assign ex_branch_taken =
        (id_ex_branch_type == 3'd1 && alu_result == 32'd0)         ||  // BEQ
        (id_ex_branch_type == 3'd2 && alu_result != 32'd0)         ||  // BNE
        (id_ex_branch_type == 3'd3 && alu_result == 32'd1)         ||  // BLT (SLT=1)
        (id_ex_branch_type == 3'd4 && alu_result == 32'd0)         ||  // BGE (SLT=0)
        (id_ex_branch_type == 3'd5 && alu_result == 32'd1)         ||  // BLTU (SLTU=1)
        (id_ex_branch_type == 3'd6 && alu_result == 32'd0)         ||  // BGEU (SLTU=0)
        id_ex_jalr;                                                      // JALR 始终跳转

    assign ex_branch_target = id_ex_jalr ?
        (alu_result & ~32'h1) :        // JALR：(rs1+imm) & ~1（alu 已计算 rs1+imm）
        (id_ex_pc + id_ex_imm);        // 条件分支：PC + imm_b

    // EX/MEM 流水线寄存器
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_rd          <= 5'b0;
            ex_mem_alu_result  <= 32'b0;
            ex_mem_rdata2      <= 32'b0;
            ex_mem_reg_we      <= 1'b0;
            ex_mem_mem_ce      <= 1'b0;
            ex_mem_mem_we      <= 4'b0;
            ex_mem_load_func3  <= 3'b0;
            ex_mem_store_func3 <= 3'b0;
            ex_mem_write_pc4   <= 1'b0;
            ex_mem_return_pc   <= 32'b0;
        end else begin
            ex_mem_rd          <= id_ex_rd;
            ex_mem_alu_result  <= alu_result;
            ex_mem_rdata2      <= ex_rdata2_fwd;
            ex_mem_reg_we      <= id_ex_reg_we;
            ex_mem_mem_ce      <= id_ex_mem_ce;
            ex_mem_mem_we      <= id_ex_mem_we;
            ex_mem_load_func3  <= id_ex_load_func3;
            ex_mem_store_func3 <= id_ex_store_func3;
            ex_mem_write_pc4   <= id_ex_write_pc4;
            ex_mem_return_pc   <= id_ex_pc + 4;   // JALR 返回地址
        end
    end

    // ==========================================================
    // ④ MEM 阶段
    // ==========================================================
    mem_stage mem_stage_inst(
        .addr        (ex_mem_alu_result),
        .write_data  (ex_mem_rdata2),
        .mem_we      (ex_mem_mem_we),
        .store_func3 (ex_mem_store_func3),
        .load_func3  (ex_mem_load_func3),
        .mem_ce      (ex_mem_mem_ce),
        .rdata       (data_i),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_we_o    (mem_we_o),
        .mem_ce_o    (mem_ce_o),
        .load_data   (load_data)
    );

    assign data_addr_o = mem_addr;
    assign data_o      = mem_wdata;
    assign data_we_o   = mem_we_o;
    assign data_ce_o   = mem_ce_o;

    // MEM/WB 流水线寄存器
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_rd         <= 5'b0;
            mem_wb_alu_result <= 32'b0;
            mem_wb_load_data  <= 32'b0;
            mem_wb_reg_we     <= 1'b0;
            mem_wb_mem_ce     <= 1'b0;
            mem_wb_mem_we     <= 4'b0;
            mem_wb_write_pc4  <= 1'b0;
            mem_wb_return_pc  <= 32'b0;
        end else begin
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_load_data  <= load_data;
            mem_wb_reg_we     <= ex_mem_reg_we;
            mem_wb_mem_ce     <= ex_mem_mem_ce;
            mem_wb_mem_we     <= ex_mem_mem_we;
            mem_wb_write_pc4  <= ex_mem_write_pc4;
            mem_wb_return_pc  <= ex_mem_return_pc;
        end
    end

    // ==========================================================
    // ⑤ WB 阶段
    // ==========================================================
    // 优先级：JALR 返回地址 > LOAD 数据 > ALU 结果
    assign wb_data = mem_wb_write_pc4                            ? mem_wb_return_pc    :
                     (mem_wb_mem_we == 4'b0 && mem_wb_mem_ce)   ? mem_wb_load_data    :
                                                                    mem_wb_alu_result;

endmodule
