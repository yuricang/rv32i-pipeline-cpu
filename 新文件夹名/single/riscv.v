module riscv(

	input wire				 clk,
	input wire				 rst,

    // inst_mem
	input wire[31:0]         inst_i,
	output wire[31:0]        inst_addr_o,
	output wire              inst_ce_o,

    // data_mem
	input wire[31:0]         data_i,
	output wire[3:0]         data_we_o,
    output wire              data_ce_o,
	output wire[31:0]        data_addr_o,
	output wire[31:0]        data_o

);

	wire[31:0] pc;
	wire[31:0] pc_next;
	wire        pc_we;
	wire[31:0] next_pc;

	wire[4:0]  rs1, rs2, rd;
	wire[31:0] imm;
	wire[31:0] src1, src2;
	wire[3:0]  alu_op;
	wire[1:0]  src2_sel;
	wire        reg_we;
	wire        mem_ce;
	wire[3:0]  mem_we;
	wire        inst_type;
	wire[31:0] rdata1, rdata2;
	wire[2:0]  load_func3;    // 新增
	wire[2:0]  store_func3;   // 新增

	wire[31:0] alu_result;

	wire[31:0] mem_addr;
	wire[31:0] mem_wdata;
	wire[3:0]  mem_we_o;
	wire        mem_ce_o;
	wire[31:0] load_data;

	wire[31:0] wb_data;

	assign inst_ce_o   = 1'b1;
	assign inst_addr_o = pc;

	if_stage if_stage_inst(
		.clk(clk),
		.rst(rst),
		.next_pc(next_pc),
		.pc_we(pc_we),
		.pc(pc),
		.pc_next(pc_next)
	);

	register register_inst(
		.clk(clk),
		.rst(rst),
		.raddr1(rs1),
		.raddr2(rs2),
		.rdata1(rdata1),
		.rdata2(rdata2),
		.waddr(rd),
		.wdata(wb_data),
		.we(reg_we)
	);

	id_stage id_stage_inst(
		.inst(inst_i),
		.pc(pc),
		.rdata1(rdata1),
		.rdata2(rdata2),
		.rs1(rs1),
		.rs2(rs2),
		.rd(rd),
		.imm(imm),
		.src1(src1),
		.src2(src2),
		.alu_op(alu_op),
		.src2_sel(src2_sel),
		.reg_we(reg_we),
		.mem_ce(mem_ce),
		.mem_we(mem_we),
		.pc_we(pc_we),
		.next_pc(next_pc),
		.inst_type(inst_type),
		.load_func3(load_func3),    // 新增
		.store_func3(store_func3)   // 新增
	);

	ex_stage ex_stage_inst(
		.src1(src1),
		.src2(src2),
		.alu_op(alu_op),
		.alu_result(alu_result)
	);

	mem_stage mem_stage_inst(
		.addr(alu_result),
		.write_data(rdata2),
		.mem_we(mem_we),
		.store_func3(store_func3),   // 新增
		.load_func3(load_func3),     // 新增
		.mem_ce(mem_ce),
		.rdata(data_i),
		.mem_addr(mem_addr),
		.mem_wdata(mem_wdata),
		.mem_we_o(mem_we_o),
		.mem_ce_o(mem_ce_o),
		.load_data(load_data)
	);

	assign data_addr_o = mem_addr;
	assign data_o      = mem_wdata;
	assign data_we_o   = mem_we_o;
	assign data_ce_o   = mem_ce_o;

	// LOAD 写回 load_data；其余写回 ALU 结果
	assign wb_data = (mem_we == 4'b0 && mem_ce == 1'b1) ? load_data : alu_result;

endmodule
