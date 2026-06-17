module if_stage(
    input wire clk,
    input wire rst,
    
    // 来自控制单元
    input wire[31:0] next_pc,  // 下一个PC（来自分支/跳转）
    input wire pc_we,           // PC写使能（1=跳转，0=顺序执行）
    
    // 输出
    output reg[31:0] pc,        // 当前PC
    output wire[31:0] pc_next   // 下一条指令的PC（顺序执行时）
);

    assign pc_next = pc + 4;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'b0;
        end else begin
            if (pc_we) begin
                pc <= next_pc;  // 跳转
            end else begin
                pc <= pc_next;  // 顺序执行
            end
        end
    end

endmodule
