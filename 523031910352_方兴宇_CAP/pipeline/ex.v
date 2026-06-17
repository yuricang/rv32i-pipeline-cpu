module ex_stage(
    input  wire [31:0] src1,
    input  wire [31:0] src2,
    input  wire [3:0]  alu_op,
    output reg  [31:0] alu_result
);

    always @(*) begin
        case (alu_op)
            4'd0: alu_result = src1 + src2;
            4'd1: alu_result = src1 - src2;
            4'd2: alu_result = src1 & src2;
            4'd3: alu_result = src1 | src2;
            4'd4: alu_result = src1 ^ src2;
            4'd5: alu_result = src1 << src2[4:0];
            4'd6: alu_result = src1 >> src2[4:0];
            4'd7: alu_result = ($signed(src1) < $signed(src2)) ? 32'd1 : 32'd0;
            4'd8: alu_result = (src1 < src2) ? 32'd1 : 32'd0;
            4'd9: alu_result = $signed(src1) >>> src2[4:0];
            default: alu_result = 32'b0;
        endcase
    end

endmodule
