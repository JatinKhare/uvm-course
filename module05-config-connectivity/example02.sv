// Module 05 / example02.sv -- TLM analysis connectivity: port, hierarchical port, imp, tlm_analysis_fifo
// Demonstrates : producer -> (child port promoted through a wrapper port) -> two consumers:
//                A: uvm_analysis_imp (write() runs immediately, in the producer's thread)
//                B: uvm_tlm_analysis_fifo (buffers; a slow thread drains it with a blocking get)
// Lesson use   : "Code Walkthrough" sections 3-4
// Tool note    : UVM 1.2. Compile this file alone (own top; no DUT).

`timescale 1ns/1ps

package mcpu_tlm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class mcpu_demo_txn extends uvm_sequence_item;
    `uvm_object_utils(mcpu_demo_txn)
    bit [31:0] addr, data;
    function new(string name = "mcpu_demo_txn");
      super.new(name);
    endfunction
    virtual function string convert2string();
      return $sformatf("addr=0x%08h data=0x%08h", addr, data);
    endfunction
  endclass

  class mcpu_producer extends uvm_component;
    `uvm_component_utils(mcpu_producer)
    uvm_analysis_port#(mcpu_demo_txn) ap;
    function new(string name = "mcpu_producer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);                         // why: ports are constructed with new, in build_phase
    endfunction
    task run_phase(uvm_phase phase);
      mcpu_demo_txn t;
      for (int i = 0; i < 3; i++) begin
        t = mcpu_demo_txn::type_id::create("t");    // why: new object per write (consumers keep the handle)
        t.addr = i * 4;
        t.data = 32'hA0 + i;
        ap.write(t);                                // why: function call; every subscriber's write() runs now
        #10ns;
      end
    endtask
  endclass

  // Wrapper that hides the producer: its own port is the hierarchical boundary
  class mcpu_prod_box extends uvm_component;
    `uvm_component_utils(mcpu_prod_box)
    mcpu_producer                     prod;
    uvm_analysis_port#(mcpu_demo_txn) ap;
    function new(string name = "mcpu_prod_box", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap   = new("ap", this);
      prod = mcpu_producer::type_id::create("prod", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      prod.ap.connect(ap);                          // why: child port -> parent port (port-to-port promotion)
    endfunction
  endclass

  class mcpu_cons_a extends uvm_component;
    `uvm_component_utils(mcpu_cons_a)
    uvm_analysis_imp#(mcpu_demo_txn, mcpu_cons_a) imp;   // why: terminator; calls write() of THIS class
    function new(string name = "mcpu_cons_a", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      imp = new("imp", this);
    endfunction
    function void write(mcpu_demo_txn t);           // why: must be a non-blocking function
      `uvm_info("A", {"got ", t.convert2string()}, UVM_LOW)
    endfunction
  endclass

  class mcpu_cons_b extends uvm_component;
    `uvm_component_utils(mcpu_cons_b)
    uvm_tlm_analysis_fifo#(mcpu_demo_txn) fifo;    // why: unbounded buffer with an analysis_export on the input side
    function new(string name = "mcpu_cons_b", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      fifo = new("fifo", this);
    endfunction
    task run_phase(uvm_phase phase);
      mcpu_demo_txn t;
      forever begin
        fifo.get(t);                                // why: blocking get; consumer sets its own pace
        #25ns;                                      // slow consumer
        `uvm_info("B", $sformatf("done %s used=%0d", t.convert2string(), fifo.used()), UVM_LOW)
      end
    endtask
  endclass

  class mcpu_tlm_env extends uvm_env;
    `uvm_component_utils(mcpu_tlm_env)
    mcpu_prod_box box;
    mcpu_cons_a   a;
    mcpu_cons_b   b;
    function new(string name = "mcpu_tlm_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      box = mcpu_prod_box::type_id::create("box", this);
      a   = mcpu_cons_a::type_id::create("a", this);
      b   = mcpu_cons_b::type_id::create("b", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      box.ap.connect(a.imp);                        // why: analysis port -> imp (one of N subscribers)
      box.ap.connect(b.fifo.analysis_export);       // why: same port, second subscriber
    endfunction
  endclass

  class mcpu_tlm_test extends uvm_test;
    `uvm_component_utils(mcpu_tlm_test)
    mcpu_tlm_env env;
    function new(string name = "mcpu_tlm_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mcpu_tlm_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "tlm test");
      #100ns;                                       // long enough for the slow consumer to drain
      phase.drop_objection(this, "tlm test done");
    endtask
  endclass
endpackage

module tb_top_tlm;
  import uvm_pkg::*;
  import mcpu_tlm_pkg::*;
  initial run_test("mcpu_tlm_test");
endmodule

// Expected log (hand-derived, not simulated)
// Producer writes at 0, 10, 20 ns. A's write() runs inside each write call; B's consumer takes 25 ns per item.
// UVM-internal lines elided. The run phase ends at 100 ns (test objection).
//
// UVM_INFO example02.sv(77) @ 0:  uvm_test_top.env.a [A] got addr=0x00000000 data=0x000000a0
// UVM_INFO example02.sv(77) @ 10: uvm_test_top.env.a [A] got addr=0x00000004 data=0x000000a1
// UVM_INFO example02.sv(77) @ 20: uvm_test_top.env.a [A] got addr=0x00000008 data=0x000000a2
// UVM_INFO example02.sv(96) @ 25: uvm_test_top.env.b [B] done addr=0x00000000 data=0x000000a0 used=2
// UVM_INFO example02.sv(96) @ 50: uvm_test_top.env.b [B] done addr=0x00000004 data=0x000000a1 used=1
// UVM_INFO example02.sv(96) @ 75: uvm_test_top.env.b [B] done addr=0x00000008 data=0x000000a2 used=0
//
// B: get #1 at 0 -> done at 25 with the two later items queued (used=2); get #2 at 25 -> done 50 (used=1);
// get #3 at 50 -> done 75 (used=0). The producer was never delayed.

