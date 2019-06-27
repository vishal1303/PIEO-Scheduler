// synopsys translate_off
`timescale 1 ns / 1 ps
// synopsys translate_on

module alt_ram
  #(
    parameter RAM_WIDTH = 1,
    parameter RAM_ADDR_BITS = 1,
    parameter USE_OUTPUT_REGISTER = 0,
    parameter INIT_FILE = ""
    )
    (
	address_a,
	address_b,
	clock,
	data_a,
	data_b,
	rden_a,
	rden_b,
	wren_a,
	wren_b,
	q_a,
	q_b);

	input	[RAM_ADDR_BITS-1:0]  address_a;
	input	[RAM_ADDR_BITS-1:0]  address_b;
	input	  clock;
	input	[RAM_WIDTH-1:0]  data_a;
	input	[RAM_WIDTH-1:0]  data_b;
	input	  rden_a;
	input	  rden_b;
	input	  wren_a;
	input	  wren_b;
	output	[RAM_WIDTH-1:0]  q_a;
	output	[RAM_WIDTH-1:0]  q_b;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri1	  clock;
	tri1	  rden_a;
	tri1	  rden_b;
	tri0	  wren_a;
	tri0	  wren_b;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

   localparam 	  OUT_REG = (USE_OUTPUT_REGISTER) ? "CLOCK0" : "UNREGISTERED";


	wire [RAM_WIDTH-1:0] sub_wire0;
	wire [RAM_WIDTH-1:0] sub_wire1;
	wire [RAM_WIDTH-1:0] q_a = sub_wire0[RAM_WIDTH-1:0];
	wire [RAM_WIDTH-1:0] q_b = sub_wire1[RAM_WIDTH-1:0];

	altsyncram	altsyncram_component (
				.clock0 (clock),
				.wren_a (wren_a),
				.address_b (address_b),
				.data_b (data_b),
				.rden_a (rden_a),
				.wren_b (wren_b),
				.address_a (address_a),
				.data_a (data_a),
				.rden_b (rden_b),
				.q_a (sub_wire0),
				.q_b (sub_wire1),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.eccstatus ());
	defparam
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK0",
`ifdef NO_PLI
		altsyncram_component.init_file = "somefile.rif"
`else
		altsyncram_component.init_file = INIT_FILE
`endif
,
		altsyncram_component.intended_device_family = "Stratix V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**RAM_ADDR_BITS,
		altsyncram_component.numwords_b = 2**RAM_ADDR_BITS,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = OUT_REG,
		altsyncram_component.outdata_reg_b = OUT_REG,
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = RAM_ADDR_BITS,
		altsyncram_component.widthad_b = RAM_ADDR_BITS,
		altsyncram_component.width_a = RAM_WIDTH,
		altsyncram_component.width_b = RAM_WIDTH,
		altsyncram_component.width_byteena_a = 1,
		altsyncram_component.width_byteena_b = 1,
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";

endmodule

module dual_port_bram #
(
	parameter RAM_WIDTH = 32,
	parameter RAM_ADDR_BITS = 10,
	parameter RAM_LINES = (2**RAM_ADDR_BITS),
	parameter USE_OUTPUT_REGISTER = 0,
	parameter INIT_FILE = ""
)
(
	input clk,

	input  [RAM_WIDTH-1:0] Data_In_A,
	input  [RAM_ADDR_BITS-1:0] Addr_A,
	input  En_A,
	input  Wen_A,
	output [RAM_WIDTH-1:0] Data_Out_A,

	input  [RAM_WIDTH-1:0] Data_In_B,
	input  [RAM_ADDR_BITS-1:0] Addr_B,
	input  En_B,
	input  Wen_B,
	output [RAM_WIDTH-1:0] Data_Out_B

);


alt_ram #(
	.RAM_WIDTH( RAM_WIDTH ),
	.RAM_ADDR_BITS( RAM_ADDR_BITS ),
	.USE_OUTPUT_REGISTER( USE_OUTPUT_REGISTER ),
	.INIT_FILE( INIT_FILE )
)
bram
(
	.clock( clk ),

	.address_a( Addr_A ),
	.rden_a( En_A  & ~Wen_A ),
	.wren_a( En_A & Wen_A ),
	.data_a( Data_In_A ),
	.q_a( Data_Out_A ),

	.address_b( Addr_B ),
	.rden_b( En_B & ~Wen_B),
	.wren_b( En_B & Wen_B ),
	.data_b( Data_In_B ),
	.q_b( Data_Out_B )
);

endmodule
