module pcie_tx
  (
   input 	 clock,
   input 	 reset,
   input [15:0]  pcie_id,
   // read completion (rc)
   input 	 rc_done,
   input [31:0]  rc_dw2,
   input [63:0]  rc_data,
   // read request (rr)
   input 	 rr_valid,
   input [63:0]  rr_addr,
   input [7:0] 	 rr_tag,
   output 	 rr_ready,
   // write request (wr)
   input 	 wr_valid,
   input [63:0]  wr_addr,
   output 	 wr_ready, // pulses 16 times in request of the next data value
   input [63:0]  wr_data,
   // AXI stream to PCI Express core
   input 	 tx_tready,
   output [63:0] tx_tdata,
   output 	 tx_1dw,
   output	 tx_tlast,
   output 	 tx_tvalid
   );

   function [31:0] es; // endian swap
      input [31:0]   x;
      es = {x[7:0], x[15:8], x[23:16], x[31:24]};
   endfunction

   reg [63:0] 	     wr_data_q;
   
   reg 		     rc_valid;
   wire 	     rc_ready;
   
   reg [4:0] 	     state = 0;
   wire 	     rr_is_32 = rr_addr[63:32] == 0;
   wire 	     wr_is_32 = wr_addr[63:32] == 0;
   reg 		     wr_is_32_q = 0;
   assign rc_ready = (state == 3);
   assign rr_ready = (state == 5);
   assign wr_ready = ((state > 5) && (state < 22));
   wire 	     fi_ready;
   reg [65:0] 	     fi_data;
   reg 		     fi_valid = 0;
   
   always @(posedge clock)
     begin
	if(reset)
	  rc_valid <= 1'b0;
	else if(rc_done)
	  rc_valid <= 1'b1;
	else if(rc_ready)
	  rc_valid <= 1'b0;
	if(reset)
	  state <= 5'd0;
	else
	  case(state)
	    0:  state <= fi_ready ? ((rc_valid & (state != 3)) ? 3'd1 : (rr_valid ? 3'd4 : (wr_valid ? 3'd6 : 3'd0))) : 1'b0;
	    3:  state <= fi_ready ? ((rc_valid & (state != 3)) ? 3'd1 : (rr_valid ? 3'd4 : (wr_valid ? 3'd6 : 3'd0))) : 1'b0;
	    5:  state <= fi_ready ? ((rc_valid & (state != 3)) ? 3'd1 : (rr_valid ? 3'd0 : (wr_valid ? 3'd6 : 3'd0))) : 1'b0;
	    23: state <= fi_ready ? ((rc_valid & (state != 3)) ? 3'd1 : (rr_valid ? 3'd4 : (wr_valid ? 3'd6 : 3'd0))) : 1'b0;
	    default: state <= state + 1'b1;
	  endcase
	if(state == 6)
	  wr_is_32_q <= wr_is_32;
	wr_data_q <= wr_data;
	fi_valid <= state != 0;
	case(state)
	  // idle
	  0: fi_data <= 1'b0;
	  // read completion (rc)
	  1: fi_data <= {2'b00, pcie_id, 16'd8, 32'h4A000002}; // always 2 DW
	  2: fi_data <= {2'b00, es(rc_data[31:0]), rc_dw2}; // rc DW3, DW2
	  3: fi_data <= {2'b11, 32'h0, es(rc_data[63:32])}; // rc DW4
	  // read request (rr)
	  4: fi_data <= {2'b00, pcie_id, rr_tag[7:0], 8'hFF, 2'd0, ~rr_is_32, 29'd128}; // always 128 DW
	  5: fi_data <= rr_is_32 ? {2'b11, rr_addr[31:0], rr_addr[31:0]} : {2'b01, rr_addr[31:0], rr_addr[63:32]};
	  // write request (wr)
	  6: fi_data <= {2'b00, pcie_id, 16'h00FF, 2'b01, ~wr_is_32, 29'd32}; // always 32 DW
	  7: fi_data <= wr_is_32_q ? {2'b00, es(wr_data[31:0]), wr_addr[31:0]} : {2'b00, wr_addr[31:0], wr_addr[63:32]};
	  default: fi_data <= wr_is_32_q ? {2'b00, es(wr_data[31:0]), es(wr_data_q[63:32])} : {2'b00, es(wr_data_q[63:32]),es(wr_data_q[31:0])};
	  23: fi_data <= wr_is_32_q ? {2'b11, es(wr_data[31:0]), es(wr_data_q[63:32])} : {2'b01,es(wr_data_q[63:32]),es(wr_data_q[31:0])};
	endcase
     end

   fwft_fifo #(.NBITS(66)) tx_fifo
     (
      .reset(reset),
      .i_clock(clock),
      .i_data(fi_data),
      .i_valid(fi_valid),
      .i_ready(fi_ready),
      .o_clock(clock),
      .o_read(tx_tready & tx_tvalid),
      .o_data({tx_1dw, tx_tlast, tx_tdata}),
      .o_valid(tx_tvalid),
      .o_almost_empty()
      );

endmodule
