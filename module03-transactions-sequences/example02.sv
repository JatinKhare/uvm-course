// Module 03 / example02.sv -- virtual sequence, virtual sequencer, p_sequencer
// Demonstrates : coordinating two sequencers (data-memory preload, then instruction stream)
//                for a "LW after SW to the same address" scenario
// Lesson use   : "Code Walkthrough" section 5
// Tool note    : UVM 1.2. Compile this file; it `include`s example01.sv (same directory, MCPU_NO_TOP defined).
//                Include-path resolution is SIMULATOR-DEPENDENT: run from this directory or add +incdir.

`define MCPU_NO_TOP
`include "example01.sv"

`timescale 1ns/1ps

package mcpu_vseq_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;

  // Data-memory preload item (consumed by the load/store side)
  class mcpu_mem_item extends uvm_sequence_item;
    `uvm_object_utils(mcpu_mem_item)
    rand bit [31:0] addr, data;
    constraint c_align { addr[1:0] == 2'b00; }
    function new(string name = "mcpu_mem_item");
      super.new(name);
    endfunction
    virtual function string convert2string();
      return $sformatf("addr=0x%08h data=0x%08h", addr, data);
    endfunction
  endclass

  typedef uvm_sequencer#(mcpu_mem_item) mcpu_lsu_seqr;

  class mcpu_stub_lsu_driver extends uvm_driver#(mcpu_mem_item);   // throwaway; real LSU side: Module 04 exercise 03
    `uvm_component_utils(mcpu_stub_lsu_driver)
    function new(string name = "mcpu_stub_lsu_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("LSU", {"preload ", req.convert2string()}, UVM_LOW)
        #10ns;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class mcpu_mem_preload_seq extends uvm_sequence#(mcpu_mem_item);
    `uvm_object_utils(mcpu_mem_preload_seq)
    function new(string name = "mcpu_mem_preload_seq");
      super.new(name);
    endfunction
    task load_word(bit [31:0] a, bit [31:0] d);
      mcpu_mem_item m;
      m = mcpu_mem_item::type_id::create("m");
      start_item(m);
      if (!m.randomize() with { addr == a; data == d; }) `uvm_error("RAND", "mem randomize failed")
      finish_item(m);
    endtask
    task body();
      load_word(32'h0000_0100, 32'hDEAD_BEEF);   // stale value the SW must overwrite
      load_word(32'h0000_0104, 32'h1234_5678);   // neighbour word: catches a wrong-address LW
    endtask
  endclass

  class mcpu_lw_after_sw_seq extends mcpu_instr_seq_base;
    `uvm_object_utils(mcpu_lw_after_sw_seq)
    function new(string name = "mcpu_lw_after_sw_seq");
      super.new(name);
    endfunction
    task body();
      send_instr(OP_ADDI, 5'd4, 5'd0, 5'd0, 12'h100);   // ADDI x4,x0,0x100   base address
      send_instr(OP_ADDI, 5'd3, 5'd0, 5'd0, 12'd42);    // ADDI x3,x0,42      store data
      send_instr(OP_SW,   5'd0, 5'd4, 5'd3, 12'd0);     // SW   x3,0(x4)
      send_instr(OP_LW,   5'd5, 5'd4, 5'd0, 12'd0);     // LW   x5,0(x4)      must read 42, not 0xDEADBEEF
    endtask
  endclass

  // Virtual sequencer: runs no items itself; just holds handles to the real sequencers.
  class mcpu_vseqr extends uvm_sequencer;
    `uvm_component_utils(mcpu_vseqr)
    mcpu_ifetch_seqr ifetch_seqr;
    mcpu_lsu_seqr    lsu_seqr;
    function new(string name = "mcpu_vseqr", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  // Virtual sequence: orchestrates sub-sequences on different sequencers.
  class mcpu_lw_after_sw_vseq extends uvm_sequence;
    `uvm_object_utils(mcpu_lw_after_sw_vseq)
    `uvm_declare_p_sequencer(mcpu_vseqr)               // why: declares a typed p_sequencer handle, set when started
    function new(string name = "mcpu_lw_after_sw_vseq");
      super.new(name);
    endfunction
    task body();
      mcpu_mem_preload_seq   pre;
      mcpu_lw_after_sw_seq   prog;
      pre  = mcpu_mem_preload_seq::type_id::create("pre");
      prog = mcpu_lw_after_sw_seq::type_id::create("prog");
      `uvm_info("VSEQ", "preloading data memory", UVM_LOW)
      pre.start(p_sequencer.lsu_seqr);                  // why: start sub-sequence on the REAL sequencer
      `uvm_info("VSEQ", "starting program", UVM_LOW)
      prog.start(p_sequencer.ifetch_seqr);
    endtask
  endclass

  class mcpu_vseq_test extends uvm_test;
    `uvm_component_utils(mcpu_vseq_test)
    mcpu_vseqr             vseqr;
    mcpu_ifetch_seqr       ifetch_seqr;
    mcpu_lsu_seqr          lsu_seqr;
    mcpu_stub_driver       ifetch_drv;
    mcpu_stub_lsu_driver   lsu_drv;

    function new(string name = "mcpu_vseq_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vseqr       = mcpu_vseqr::type_id::create("vseqr", this);
      ifetch_seqr = mcpu_ifetch_seqr::type_id::create("ifetch_seqr", this);
      lsu_seqr    = mcpu_lsu_seqr::type_id::create("lsu_seqr", this);
      ifetch_drv  = mcpu_stub_driver::type_id::create("ifetch_drv", this);
      lsu_drv     = mcpu_stub_lsu_driver::type_id::create("lsu_drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      ifetch_drv.seq_item_port.connect(ifetch_seqr.seq_item_export);
      lsu_drv.seq_item_port.connect(lsu_seqr.seq_item_export);
      vseqr.ifetch_seqr = ifetch_seqr;                  // why: virtual sequencer must be told who the real ones are
      vseqr.lsu_seqr    = lsu_seqr;
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_lw_after_sw_vseq vseq;
      phase.raise_objection(this, "vseq test");
      vseq = mcpu_lw_after_sw_vseq::type_id::create("vseq");
      vseq.start(vseqr);
      phase.drop_objection(this, "vseq test done");
    endtask
  endclass
endpackage

module tb_top_vseq;
  import uvm_pkg::*;
  import mcpu_vseq_pkg::*;
  initial run_test("mcpu_vseq_test");
endmodule

// Expected log (hand-derived, not simulated)
// UVM-internal lines elided. Each driver holds an item 10 ns. Sub-sequences run one after the other
// because body() calls start() sequentially (start blocks until the sub-sequence's body returns).
//
// UVM_INFO example02.sv(101) @ 0:  <seq path>          [VSEQ] preloading data memory
// UVM_INFO example02.sv(41)  @ 0:  uvm_test_top.lsu_drv [LSU] preload addr=0x00000100 data=0xdeadbeef
// UVM_INFO example02.sv(41)  @ 10: uvm_test_top.lsu_drv [LSU] preload addr=0x00000104 data=0x12345678
// UVM_INFO example02.sv(103) @ 20: <seq path>          [VSEQ] starting program
// UVM_INFO example01.sv(138) @ 20: uvm_test_top.ifetch_drv [DRV] got OP_ADDI rd=x4 rs1=x0 rs2=x0 imm=0x100 enc=0x10000213
// UVM_INFO example01.sv(138) @ 30: uvm_test_top.ifetch_drv [DRV] got OP_ADDI rd=x3 rs1=x0 rs2=x0 imm=0x02a enc=0x02a00193
// UVM_INFO example01.sv(138) @ 40: uvm_test_top.ifetch_drv [DRV] got OP_SW rd=x0 rs1=x4 rs2=x3 imm=0x000 enc=0x00322023
// UVM_INFO example01.sv(138) @ 50: uvm_test_top.ifetch_drv [DRV] got OP_LW rd=x5 rs1=x4 rs2=x0 imm=0x000 enc=0x00022283
//
// The objection drops at 60. <seq path> is how the library names a running sequence in messages (derived from
// its sequencer's path; exact form is SIMULATOR/VERSION-DEPENDENT). File names/lines in the log depend on how
// the include was resolved.

