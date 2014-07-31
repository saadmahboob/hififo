module pcie_from_pc_fifo
  (
   input 	    clock,
   input 	    reset,
   output reg [1:0] interrupt = 0,
   output [63:0]    status, 
   // PIO
   input 	    pio_wvalid,
   input [63:0]     pio_wdata,
   input [12:0]     pio_addr, 
   // read completion
   input 	    rc_valid,
   input [7:0] 	    rc_tag,
   input [5:0] 	    rc_index,
   input [63:0]     rc_data,
   // read request
   output 	    rr_valid,
   output [63:0]    rr_addr,
   output [7:0]     rr_tag,
   input 	    rr_ready,
   // FIFO
   input 	    fifo_clock, // for all FIFO signals
   input 	    fifo_read,
   output [63:0]    fifo_read_data,
   output 	    fifo_read_valid
   );

   // clock
   reg [42:0] 	     pt [31:0];
   reg [42:0] 	     pt_q;
   reg [7:0] 	     block_filled = 0;
   reg [2:0] 	     p_read = 0;
   reg [16:0] 	     p_write = 0;
   reg [16:0] 	     p_request = 0;
   reg [16:0] 	     p_stop = 0;
   reg [16:0] 	     p_int = 0;
   wire  	     write = (rc_tag[7:3] == 0) && rc_valid;
   wire [8:0] 	     write_address = {rc_tag[2:0],rc_index};
   wire 	     write_last = write && (rc_index == 6'h3F);
   wire [2:0] 	     prp2 = p_request[2:0] + 2'd2;
   assign rr_valid = ~rr_ready & (prp2 != p_read[2:0]) & (p_request != p_stop);
   assign rr_addr = {pt_q, p_request[11:0], 9'd0};
   assign rr_tag = p_request[2:0];
   assign status = {p_write, 9'd0};
   wire 	     p_read_6_clk, p_read_inc128;
   
   always @ (posedge clock)
     begin
	pt_q <= pt[p_request[16:12]];
	if(pio_wvalid && (pio_addr[12:5] == 2))
	  pt[pio_addr[4:0]] <= pio_wdata[63:21];
	if(reset)
	  block_filled <= 8'd0;
	else
	  begin
	     block_filled[0] <= (write_last && (rc_tag == 0)) || ((p_write[2:0] == 0) ? 1'b0 : block_filled[0]);
	     block_filled[1] <= (write_last && (rc_tag == 1)) || ((p_write[2:0] == 1) ? 1'b0 : block_filled[1]);
	     block_filled[2] <= (write_last && (rc_tag == 2)) || ((p_write[2:0] == 2) ? 1'b0 : block_filled[2]);
	     block_filled[3] <= (write_last && (rc_tag == 3)) || ((p_write[2:0] == 3) ? 1'b0 : block_filled[3]);
	     block_filled[4] <= (write_last && (rc_tag == 4)) || ((p_write[2:0] == 4) ? 1'b0 : block_filled[4]);
	     block_filled[5] <= (write_last && (rc_tag == 5)) || ((p_write[2:0] == 5) ? 1'b0 : block_filled[5]);
	     block_filled[6] <= (write_last && (rc_tag == 6)) || ((p_write[2:0] == 6) ? 1'b0 : block_filled[6]);
	     block_filled[7] <= (write_last && (rc_tag == 7)) || ((p_write[2:0] == 7) ? 1'b0 : block_filled[7]);
	  end
	p_stop <= reset ? 1'b0 : (pio_wvalid && (pio_addr == 6) ? pio_wdata[25:9] : p_stop);
	p_int <= reset ? 1'b0 : (pio_wvalid && (pio_addr == 7) ? pio_wdata[25:9] : p_int);
	p_read <= reset ? 1'b0 : p_read + p_read_inc128;
	p_write <= reset ? 1'b0 : p_write + block_filled[p_write[2:0]];
	p_request <= reset ? 1'b0 : p_request + rr_ready;
	interrupt <= {(p_stop == p_write), (p_int == p_write)};
     end
   
   oneshot_dualedge oneshot0(.clock(clock), .in(p_read_6_clk), .out(p_read_inc128));

   // fifo_clock
   wire [8:0] 	  p_read_fclk;
   wire [2:0] 	  p_write_fclk;
   wire 	  reset_fclk;
   gray_sync_3 sync0(.clock_in(clock), .in(p_write[2:0]), .clock_out(fifo_clock), .out(p_write_fclk));
   sync sync1(.clock(clock), .in(p_read_fclk[6]), .out(p_read_6_clk));
   sync sync_reset(.clock(fifo_clock), .in(reset), .out(reset_fclk));
   
   fwft_out fwft_out
     (.clock_in(clock),
      .d_in(rc_data),
      .a_in(write_address),
      .w_in(write),
      .clock(fifo_clock),
      .reset(reset_fclk),
      .p_in({p_write_fclk,6'd0}),
      .p_out(p_read_fclk),
      .d_out(fifo_read_data),
      .v_out(fifo_read_valid),
      .r_out(fifo_read));

endmodule

module fwft_out
  (
   // clock_in domain - write data only
   input 	    clock_in,
   input [63:0]     d_in,
   input [8:0] 	    a_in,
   input 	    w_in,
   // clock domain
   input 	    clock,
   input 	    reset, 
   input [8:0] 	    p_in, // pointer in
   output reg [8:0] p_out, // pointer out
   output [63:0]    d_out,
   output 	    v_out,
   input 	    r_out);
   
   reg [63:0] 	     fifo_bram [511:0];
   
   always @ (posedge clock_in)
     begin
	if(w_in)
	  fifo_bram[a_in] <= d_in;
     end

   reg [63:0] 	  a_data, b_data;
   reg 		  a_valid = 0, b_valid = 0;
   
   wire 	  a_cken = (p_out != p_in) && (~a_valid | ~b_valid | r_out);
   wire 	  b_cken = a_valid && (~b_valid | r_out);

   assign v_out = b_valid;
   assign d_out = b_data;
      
   always @ (posedge clock)
     begin
	if(reset)
	  begin
	     p_out <= 1'b0;
	     a_valid <= 1'b0;
	     b_valid <= 1'b0;
	  end
	else
	  begin
	     // a stage
	     p_out <= p_out + a_cken;
	     if(a_cken)
	       a_data <= fifo_bram[p_out];
	     a_valid <= a_cken | (a_valid && ~b_cken);
	     // b stage
	     if(b_cken)
	       b_data <= a_data;
	     b_valid <= b_cken | (b_valid && ~r_out);
	  end
     end
endmodule


