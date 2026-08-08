`timescale 1ns / 1ps

module spi_master #(parameter DATA_WIDTH=8)
( input wire clk,
  input wire rst_n,
  input wire spi_en,
  input wire cpol,
  input wire cpha,
  input wire [7:0] clk_div,
  
  input wire [DATA_WIDTH-1:0] tx_data,
  output reg [DATA_WIDTH-1:0] rx_data,
  
  output reg busy,
  output reg done,
  output reg sclk,
  output reg mosi,
  output reg ss_n,
  input wire miso
);

localparam [1:0] S_IDLE = 2'b00,
                 S_LOAD = 2'b01,
                 S_SHIFT = 2'b10,
                 S_DONE = 2'b11;
                 
//INTERNAL REGISTER
reg [1:0] state;
reg [DATA_WIDTH-1:0] tx_shift;
reg [DATA_WIDTH-1:0] rx_shift;
reg [7:0] div_cnt;//clock divider down counter
reg [3:0] bit_cnt;//Number of bits captured

wire sample_on_pos = ~(cpol ^ cpha); //clock mode

wire sclk_toggle = (state == S_SHIFT) && (div_cnt == clk_div - 8'd1);
wire pos_edge = sclk_toggle && (~sclk); //0 -> 1
wire neg_edge = sclk_toggle && (sclk); //1 -> 0

wire sample_edge = sample_on_pos ? pos_edge : neg_edge;
wire shift_edge = sample_on_pos ? neg_edge : pos_edge;

always @(posedge clk) begin
if(!rst_n) begin
    div_cnt <= 8'b0;
    sclk    <= 1'b0;
    end else begin
    if (state == S_SHIFT) begin
        if (div_cnt == clk_div - 8'b1) begin
            div_cnt <= 8'b0;
            sclk <= ~sclk;
          end else begin
            div_cnt <= div_cnt + 8'b1;
          end
      end else begin
          div_cnt <= 8'b0;
          sclk <= cpol;
      end
   end
end       

always @(posedge clk) begin
if(!rst_n) begin
   state  <= S_IDLE;
   tx_shift <= {DATA_WIDTH{1'b0}};
   rx_shift <= {DATA_WIDTH{1'b0}};
   rx_data  <= {DATA_WIDTH{1'b0}};
   bit_cnt  <= 4'b0;
   mosi     <= 1'b0;
   ss_n     <= 1'b1;
   busy     <= 1'b0;
   done     <= 1'b0;
end else begin
   
   done <= 1'b0; //done is always 0 unless pulsed in S_DONE
   
   case (state)
   
   S_IDLE: begin
           ss_n <= 1'b1;
           busy <= 1'b0;
           mosi <= 1'b0;
           if (spi_en)
           state <= S_LOAD;
           end
           
   S_LOAD: begin
           tx_shift <= tx_data;
           rx_shift <= {DATA_WIDTH{1'b0}};
           bit_cnt  <= 4'd0;
           ss_n     <= 1'b0;
           busy     <= 1'b1;
           
           if(!cpha)
           mosi <= tx_data[DATA_WIDTH-1];
           state <= S_SHIFT;
           end
           
    S_SHIFT: begin
          if(sample_edge) begin
            if (bit_cnt == DATA_WIDTH-1) begin
            rx_data <= {rx_shift[DATA_WIDTH-2:0],miso};
            ss_n <= 1'b1;
            state <= S_DONE;
          end else begin
            rx_shift <= {rx_shift[DATA_WIDTH-2:0],miso};
            bit_cnt <= bit_cnt + 4'd1;
          end
          end 
          
          if (shift_edge) begin
          if(!cpha) begin
             mosi <= tx_shift[DATA_WIDTH-2];
             end else begin
             mosi <= tx_shift[DATA_WIDTH-1];
             end
             tx_shift <= {tx_shift[DATA_WIDTH-2:0],1'b0};
             end
             end
 
 S_DONE: begin
        ss_n <= 1'b1;
        busy <= 1'b0;
        done <= 1'b1;
        state <= S_IDLE;
        end
        default: state <= S_IDLE;
        
      endcase
   end
end               
endmodule
