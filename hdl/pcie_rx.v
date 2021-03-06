/*
 * HIFIFO: Harmon Instruments PCI Express to FIFO
 * Copyright (C) 2014 Harmon Instruments, LLC
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/
 */

`timescale 1ns / 1ps

module pcie_rx
  (
   input 	     clock,
   input 	     reset,
   // outputs
   output reg 	     write_valid = 0,
   output reg 	     completion_valid = 0,
   output reg [5:0]  completion_index = 0,
   output [7:0]      completion_tag,
   output reg [63:0] data = 0,
   output [5:0]      address,
   output [23:0]     rr_rid_tag,
   output [7:0]      rr_addr,
   output 	     rr_valid,
   input 	     rr_ready,
   // AXI stream from PCIE core
   input 	     tvalid,
   input 	     tlast,
   input [63:0]      tdata
   );

   function [31:0] es; // endian swap
      input [31:0]   x;
      es = {x[7:0], x[15:8], x[23:16], x[31:24]};
   endfunction

   reg [12:0] 	     address_q = 0;
   assign completion_tag = address_q[12:5];
   assign address = address_q[5:0];

   reg 		     tvalid_q = 0;
   reg [63:0] 	     tdata_q = 0;
   reg 		     tlast_q = 0;
   reg 		     wait_dw01 = 1;
   reg 		     wait_dw23 = 0;
   reg 		     wait_dw45 = 0;
   reg [31:0] 	     previous_dw = 0;
   reg 		     is_write_32 = 0;
   reg 		     is_cpld = 0;
   reg 		     is_read_32_1dw = 0;

   //assign rr_rc_dw2 = {rid_tag, 1'b0, rr_rc_lower_addr, 3'd0};

   always @ (posedge clock)
     begin
	tvalid_q <= tvalid;
	tlast_q <= tlast;
	tdata_q <= tdata;
	if(tvalid_q)
	  begin
	     data <= {es(tdata_q[31:0]), es(previous_dw[31:0])};
	     previous_dw <= tdata_q[63:32];
	     if(wait_dw01)
	       begin
		  is_write_32 <= tdata_q[30:24] == 7'b1000000;
		  is_cpld <= tdata_q[30:24] == 7'b1001010;
		  is_read_32_1dw <= (tdata_q[30:24] == 7'b0000000)
		    && (tdata_q[9:0] == 10'd1);
	       end
	     if(wait_dw23)
	       address_q <= tdata_q[15:3];
	     if(wait_dw01)
	       completion_index <= 6'h3F - {tdata_q[40:38],3'd0};
	     else if(wait_dw45)
	       completion_index <= completion_index + 1'b1;
	  end
	if(reset || (tvalid_q && tlast_q))
	  {wait_dw45, wait_dw23, wait_dw01} <= 3'b001;
	else if(tvalid_q & wait_dw01)
	  {wait_dw45, wait_dw23, wait_dw01} <= 3'b010;
	else if(tvalid_q && wait_dw23)
	  {wait_dw45, wait_dw23, wait_dw01} <= 3'b100;
	write_valid <= is_write_32 && wait_dw45 && tvalid_q;
	completion_valid <= is_cpld && wait_dw45 && tvalid_q;
     end

   fwft_fifo #(.NBITS(32)) read_fifo
     (
      .reset(reset),
      .i_clock(clock),
      // RID (16), tag (8), addr[9:2]
      .i_data({previous_dw[31:8], tdata_q[9:2]}),
      .i_valid(is_read_32_1dw && wait_dw23 && tvalid_q),
      .i_ready(),
      .o_clock(clock),
      .o_read(rr_ready),
      .o_data({rr_rid_tag, rr_addr}),
      .o_valid(rr_valid),
      .o_almost_empty()
      );

endmodule