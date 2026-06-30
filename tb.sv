module all_mod_tb;
  
    reg clk, rst, wr, rd;
    reg rx;
    reg [2:0] addr;
    reg [7:0] din;
    wire tx;
    wire [7:0] dout;

    reg [15:0] div_latch;
    int baud;
    int error;
    bit tx_parity;
    bit parity_bit;


    all_mod dut (clk, rst, wr, rd,rx,addr, din, tx, dout);
    
    initial begin
    rst = 0;
    clk = 0;
    wr = 0;
    rd = 0;
    addr = 0;
    din = 0;
    rx = 1;
    end
    
    always #5 clk = ~clk;

    task automatic send_uart_byte(input [7:0] data);
      int nbits;
      bit [7:0] mask;
      bit parity_bit, parity_to_send;

      case (dut.csr.lcr.wls)
        2'b00: nbits = 5;
        2'b01: nbits = 6;
        2'b10: nbits = 7;
        2'b11: nbits = 8;
      endcase

      mask = (8'h01 << nbits) - 8'h01;   // e.g. nbits=6 -> mask = 8'b0011_1111

      // start bit
      rx = 1'b0;
      repeat(16) @(posedge dut.baud_pulse);

      // data bits, LSB first, only as many as configured
      for (int i = 0; i < nbits; i++) begin
        rx = data[i];
        repeat(16) @(posedge dut.baud_pulse);
      end

      // parity bit, computed the same way the DUT computes it
      if (dut.csr.lcr.pen) begin
        parity_bit = ^(data & mask);     // XOR-reduce only the active data bits
        case ({dut.csr.lcr.stick_parity, dut.csr.lcr.eps})
          2'b00: parity_to_send = ~parity_bit; // odd
          2'b01: parity_to_send =  parity_bit; // even
          2'b10: parity_to_send =  1'b1;       // mark
          2'b11: parity_to_send =  1'b0;       // space
        endcase
        rx = parity_to_send;
        repeat(16) @(posedge dut.baud_pulse);
      end

      // stop bit(s)
      rx = 1'b1;
      repeat(16) @(posedge dut.baud_pulse);
      if (dut.csr.lcr.stb)
        repeat(16) @(posedge dut.baud_pulse); // extra time for 1.5/2 stop-bit modes
    endtask
    
    initial begin
    rst = 1'b1;
    repeat(5)@(posedge clk);
    $display("System Reset Done");
    rst = 0;

  //////////////////////////////////////////////////// LCR Register config ///////////////////////////////////////////////////////
    @(posedge clk);
    wr   = 1;
    addr = 3'h3;
    din  = 8'b1000_0000;
    @(posedge clk)
    $display("======================= LCR Register ==========================");
    $display("dlab:%0d set_break:%0d stick_parity:%0d eps:%0d pen:%0d stb:%0d wls:%0d",
      dut.csr.lcr.dlab,dut.csr.lcr.set_break,dut.csr.lcr.stick_parity,dut.csr.lcr.eps,dut.csr.lcr.pen,
      dut.csr.lcr.stb,dut.csr.lcr.wls);
    case({dut.csr.lcr.dlab,addr})
      4'd0 : $display("Transmitter hold register (THR)");
      4'd1 : $display("Receiver hold register (RHR)");
      4'd8 : $display("LSB of baud rate divisor");
      4'd9 : $display("MSB of baud rate divisor");
    endcase
    if(dut.csr.lcr.set_break) $display("Set break Enable"); else $display("Set break Disable");
    if(dut.csr.lcr.pen) $display("Parity Enable"); else $display("Parity Disable");
    case({dut.csr.lcr.stick_parity,dut.csr.lcr.eps})
      2'd0 : $display("Odd Parity");
      2'd1 : $display("Even Parity");
      2'd2 : $display("Parity bit : 1");
      2'd3 : $display("Parity bit : 0");
    endcase 
    if (dut.csr.lcr.stb == 1'b0)
      $display("1 Stop Bit");
    else if (dut.csr.lcr.wls == 2'b00)
        $display("1.5 Stop Bit");
    else
        $display("2 Stop Bit");
    case(dut.csr.lcr.wls)
      2'd0 : $display("5 data bits");
      2'd1 : $display("6 data bits");
      2'd2 : $display("7 data bits");
      2'd3 : $display("8 data bits");
    endcase 
    $display("==============================================================");

  //////////////////////////////////////////////////// Baud Generation  ////////////////////////////////////////////
    ///// lsb latch 
    @(posedge clk);
    addr = 3'h0;
    din  = 8'b1010_0011;
    ////// msb latch
    @(posedge clk);
    addr = 3'h1;
    din  = 8'b0000_0000;
    @(posedge clk);
    $display("======================= Divisor Latch For Baud Generation ==========================");
    $display("dmsb:%0d dlsb:%0d",dut.uart_regs_inst.dl.dmsb,dut.uart_regs_inst.dl.dlsb);
    div_latch = {dut.uart_regs_inst.dl.dmsb,dut.uart_regs_inst.dl.dlsb};
    baud = 100000000/(div_latch*16);
    $display("div_latch:%0d",div_latch);
    $display("baud rate:%0d Hz",baud);
    $display("==============================================================");
    
  /////////////////////////////////////////////////// LCR Register config /////////////////////////////////////////////
    @(posedge clk);
    addr = 3'h3;
    din  = 8'b0011_1100; // dlab=0
    @(posedge clk);
    $display("======================= LCR Register ==========================");
    $display("dlab:%0d set_break:%0d stick_parity:%0d eps:%0d pen:%0d stb:%0d wls:%0d",
      dut.csr.lcr.dlab,dut.csr.lcr.set_break,dut.csr.lcr.stick_parity,dut.csr.lcr.eps,dut.csr.lcr.pen,
      dut.csr.lcr.stb,dut.csr.lcr.wls);
    case({dut.csr.lcr.dlab,addr})
      4'd0 : $display("Transmitter hold register (THR)");
      4'd1 : $display("Receiver hold register (RHR)");
      4'd8 : $display("LSB of baud rate divisor");
      4'd9 : $display("MSB of baud rate divisor");
    endcase
    if(dut.csr.lcr.set_break) $display("Set break Enable"); else $display("Set break Disable");
    if(dut.csr.lcr.pen) $display("Parity Enable"); else $display("Parity Disable");
    case({dut.csr.lcr.stick_parity,dut.csr.lcr.eps})
      2'd0 : $display("Odd Parity");
      2'd1 : $display("Even Parity");
      2'd2 : $display("Parity bit : 1");
      2'd3 : $display("Parity bit : 0");
    endcase 
    if (dut.csr.lcr.stb == 1'b0)
      $display("1 Stop Bit");
    else if (dut.csr.lcr.wls == 2'b00)
        $display("1.5 Stop Bit");
    else
        $display("2 Stop Bit");
    case(dut.csr.lcr.wls)
      2'd0 : $display("5 data bits");
      2'd1 : $display("6 data bits");
      2'd2 : $display("7 data bits");
      2'd3 : $display("8 data bits");
    endcase 
    $display("==============================================================");
          
  /////////////////////////////////////////////////////// Tx FIFO enable  //////////////////////////////////////////////////////
    @(posedge clk);
    wr = 1'd1;
    addr = 3'h2;
    din  = 8'b0000_0001; // enable FIFO only
    @(posedge clk);
    $display("===================================== Transmitter FIFO ========================================");
    $display("-----------FCR register configuration---------");
    $display("ena:%0d tx_rst:%0d",dut.csr.fcr.ena,dut.csr.fcr.tx_rst);
    if(dut.csr.fcr.ena) $display("Transmitter FIFO : ENABLED"); else $display("Transmitter FIFO : DISABLED");
    if(dut.csr.fcr.tx_rst) $display("Transmitter FIFO Resetting ...."); else $display("Transmitter FIFO Reset done");
    $display("------------------------------------");
    $display("-----------LSR register configuration---------");
    $display("thre:%0d temt:%0d dr:%0d",dut.csr.lsr.thre,dut.csr.lsr.temt,dut.csr.lsr.dr);
    $display("push:%0d pop:%0d din:%0d dout:%0d empty:%0d full:%0d overrun%0d underrun%0d cnt:%0d",dut.tx_fifo_inst.push_in,dut.tx_fifo_inst.pop_in,
      dut.tx_fifo_inst.din,dut.tx_fifo_inst.dout,dut.tx_fifo_inst.empty,dut.tx_fifo_inst.full,dut.tx_fifo_inst.overrun,
      dut.tx_fifo_inst.underrun,dut.tx_fifo_inst.cnt);
    if(dut.csr.lsr.thre) $display("Transmitter Holding Register is Empty"); else $display("Transmitter Holding Register is not Empty");
    if(dut.csr.lsr.temt) $display("Transmitter is not Empty"); else $display("Transmitter is Empty");
    if(dut.csr.lsr.dr) $display("Data Ready for Transmission"); else $display("Data not ready for transmission");
    $display("------------------------------------");
    for(int i = 0; i < 8; i++) begin
      @(posedge clk);
      wr <= 1'd1;
      addr <= 3'h0;
      din  <= $urandom_range(0,31);
      @(posedge clk);
      if(dut.tx_fifo_inst.push_in) $display("Data Write in TX FIFO:%0d",dut.tx_fifo_inst.din);
      $display("push:%0d pop:%0d din:%0d dout:%0d empty:%0d full:%0d overrun:%0d underrun:%0d cnt:%0d thres_trigg:%0d",dut.tx_fifo_inst.push_in,dut.tx_fifo_inst.pop_in,
          dut.tx_fifo_inst.din,dut.tx_fifo_inst.dout,dut.tx_fifo_inst.empty,dut.tx_fifo_inst.full,dut.tx_fifo_inst.overrun,
          dut.tx_fifo_inst.underrun,dut.tx_fifo_inst.cnt,dut.tx_fifo_inst.thre_trigger);
      wr <= 0;
      $display("------------------------------------");
    end
    @(posedge clk);
    $display("============ Transmission FIFO Final State ============");
    $display("empty:%0d full:%0d cnt:%0d",dut.tx_fifo_inst.empty,dut.tx_fifo_inst.full,dut.tx_fifo_inst.cnt);
    $display("Mem -> [0]=%0d [1]=%0d [2]=%0d [3]=%0d [4]=%0d [5]=%0d [6]=%0d [7]=%0d [8]=%0d [9]=%0d [10]=%0d [11]=%0d [12]=%0d [13]=%0d [14]=%0d [15]=%0d"
      ,dut.tx_fifo_inst.mem[0],dut.tx_fifo_inst.mem[1],dut.tx_fifo_inst.mem[2],dut.tx_fifo_inst.mem[3],dut.tx_fifo_inst.mem[4]
      ,dut.tx_fifo_inst.mem[5],dut.tx_fifo_inst.mem[6],dut.tx_fifo_inst.mem[7],dut.tx_fifo_inst.mem[8],dut.tx_fifo_inst.mem[9]
      ,dut.tx_fifo_inst.mem[10],dut.tx_fifo_inst.mem[11],dut.tx_fifo_inst.mem[12],dut.tx_fifo_inst.mem[13],dut.tx_fifo_inst.mem[14]
      ,dut.tx_fifo_inst.mem[15]);
    $display("=================================================================================");

  //////////////////////////////////////////////////// Transmitter start sending byte  /////////////////////////////////////////////////
    wr   = 0;
    addr = 0;
    din  = 0;
    $display("============================= Uart Transmitter ===================================");
    $display("pen:%0d thre%0d stb%0d sticky_parity%0d eps%0d set_break:%0d pop:%0d sreg_empty:%0d tx:%0d wls:%0d",dut.uart_tx_inst.pen
    ,dut.uart_tx_inst.thre,dut.uart_tx_inst.stb,dut.uart_tx_inst.sticky_parity,dut.uart_tx_inst.eps,dut.uart_tx_inst.set_break
    ,dut.uart_tx_inst.pop,dut.uart_tx_inst.sreg_empty,dut.uart_tx_inst.tx,dut.uart_tx_inst.wls);
    if(dut.uart_tx_inst.thre) $display("Tx Fifo is empty"); else $display("Tx Fifo contains Data");
    if(dut.uart_tx_inst.set_break) $display("Set break Enable"); else $display("Set break Disable");
    if(dut.uart_tx_inst.pen) $display("Parity Enable"); else $display("Parity Disable");
    case({dut.uart_tx_inst.sticky_parity,dut.uart_tx_inst.eps})
      2'd0 : $display("Odd Parity");
      2'd1 : $display("Even Parity");
      2'd2 : $display("Parity bit : 1");
      2'd3 : $display("Parity bit : 0");
    endcase 
    if (dut.uart_tx_inst.stb == 1'b0)
      $display("1 Stop Bit");
    else if (dut.csr.lcr.wls == 2'b00)
        $display("1.5 Stop Bit");
    else
        $display("2 Stop Bit");
    case(dut.uart_tx_inst.wls)
      2'd0 : $display("5 data bits");
      2'd1 : $display("6 data bits");
      2'd2 : $display("7 data bits");
      2'd3 : $display("8 data bits");
    endcase 
    $display("------------------------------------");
    $display("Data Ready for Transmission");
    $display("Transmitter Starting....");
    $display("------------------------------------");
    for(int i = 0; i < 8; i++) begin
      @(posedge dut.uart_tx_inst.pop);
      parity_bit = ^dut.uart_tx_inst.din;
      case ({dut.uart_tx_inst.sticky_parity,dut.uart_tx_inst.eps})
        2'b00: tx_parity = ~parity_bit; // odd parity
        2'b01: tx_parity =  parity_bit; // even parity
        2'b10: tx_parity =  1'b1;       // mark parity (always 1)
        2'b11: tx_parity =  1'b0;       // space parity (always 0)
      endcase
      $display("Data Byte[%0d]:%0d  parity:%0d pop:%0d  --> Byte %0d Sent successfully",i,dut.uart_tx_inst.din,
      tx_parity,dut.uart_tx_inst.pop,i);
      $display("------------------------------------");
    end
    repeat(3) @(posedge clk);
      if(dut.tx_fifo_inst.empty) $display("Tx FIFO empty:%0d --> All Bytes Sent successfully",dut.tx_fifo_inst.empty);
      $display("Transmitter Stopped....");
      $display("==================================================================");

  /////////////////////////////////////////////// Receiver start Receiving byte in Rx FIFO ///////////////////////////////////////////////
    @(posedge clk);
    $display("=================================== Uart Receiver ====================================");
    $display("rx:%0d sticky_parity:%0d eps:%0d pen:%0d wls:%0d push:%0d pe:%0d fe:%0d bi:%0d"
    ,dut.uart_rx_inst.rx,dut.uart_rx_inst.sticky_parity,dut.uart_rx_inst.eps,dut.uart_rx_inst.pen
    ,dut.uart_rx_inst.wls,dut.uart_rx_inst.push,dut.uart_rx_inst.pe,dut.uart_rx_inst.fe
    ,dut.uart_rx_inst.bi);
    if(dut.uart_rx_inst.pen) $display("Parity Enable"); else $display("Parity Disable");
    case({dut.uart_rx_inst.sticky_parity,dut.uart_rx_inst.eps})
      2'd0 : $display("Odd Parity");
      2'd1 : $display("Even Parity");
      2'd2 : $display("Parity bit : 1");
      2'd3 : $display("Parity bit : 0");
    endcase 
    case(dut.uart_rx_inst.wls)
      2'd0 : $display("5 data bits");
      2'd1 : $display("6 data bits");
      2'd2 : $display("7 data bits");
      2'd3 : $display("8 data bits");
    endcase 
    $display("------------------------------------");
    $display("Receiver Starting....");
    $display("rx:%0d push:%0d",dut.uart_rx_inst.rx,dut.uart_rx_inst.push);
    $display("------------------------------------");
    for(int i = 0; i < 8; i++) begin
      send_uart_byte(dut.tx_fifo_inst.mem[i]);   // re-send same bytes that were loaded in TX FIFO earlier
      repeat(2) @(posedge clk);
      $display("Data Byte[%0d]:%0d received --> Byte[%0d] Received Successfully",i,dut.uart_rx_inst.dout,i);
      $display("------------------------------------");
    end
    repeat(3) @(posedge clk);
      if(dut.rx_fifo_inst.empty) $display("Receiver FIFO empty:%0d --> All Data Byte received",dut.tx_fifo_inst.empty);
      $display("Receiver Stopped....");
      if(dut.uart_rx_inst.pe) begin
        $display("Parity error Occured");
        error = error + 1;
      end
      if(dut.uart_rx_inst.fe) begin
        $display("Frame error Occured");
        error = error + 1;
      end
      if(dut.uart_rx_inst.bi) begin
        $display("Break indicator Occured");
        error = error + 1;
      end
      $display("Error count:%0d",error);
      $display("==============================================================");

  /////////////////////////////////////////////////////// Rx FIFO enable //////////////////////////////////////////////////////////
    @(posedge clk);
    $display("===================================== Receiver FIFO ========================================");
    $display("-----------FCR register configuration---------");
    $display("ena:%0d rx_rst:%0d rx_trigger:%0d",dut.csr.fcr.ena,
    dut.csr.fcr.rx_rst,dut.csr.fcr.rx_trigger);
    if(dut.csr.fcr.ena) $display("Receiver FIFO : ENABLED"); else $display("Receiver FIFO : DISABLED");
    if(dut.csr.fcr.rx_rst) $display("Receiver FIFO Resetting ...."); else $display("Receiver FIFO Reset done");
    case(dut.csr.fcr.rx_trigger)
      2'd0 : $display("Receiver FIFO Interrupt Trigger at 1 byte");
      2'd1 : $display("Receiver FIFO Interrupt Trigger at 4 byte");
      2'd2 : $display("Receiver FIFO Interrupt Trigger at 8 byte");
      2'd3 : $display("Receiver FIFO Interrupt Trigger at 14 byte");
    endcase 
    $display("------------------------------------");
    $display("-----------LSR register configuration---------");
    $display("bi:%0d fe:%0d oe:%0d pe:%0d",dut.csr.lsr.bi,dut.csr.lsr.fe,dut.csr.lsr.oe,dut.csr.lsr.pe);
    $display("push:%0d pop:%0d din:%0d dout:%0d empty:%0d full:%0d overrun%0d underrun%0d cnt:%0d",dut.rx_fifo_inst.push_in,dut.rx_fifo_inst.pop_in,
      dut.rx_fifo_inst.din,dut.rx_fifo_inst.dout,dut.rx_fifo_inst.empty,dut.rx_fifo_inst.full,dut.rx_fifo_inst.overrun,
      dut.rx_fifo_inst.underrun,dut.rx_fifo_inst.cnt);
    $display("------------------------------------");
    @(posedge clk);
    $display("============ Receiver FIFO Final State ============");
    $display("empty:%0d full:%0d cnt:%0d",dut.rx_fifo_inst.empty,dut.rx_fifo_inst.full,dut.rx_fifo_inst.cnt);
    $display("Mem -> [0]=%0d [1]=%0d [2]=%0d [3]=%0d [4]=%0d [5]=%0d [6]=%0d [7]=%0d [8]=%0d [9]=%0d [10]=%0d [11]=%0d [12]=%0d [13]=%0d [14]=%0d [15]=%0d"
      ,dut.rx_fifo_inst.mem[0],dut.rx_fifo_inst.mem[1],dut.rx_fifo_inst.mem[2],dut.rx_fifo_inst.mem[3],dut.rx_fifo_inst.mem[4]
      ,dut.rx_fifo_inst.mem[5],dut.rx_fifo_inst.mem[6],dut.rx_fifo_inst.mem[7],dut.rx_fifo_inst.mem[8],dut.rx_fifo_inst.mem[9]
      ,dut.rx_fifo_inst.mem[10],dut.rx_fifo_inst.mem[11],dut.rx_fifo_inst.mem[12],dut.rx_fifo_inst.mem[13],dut.rx_fifo_inst.mem[14]
      ,dut.rx_fifo_inst.mem[15]);
    $display("=================================================================================");
    $stop;
    end
    
endmodule


