`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/12/06 18:53:48
// Design Name: 
// Module Name: sram_ctr_ahb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module sram(
    input clka,
    input ena,
    input wea,//low effective
    input [11:0]addra,
    input [31:0]dina,
    output wire [31:0]douta
    );
    reg [31:0] ram[4095:0];
    reg [31:0] dout;
    assign douta = dout;
    always@(negedge clka)begin
        //douta=ena;
        if (!ena) begin 
            if (!wea)begin 
            ram[addra] = dina;
            end
            dout = ram[addra];       
        end
        else dout = 32'bz;
    end
endmodule

module sram_ctr_ahb(
    input hclk,hresetn,hwrite,
    input [1:0]htrans, //NONSEQ,SEQ,IDLE,BUSY
    input [2:0]hsize, //每一个transfer传输的数据大小，以字节为单位，最高支持1024位
    input [31:0]haddr,
    input [2:0]hburst,//burst类型，支持4、8、16 burst，incrementing/wrapping
    input [31:0]hwdata,//data from master
    output reg hready,//1:slave 发出传输结束,0:slave需要延长传输周期,发至Master
    output reg [1:0]hresp,//slave发给Master的总线传输状态OKAY、ERROR、RETRY、SPLIT
    output reg [31:0]hrdata,//data to master
    output sram_csn,sram_wen,//sram chip select enable
    output [11:0]sram_a,//sram为4k大小
    output [31:0]sram_d,//data to sram
    input  [31:0]sram_q//data from sram
    );
    //internal registers
    reg       hwrite_r;
    reg[2:0]  hsize_r;
    //reg[2:0]  hburst_r;
    reg[1:0]  htrans_r;
    reg[31:0] haddr_r; //寻址只能是32位，但地址空间16K,仅低14位有效，13:12两位片选信号，11:0一块sram的寻址数据
    reg[9:0] trans_size;
    reg[5:0] tmp_index;
    reg[5:0] all_index;
    reg[31:0] data_from_ahb;//hwdata,input
    reg[31:0] data_to_ahb;//hrdata,output
    reg[31:0] data_from_sram;//sram_q,input
    reg[31:0] data_to_sram;//sram_d,output    
    
    //internal signals
    wire[1:0] haddr_sel;//地址高两位，选择sram
    wire sram_write;
    wire sram_read;
    
    parameter IDLE=2'b00,BUSY=2'b01,NONSEQ=2'b10,SEQ=2'b11;//htrans
    parameter OKAY=2'b00,ERROR=2'b01,RETRY=2'b10,SPLIT=2'b11;//hresp
    parameter BYTE=3'b000,HALFWORD=3'b001,WORD=3'b010,DWORD=3'b011,FOURWORD=3'b100,EIGHTWORD=3'b101,HALFMAX=3'b110,MAX=3'b111;
    assign sram_d = data_from_ahb;
    //                       {sram_}:
    //generate sram write and read enable signals
    assign sram_write = ((htrans == NONSEQ)||(htrans == SEQ)) && hwrite;
    assign sram_read = ((htrans == NONSEQ)||(htrans == SEQ)) && (!hwrite);
    assign sram_wen = !sram_write;
    assign sram_csn = !(sram_write || sram_read);
    //generate sram address
    //assign sram_addr = haddr_r [13:0];//all 16K
    reg [11:0] sram_addr_out;
    assign sram_a = sram_addr_out;//4K
    
    initial begin
        tmp_index=0;
        all_index=0;
        hready = 1;//1:slave 发出传输结束,0:slave需要延长传输周期,发至Master
        hresp = 2'b0;//slave发给Master的总线传输状态OKAY、ERROR、RETRY、SPLIT
        hrdata = 32'b0;//data to master
    end
    //assign bank_sel = (sram_csn && (sram_addr[13]==1'b0))?1'b1:1'b0; 
    //                                
   always@(posedge hclk or negedge hresetn)begin
     if(!hresetn)begin
       hwrite_r = 1'b0;
       hsize_r = 3'b0;
       htrans_r = 2'b0;
       haddr_r = 32'b0;
     end
     else if(hready)begin//sram已可以传输数据
       hwrite_r = hwrite;
       hsize_r = hsize;
       htrans_r = htrans;
       haddr_r = haddr;
     end
     else begin
       hwrite_r = 1'b0;
       hsize_r = 3'b0;
       htrans_r = 2'b0;
       haddr_r = 32'b0;
     end
   end 
   always@(posedge hclk)begin//讨论hburst和hsize
     case(hsize)
     BYTE:begin//single
         all_index=4;
         data_from_ahb = hwdata;
         data_from_sram = sram_q;
         hrdata = data_from_sram;
         sram_addr_out = haddr[11:0];
         hready=1; 
         tmp_index = (tmp_index+1)%all_index;
     end
     HALFWORD:begin
         all_index=2;
         data_from_ahb = hwdata;
         data_from_sram = sram_q;
         hrdata = data_from_sram;
         sram_addr_out = haddr[11:0];
         hready=1;
         tmp_index = !tmp_index;
     end
     WORD:begin
         all_index=1;
         data_from_ahb = hwdata;
         data_from_sram = sram_q;
         hrdata = data_from_sram;
         sram_addr_out = haddr[11:0];
         tmp_index = 1;
         hready=1;
     end
     DWORD:begin
        all_index=2;
        data_from_ahb = hwdata;
        data_from_sram = sram_q;
        hrdata = data_from_sram;
        if(hready)sram_addr_out = haddr[11:0];
        if(!tmp_index) hready=0;//起点
        else begin hready=1;sram_addr_out = sram_addr_out + 12'h1;end
        tmp_index = !tmp_index;
     end
     FOURWORD:begin
         all_index=4;
         data_from_ahb = hwdata;
         data_from_sram = sram_q;
         hrdata = data_from_sram;
         if(hready)sram_addr_out = haddr[11:0];
         if(!tmp_index)hready=0;
         else if (tmp_index==3)begin hready=1;sram_addr_out = sram_addr_out + 12'h1;end//终点
         else begin hready=0;sram_addr_out = sram_addr_out + 12'h1;end
         tmp_index = (tmp_index+1)%all_index;     
     end
     EIGHTWORD:begin
          all_index=8;
          data_from_ahb = hwdata;
          data_from_sram = sram_q;
          hrdata = data_from_sram;
          if(hready)sram_addr_out = haddr[11:0];
          if(!tmp_index)hready=0;
          else if (tmp_index==7)begin hready=1;sram_addr_out = sram_addr_out + 12'h1;end//终点
          else begin hready=0;sram_addr_out = sram_addr_out + 12'h1;end
          tmp_index = (tmp_index+1)%all_index;
     end
     HALFMAX:begin
          all_index=16;
          data_from_ahb = hwdata;
          data_from_sram = sram_q;
          hrdata = data_from_sram;          
          if(hready)sram_addr_out = haddr[11:0];
          if(!tmp_index)hready=0;
          else if (tmp_index==15)begin hready=1;sram_addr_out = sram_addr_out + 12'h1;end//终点
          else begin hready=0;sram_addr_out = sram_addr_out + 12'h1;end
          tmp_index = (tmp_index+1)%all_index;
     end
     MAX:begin
          all_index=32;
          data_from_ahb = hwdata;
          data_from_sram = sram_q;
          hrdata = data_from_sram;
          if(hready)sram_addr_out = haddr[11:0];
          if(!tmp_index)hready=0;
          else if (tmp_index==31)begin hready=1;sram_addr_out = sram_addr_out + 12'h1;end//终点
          else begin hready=0;sram_addr_out = sram_addr_out + 12'h1;end
          tmp_index = (tmp_index+1)%all_index;
     end
     /*default:begin
         all_index = 0;
         data_from_ahb = 0;
         sram_addr_out = 0;
         data_from_sram = 0;
         hready = 0;
     end */
     endcase
     
     if(haddr>16'h3ffc)begin hresp=ERROR;hready=0;end//传输持续
     //if(htrans_r == NONSEQ) begin hready=1;tmp_index=0; end//传输结束
   end
endmodule
