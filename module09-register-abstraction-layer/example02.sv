// Module 09 / example02.sv -- frontdoor and backdoor access through an adapter, mirror checking
// Demonstrates : a CSR bus interface and slave stub, driver, uvm_reg_adapter, map.set_sequencer, auto-predict,
//                frontdoor write/read, backdoor read, mirror(UVM_CHECK) catching a stuck bit (bug-injected DUT)
// Lesson use   : "Code Walkthrough" sections 4-5
// Tool note    : UVM 1.2. Compile this file; it includes example01.sv (the register model; its top is skipped).
//                Backdoor access uses the UVM HDL DPI (uvm_hdl_read): needs the UVM DPI library linked and
//                signal visibility; SIMULATOR/VERSION-DEPENDENT.
//
// CSR bus (debug-style port; mini_cpu_if is NOT changed): master pulses csr_req for one cycle with csr_we/addr/wdata;
// the slave answers one edge later with a one-cycle csr_rvalid and csr_rdata = value BEFORE the write.

`define MCPU_SKIP_LEAF_TOPS
`include "example01.sv"

`timescale 1ns/1ps

interface mini_cpu_csr_if (input logic clk, input logic rst_n);
  logic        csr_req, csr_we;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata, csr_rdata;
  logic        csr_rvalid;
endinterface

module mini_cpu_csr_regs #(parameter bit MEPC_BIT0_BUG = 1'b0) (mini_cpu_csr_if bus);
  logic [31:0] mstatus_q, mtvec_q, mepc_q, mcause_q;
  always_ff @(posedge bus.clk) begin
    bus.csr_rvalid <= 1'b0;
    if (!bus.rst_n) begin
      mstatus_q <= 32'h0;  mtvec_q <= 32'h100;  mepc_q <= 32'h0;  mcause_q <= 32'h0;  bus.csr_rdata <= '0;
    end else if (bus.csr_req) begin
      bus.csr_rvalid <= 1'b1;
      case (bus.csr_addr)
        12'h300: begin bus.csr_rdata <= mstatus_q; if (bus.csr_we) mstatus_q <= bus.csr_wdata & 32'h0000_0088; end
        12'h305: begin bus.csr_rdata <= mtvec_q;   if (bus.csr_we) mtvec_q   <= bus.csr_wdata; end
        12'h341: begin bus.csr_rdata <= mepc_q;    if (bus.csr_we) mepc_q    <= MEPC_BIT0_BUG ? bus.csr_wdata : (bus.csr_wdata & 32'hFFFF_FFFE); end
        12'h342: bus.csr_rdata <= mcause_q;                                   // read-only
        default: bus.csr_rdata <= '0;
      endcase
    end
  end
endmodule

package mcpu_csr_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_ral_pkg::*;

  class mcpu_csr_item extends uvm_sequence_item;
    `uvm_object_utils(mcpu_csr_item)
    bit        we;
    bit [11:0] addr;
    bit [31:0] wdata, rdata;
    function new(string name = "mcpu_csr_item");
      super.new(name);
    endfunction
  endclass

  typedef uvm_sequencer#(mcpu_csr_item) mcpu_csr_seqr;

  class mcpu_csr_driver extends uvm_driver#(mcpu_csr_item);
    `uvm_component_utils(mcpu_csr_driver)
    virtual mini_cpu_csr_if vif;
    function new(string name = "mcpu_csr_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mini_cpu_csr_if)::get(this, "", "csr_vif", vif))
        `uvm_fatal("NOVIF", "csr_vif not found for the CSR driver")
    endfunction
    task run_phase(uvm_phase phase);
      vif.csr_req <= 1'b0;  vif.csr_we <= 1'b0;  vif.csr_addr <= '0;  vif.csr_wdata <= '0;
      forever begin
        seq_item_port.get_next_item(req);
        @(posedge vif.clk);
        vif.csr_req <= 1'b1;  vif.csr_we <= req.we;  vif.csr_addr <= req.addr;  vif.csr_wdata <= req.wdata;
        @(posedge vif.clk);                             // slave samples the request at this edge
        vif.csr_req <= 1'b0;
        @(posedge vif.clk);                             // slave's rvalid/rdata were set at the previous edge
        req.rdata = vif.csr_rdata;                      // why: reads return their data IN THE SAME ITEM
        seq_item_port.item_done();
      end
    endtask
  endclass

  class mcpu_csr_adapter extends uvm_reg_adapter;
    `uvm_object_utils(mcpu_csr_adapter)
    function new(string name = "mcpu_csr_adapter");
      super.new(name);
      supports_byte_enable = 0;
      provides_responses   = 0;                         // why: the driver completes the SAME item; no separate response
    endfunction
    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      mcpu_csr_item it;
      it = mcpu_csr_item::type_id::create("csr_it");
      it.we    = (rw.kind == UVM_WRITE);
      it.addr  = rw.addr[11:0];
      it.wdata = rw.data[31:0];
      return it;
    endfunction
    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      mcpu_csr_item it;
      if (!$cast(it, bus_item)) begin
        `uvm_fatal("CAST", "bus2reg: not a mcpu_csr_item")
        return;
      end
      rw.kind   = it.we ? UVM_WRITE : UVM_READ;
      rw.addr   = it.addr;
      rw.data   = it.we ? it.wdata : it.rdata;
      rw.status = UVM_IS_OK;
    endfunction
  endclass

  class mcpu_csr_test extends uvm_test;
    `uvm_component_utils(mcpu_csr_test)
    mcpu_csr_seqr           seqr;
    mcpu_csr_driver         drv;
    mcpu_csr_adapter        adapter;
    mcpu_csr_block          blk;
    virtual mini_cpu_csr_if vif;

    function new(string name = "mcpu_csr_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mini_cpu_csr_if)::get(this, "", "csr_vif", vif))
        `uvm_fatal("NOVIF", "csr_vif not found")
      seqr    = mcpu_csr_seqr::type_id::create("seqr", this);
      drv     = mcpu_csr_driver::type_id::create("drv", this);
      adapter = mcpu_csr_adapter::type_id::create("adapter");
      blk     = mcpu_csr_block::type_id::create("blk");
      blk.configure(null, "");
      blk.build();
      blk.add_hdl_path("tb_top_ral.csr", "RTL");                // backdoor: instance path of the DUT block
      blk.mstatus.add_hdl_path_slice("mstatus_q", 0, 32);       // backdoor: the flop that holds the register
      blk.lock_model();
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
      blk.default_map.set_sequencer(seqr, adapter);             // why: frontdoor = this sequencer + this adapter
      blk.default_map.set_auto_predict(1);                      // why: mirror follows every completed frontdoor access
    endfunction

    task run_phase(uvm_phase phase);
      uvm_status_e   status;
      uvm_reg_data_t val;
      phase.raise_objection(this, "csr test");
      @(posedge vif.rst_n);                                     // the bus is usable once reset is released

      blk.mtvec.write(status, 32'h200);
      `uvm_info("CSR", $sformatf("write mtvec=0x00000200 status=%s mirror=%s", status.name(), mcpu_fmt32(blk.mtvec.get_mirrored_value())), UVM_LOW)
      blk.mtvec.read(status, val);
      `uvm_info("CSR", $sformatf("read mtvec=%s mirror=%s", mcpu_fmt32(val), mcpu_fmt32(blk.mtvec.get_mirrored_value())), UVM_LOW)

      blk.mstatus.write(status, 32'hFFFF_FFFF);
      `uvm_info("CSR", $sformatf("write mstatus=0xffffffff status=%s mirror=%s", status.name(), mcpu_fmt32(blk.mstatus.get_mirrored_value())), UVM_LOW)
      blk.mstatus.read(status, val);
      `uvm_info("CSR", $sformatf("read mstatus=%s mirror=%s", mcpu_fmt32(val), mcpu_fmt32(blk.mstatus.get_mirrored_value())), UVM_LOW)
      blk.mstatus.read(status, val, UVM_BACKDOOR);
      `uvm_info("CSR", $sformatf("backdoor read mstatus=%s", mcpu_fmt32(val)), UVM_LOW)

      blk.mepc.write(status, 32'h0000_1001);
      `uvm_info("CSR", $sformatf("write mepc=0x00001001 mirror=%s", mcpu_fmt32(blk.mepc.get_mirrored_value())), UVM_LOW)
      blk.mepc.mirror(status, UVM_CHECK);                       // reads the DUT and compares with the mirror
      `uvm_info("CSR", $sformatf("mepc mirror(UVM_CHECK) issued, status=%s", status.name()), UVM_LOW)
      phase.drop_objection(this, "csr test done");
    endtask
  endclass
endpackage

module tb_top_ral;
  import uvm_pkg::*;
  import mcpu_csr_pkg::*;
  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  initial #42 rst_n = 1'b1;

  mini_cpu_csr_if vif (.clk(clk), .rst_n(rst_n));
  mini_cpu_csr_regs #(.MEPC_BIT0_BUG(1'b1)) csr (.bus(vif));    // bug injected: mepc bit 0 is writable

  initial begin
    uvm_config_db#(virtual mini_cpu_csr_if)::set(null, "uvm_test_top*", "csr_vif", vif);   // test and driver
    run_test("mcpu_csr_test");
  end
endmodule

// Expected log (hand-derived, not simulated). Clock posedges at 5, 15, ...; reset released at 42. UVM-internal lines elided.
// Each frontdoor access takes three edges (drive, slave samples, data visible): the first starts at 42 (waiting for the
// edge at 45) and completes at 65; later ones start at a completion time and complete 30 ns later.
//
// UVM_INFO example02.sv(155) @ 65:  uvm_test_top [CSR] write mtvec=0x00000200 status=UVM_IS_OK mirror=0x00000200
// UVM_INFO example02.sv(157) @ 95:  uvm_test_top [CSR] read mtvec=0x00000200 mirror=0x00000200
// UVM_INFO example02.sv(160) @ 125: uvm_test_top [CSR] write mstatus=0xffffffff status=UVM_IS_OK mirror=0x00000088
// UVM_INFO example02.sv(162) @ 155: uvm_test_top [CSR] read mstatus=0x00000088 mirror=0x00000088
// UVM_INFO example02.sv(164) @ 155: uvm_test_top [CSR] backdoor read mstatus=0x00000088        (zero time, same step)
// UVM_INFO example02.sv(167) @ 185: uvm_test_top [CSR] write mepc=0x00001001 mirror=0x00001000
// UVM_ERROR ... @ 215: [RegModel] ... mepc ... value read from the DUT does not match the mirrored value ...  (library text)
// UVM_INFO example02.sv(169) @ 215: uvm_test_top [CSR] mepc mirror(UVM_CHECK) issued, status=UVM_IS_OK
//
// Reasoning. mtvec: the DUT stores the full word; mirror = BASE 0x80 << 2 | MODE 0 = 0x200. mstatus: the DUT masks the write to
// 0x88 (MIE and MPIE); the model's two fields give the same 0x88 from the auto-predicted write, so read and mirror agree.
// mepc: the BUG-injected DUT stores 0x1001 (bit 0 stuck at 1) but the model predicts EPC = 0x800, ZERO (RO) = 0 -> 0x1000;
// mirror(UVM_CHECK) reads 0x1001 and the RO field ZERO (read 1, mirrored 0) mismatches: one UVM_ERROR from the library
// at 215 ns, just before the test's own line. The test's own log says only that the check was issued (status OK = the
// bus access worked); the error count of the run is 1.

