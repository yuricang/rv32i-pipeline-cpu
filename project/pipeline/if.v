module if_stage(
    input wire clk,
    input wire rst,

    // 来自控制单元
    input wire [31:0] next_pc,  // 跳转目标 PC（来自分支/跳转）
    input wire        pc_we,    // 跳转使能（1=分支/跳转，0=顺序执行）
    input wire        stall,    // 流水线阻塞（Load-Use 冲突时冻结 PC）

    // 输出
    output reg  [31:0] pc,      // 当前 PC
    output wire [31:0] pc_next  // 顺序下一条指令的 PC
);

    assign pc_next = pc + 4;

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc <= 32'b0;
        else if (stall)
            pc <= pc;           // 阻塞：保持 PC 不变（优先级最高）
        else if (pc_we)
            pc <= next_pc;      // 跳转/分支
        else
            pc <= pc_next;      // 顺序执行
    end

endmodule
