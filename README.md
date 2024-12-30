# 前言
        本工程项目起源于《数字集成电路》课程作业，要求如下：

        设计一个基于AHB从接口的单端口SRAM控制器，实现SRAM存储器与AHB总线的数据信息交换，将AHB总线上的读写操作转换成标准SRAM读写操作。

        SRAM大小为4096x32-bit，AHB接口数据大小固定为32-bit，AHB接口地址范围为0x00000000 – 0x00003FFC。AHB接口能够实现单次或突发模式的数据读写操作。

        顶层模块名为sram_ctr_ahb，输入输出功能定义：

 名称       |       方向    |      位宽            |                            描述
 --|--|--|--
  hclk        |      Input      |     1                |         系统时钟
hresetn     |     Input      |      1                 |       系统异步复位，低电平有效
 hwrite     |      Input        |    1               |          主设备写信号，高为写，低为读
 htrans      |     Input      |      2                  |       当前传输类型，IDLE、SEQ、NONSEQ、
  hsize     |       Input     |       3                  |       当前传输大小，取值为0-7分别代表8*2^hsizebit
  haddr      |     Input      |     32                |        读写从设备地址
  hburst    |      Input      |      3                 |        当前突发类型，有8种
 hwdata    |      Input      |     32               |         AHB总线向SRAM写数据，经SRAM控制器
 hready   |      Output       |   1              |            传输完成指示
  hresp     |     Output     |     2               |           传输响应
 hrdata     |     Output     |     32               |         将所读SRAM数据传至AHB总线
sram_csn   |   Output    |      1                 |         SRAM片选，低电平有效
sram_wen  |   Output      |    1                   |       SRAM写使能，低电平有效
 sram_a    |     Output    |     12                 |       SRAM读写地址
 sram_d     |    Output      |    32              |         向SRAM数据
 sram_q      |     Input    |       32               |        读SRAM数据

设计要求：

Verilog实现代码可综合，给出综合以及仿真结果。

仿真时应给出各种典型情况下的数据读写接口信号波形。

仿真时SRAM时钟与hclk相同，简单起见本文仅考虑一个主设备的情况

特别说明：本文仅供参考！！！欢迎指正，因为我也不太明白




# 相关知识
        本工程实际涉及三个对象：AHB总线（实际为主设备）、SRAM控制器（作为从设备）、SRAM，三者通信逻辑示意图如下，由于SRAM仅传输数据故省略：
