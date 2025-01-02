`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/12/14 15:41:29
// Design Name: 
// Module Name: test_ctrl
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


module test_ctrl;
    reg hclk,hresetn,hwrite;
    reg [1:0]htrans; //NONSEQ,SEQ,IDLE,BUSY
    reg [2:0]hsize; //每一个transfer传输的数据大小，以字节为单位，最高支持1024位
    reg [31:0]haddr;
    reg [2:0]hburst;//burst类型，支持4、8、16 burst，incrementing/wrapping
    reg [31:0]hwdata;//data from master
    
    wire hready;//1:slave 发出传输结束,0:slave需要延长传输周期,发至Master
    wire [1:0]hresp;//slave发给Master的总线传输状态OKAY、ERROR、RETRY、SPLIT
    wire [31:0]hrdata;//data to master
    wire sram_csn,sram_wen;//sram chip select enable
    wire sram_csn0,sram_csn1,sram_csn2,sram_csn3;
    wire [1:0]haddr_sel;
    wire [11:0]sram_a;//sram为4k大小
    wire [31:0]sram_d;//data to sram
    wire [31:0]sram_q;//data from sram
    
    sram_ctr_ahb my_ctr(.hclk(hclk),.hresetn(hresetn),.hwrite(hwrite),.htrans(htrans),.hsize(hsize),.haddr(haddr),.hburst(hburst),.hwdata(hwdata),
                        .hready(hready),.hresp(hresp),.hrdata(hrdata),.sram_csn(sram_csn),.sram_wen(sram_wen),.sram_a(sram_a),.sram_d(sram_d),.sram_q(sram_q));
    sram sram_0(.clka(hclk),.ena(sram_csn0),.wea(sram_wen),.addra(sram_a),.dina(sram_d),.douta(sram_q));
    sram sram_1(.clka(hclk),.ena(sram_csn1),.wea(sram_wen),.addra(sram_a),.dina(sram_d),.douta(sram_q));
    sram sram_2(.clka(hclk),.ena(sram_csn2),.wea(sram_wen),.addra(sram_a),.dina(sram_d),.douta(sram_q));
    sram sram_3(.clka(hclk),.ena(sram_csn3),.wea(sram_wen),.addra(sram_a),.dina(sram_d),.douta(sram_q));
                            
    assign haddr_sel = haddr[13:12];//4块
                                //
    assign sram_csn0 = (sram_csn && (haddr_sel == 2'b00));
    assign sram_csn1 = (sram_csn && (haddr_sel == 2'b01));
    assign sram_csn2 = (sram_csn && (haddr_sel == 2'b10));
    assign sram_csn3 = (sram_csn && (haddr_sel == 2'b11));
                                                    
    parameter IDLE=2'b00,BUSY=2'b01,NONSEQ=2'b10,SEQ=2'b11;//htrans
    parameter OKAY=2'b00,ERROR=2'b01,RETRY=2'b10,SPLIT=2'b11;//hresp
    parameter BYTE=3'b000,HALFWORD=3'b001,WORD=3'b010,DWORD=3'b011,FOURWORD=3'b100,EIGHTWORD=3'b101,HALFMAX=3'b110,MAX=3'b111;
    parameter SINGLE=3'b000,INCR=3'b001,WRAP4=3'b010,INCR4=3'b011,WRAP8=3'b100,INCR8=3'b101,WRAP16=3'b110,INCR16=3'b111;
    always #1 hclk=~hclk;                    
    initial fork
        hclk = 0;hresetn = 1;hwrite = 0;//read
        htrans = IDLE;
        haddr = 32'b0;hburst = SINGLE;
    join
    
    initial begin
        #1 hwrite = 1;//写
        #2 htrans = NONSEQ;hburst = WRAP4;hsize=BYTE;haddr = 32'h00000070;hwdata = 32'h00000030;
        while(!hready)begin #2 htrans = SEQ;hwdata = 32'h00000030;end//延长一个时钟周期继续传输
        
        #2 if(hready)begin haddr = haddr+32'h1;hwdata = 32'h00000034;end
        while(!hready)begin #2 hwdata = 32'h00000034;end
        
        #2 if(hready)begin haddr = haddr+32'h1;hwdata = 32'h00000038;end
        while(!hready)begin #2 hwdata = 32'h00000038;end
        
        #2 if(hready)begin haddr = haddr+32'h1;hwdata = 32'h0000003c;end  
        while(!hready)begin #2 hwdata = 32'h0000003c;end
        
        //read data
        #2 htrans = NONSEQ;hburst = WRAP4;hsize = WORD;hwrite=0;haddr = 32'h00000070;
        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000071;end
        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000072;end
        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000073;end

    end
endmodule
