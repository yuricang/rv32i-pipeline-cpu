module register(
    input wire clk,
    input wire rst,

    // 读操作（ID 阶段）
    input wire [4:0]  raddr1,
    input wire [4:0]  raddr2,
    output reg [31:0] rdata1,
    output reg [31:0] rdata2,

    // 写操作（WB 阶段）
    input wire [4:0]  waddr,
    input wire [31:0] wdata,
    input wire        we
);

    reg [31:0] regs [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    // 写操作（同步，WB 阶段在时钟上升沿写入）
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && waddr != 5'b0) begin
            regs[waddr] <= wdata;
        end
    end

    // 读操作（纯组合逻辑，无写优先逻辑）
    // 距离3拍的 WB→ID RAW 冲突由 riscv.v 的 ID/EX 捕获转发解决，
    // 此处不再需要写优先路径，消除了长组合链导致的建立时间违例。
    always @(*) begin
        rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
        rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];
    end

endmodule