![AHB总线主从结构](https://i0.hdslb.com/bfs/article/85ff23c9a02a3ea6065d708ff3bc91a0ac99cffb.png@1192w.avif "AHB总线主从结构")
  AHB总线主从结构
  
        主设备需要与从设备（本文为SRAM）通信时首先向AHB总线发出地址（含片选）及读写信号，在下一个时钟周期SRAM从AHB总线获取数据或将数据发送到AHB总线。hsize、htrans、hburst均为对传送数据的辅助指示，根据hsize和hburst，主设备在不同时钟周期会变化向总线传输的地址。

        各信号含义如下：

        haddr[31:0]为主设备选择的读写数据单元地址，由于总线为32位真正有效位视存储空间而定；

        hwrite为主设备向SRAM的写信号，高代表写SRAM低代表读SRAM；

        hwdata[31:0]为主设备向SRAM写的32位数据；

        hrdata[31:0]为主设备从SRAM读出的32位数据；

        htrans[1:0]为四种传输类型(参考https://blog.csdn.net/weixin_30897233/article/details/96343607)，其中仅SEQ与NONSEQ情况下从机需要响应；

        hburst[2:0]代表8种传输类型，SINGLE表示一次传输一个地址和控制信号作为一组数据，INCR（最常用）是地址持续递增的数据传输，根据传输数据大小递增地址（与hsize有关），需要注意的是一次burst传输不能穿越1K边界（例如从0x3FC到0x400地址变化越过了1K的地址边界，htrans要从0x3FC时的SEQ变为0x400时的NONSEQ），因为一个从设备最小的地址间隙是1KB，WRAP4是地址回环递增，每个回环内递增四次，地址在地址边界（由burst传输次数和每次传输数据大小决定）回环，INCR4是地址递增，一次INCR4信号持续到地址递增4次，WARP8与INCR8、WARP16与INCR16的关系类似，需要额外说明的是AHB的所有操作都要求给出的地址是对齐的（即地址间隔是数据宽度的整数倍），同一个burst内每次数据的宽度是一致的；

        hsize[2:0]表示8种数据宽度，0-7分别对应8bit、16bit、32bit（最常用）、64bit、128bit、256bit、512bit、1024bit；

        hready信号高表示当前transfer完成，为低表示从设备需要额外的周期完成此次传输；

        hresp[1:0]是从设备对主设备的四种相应信号，OKAY表示传输成功（通常），ERROR表示传输失败，RETRY出现在请求主设备重新开始一组传输的情况，SPLIT请求主设备分离一次传输，简单起见仅考虑OKAY信号。


# 电路设计
        由于SRAM大小为4Kx32bit，片内地址为12位，AHB总线接口固定32位，地址范围0x00000000-0x000003FFC，可寻址4块SRAM，故总线haddr信号仅[13:0]有效，其中[13:12]为片选信号，[11:0]为片内地址索引。

        首先考虑SRAM模块，其设计为32位数据接口、12位地址接口，输入端还包括时钟、片选使能、写使能，在片选无效时对外输出高阻且不读取数据，片选有效时若读有效则根据地址输出数据到hrdata，若写有效则同时根据地址将hwdata上数据存入本SRAM

        再根据总线其他控制信号考虑控制器内部逻辑，当总线上传输类型htrans为NONSEQ或SEQ时SRAM控制器需要响应，根据hwrite信号可得sram的读写信号，当读写信号有其一有效时对sram片选，选择4块sram其中的那一块则根据haddr中地址确定。按此规则，总线上hwdata可以在一个时钟周期内传至sram_d，而从SRAM读出数据到AHB总线的hrdata需要一个时钟周期的延时。另外对于传输数据位数大于32bit时，hready信号拉低以传输剩余位的信号。源工程文件链接 https://github.com/up-or-down/AHB-SRAM




# 仿真结果
        写SRAM时突发类型为WRAP4，hsize为8bit；读SRAM时突发类型WRAP4，hsize为32bit为例，测试例程如下

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

        仿真结果为

仿真时序图——写hburst=WRAP4，hsize=0；读hburst=WRAP4，hsize=2
        写SRAM时突发类型为INCR4，hsize为64bit；读SRAM时突发类型INCR8，hsize为32bit为例，测试例程

initial begin

        #1 hwrite = 1;//写

        #2 htrans = NONSEQ;hburst = INCR4;hsize=DWORD;haddr = 32'h00000070;hwdata = 32'hf0a596c3;

        #2 hwdata = 32'h01020304;

        while(!hready)begin #2 htrans = SEQ;hwdata = 32'h01020304;end//延长一个时钟周期继续传输

        

        if(hready)begin haddr = haddr+32'h2;hwdata = 32'h03040506;end

        #2 hwdata = 32'h0708090a;

        while(!hready)begin #2 htrans = SEQ;hwdata = 32'h0708090a;end

        

        if(hready)begin haddr = haddr+32'h2;hwdata = 32'h05060708;end

        #2 hwdata = 32'h090a0b0c;

        while(!hready)begin #2 hwdata = 32'h090a0b0c;end

        

        if(hready)begin haddr = haddr+32'h2;hwdata = 32'h0708090a;end

        #2 hwdata = 32'h0b0c0d0e;  

        while(!hready)begin #2 hwdata = 32'h0b0c0d0e;end

        

        //read data

        htrans = NONSEQ;hburst = INCR8;hsize = WORD;hwrite=0;haddr = 32'h00000070;

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000071;end

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000072;end

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000073;end

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000074;end

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000075;end

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000076;end        

        #2 htrans = SEQ;if(hready)begin haddr = 32'h00000077;end

    end

        仿真结果为

仿真时序图——写hburst=INCR4，hsize=3；读hburst=INCR8，hsize=2
 


