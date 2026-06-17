module register(
    input wire clk,
    input wire rst,
    
    // 读操作
    input wire[4:0] raddr1,  // 读地址1
    input wire[4:0] raddr2,  // 读地址2
    output reg[31:0] rdata1, // 读数据1
    output reg[31:0] rdata2, // 读数据2
    
    // 写操作
    input wire[4:0] waddr,   // 写地址
    input wire[31:0] wdata,  // 写数据
    input wire we            // 写使能
);

    reg[31:0] regs[0:31];
    integer i;
    
    // 初始化寄存器
    initial begin
        for(i = 0; i < 32; i = i + 1) begin
            regs[i] = 32'b0;
        end
    end
    
    // 写操作（同步）
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for(i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (we && waddr != 5'b0) begin  // x0寄存器不可写
            regs[waddr] <= wdata;
        end
    end
    
    // 读操作（组合逻辑）
    always @(*) begin
        rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
        rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];
    end

endmodule
