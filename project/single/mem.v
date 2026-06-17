// ============================================================
//  MEM 阶段 — 支持字节/半字/字的访存
//
//  data_mem 是字节寻址存储器，addr 直接作为字节地址传入。
//
//  LOAD 提取规则（data_mem 返回 {data[addr+3],...,data[addr]}）：
//    LB  (load_func3=000)：sign_ext(rdata[7:0])
//    LH  (load_func3=001)：sign_ext(rdata[15:0])
//    LW  (load_func3=010)：rdata
//    LBU (load_func3=100)：zero_ext(rdata[7:0])
//    LHU (load_func3=101)：zero_ext(rdata[15:0])
//
//  STORE 字节使能（mem_we==4'b1111 表示"有写操作"，实际使能由 store_func3 决定）：
//    SB  (store_func3=000)：we=4'b0001, 写 data_i[7:0]  到 data[addr]
//    SH  (store_func3=001)：we=4'b0011, 写 data_i[15:0] 到 data[addr..addr+1]
//    SW  (store_func3=010)：we=4'b1111, 写全字
// ============================================================
module mem_stage(
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire [3:0]  mem_we,          // 0000=load/非访存, 1111=任意 STORE
    input  wire [2:0]  store_func3,     // 000=SB, 001=SH, 010=SW
    input  wire [2:0]  load_func3,      // 000=LB, 001=LH, 010=LW, 100=LBU, 101=LHU
    input  wire        mem_ce,
    input  wire [31:0] rdata,

    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output reg  [3:0]  mem_we_o,
    output reg         mem_ce_o,
    output reg  [31:0] load_data
);

    // 内存直接使用字节地址；写数据始终是 write_data（字节使能选择有效字节）
    assign mem_addr  = addr;
    assign mem_wdata = write_data;

    always @(*) begin
        mem_ce_o  = mem_ce;
        load_data = rdata;

        // ---- STORE 字节使能 ----
        if (mem_we == 4'b1111 && mem_ce) begin
            case (store_func3[1:0])
                2'b00:   mem_we_o = 4'b0001;   // SB
                2'b01:   mem_we_o = 4'b0011;   // SH
                default: mem_we_o = 4'b1111;   // SW
            endcase
        end else begin
            mem_we_o = 4'b0000;
        end

        // ---- LOAD 数据提取 ----
        if (mem_we == 4'b0 && mem_ce) begin
            case (load_func3)
                3'b000: load_data = {{24{rdata[7]}},  rdata[7:0]};    // LB
                3'b001: load_data = {{16{rdata[15]}}, rdata[15:0]};   // LH
                3'b010: load_data = rdata;                              // LW
                3'b100: load_data = {24'b0, rdata[7:0]};               // LBU
                3'b101: load_data = {16'b0, rdata[15:0]};              // LHU
                default: load_data = rdata;
            endcase
        end
    end

endmodule
