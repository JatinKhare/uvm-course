// Module 02 / example01.sv -- phase order, objections, drain time
// Demonstrates : build top-down, connect bottom-up, run_phase in parallel, objection propagation,
//                set_drain_time, a run_phase task that is killed at phase end, report_phase
// Lesson use   : "Code Walkthrough" sections 1-3
// Tool note    : UVM 1.2. Compile this file alone (own top; no DUT).
//
// The probe classes are teaching tools (they only log); they are NOT the course's real env classes.
// Tree:  uvm_test_top (mcpu_phase_test) -> mid (mcpu_probe_mid) -> leaf_a, leaf_b (mcpu_probe_leaf)
//
// How to read it: (1) each class just LOGS in its phases, so you can see the order; (2) leaf_a / leaf_b / test each hold
// an objection ("BUSY sign") for 10 / 25 / 5 ns; (3) mid holds none and just loops forever; (4) the test also sets a
// 20 ns drain time. The expected log at the bottom shows what that produces.

`timescale 1ns/1ps

package mcpu_phase_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class mcpu_probe_leaf extends uvm_component;
    `uvm_component_utils(mcpu_probe_leaf)
    int unsigned busy_ns;                    // set by the parent after create(): how long run_phase works

    function new(string name = "mcpu_probe_leaf", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("PH", "build", UVM_LOW)
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("PH", "connect", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "leaf busy");     // why: raised at time 0, before any delay
      #(busy_ns * 1ns);
      `uvm_info("PH", "run work done", UVM_LOW)
      phase.drop_objection(this, "leaf done");      // why: balances the raise; count reaches the parent chain
    endtask
  endclass

  class mcpu_probe_mid extends uvm_component;
    `uvm_component_utils(mcpu_probe_mid)
    mcpu_probe_leaf leaf_a, leaf_b;

    function new(string name = "mcpu_probe_mid", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("PH", "build", UVM_LOW)
      leaf_a = mcpu_probe_leaf::type_id::create("leaf_a", this);
      leaf_b = mcpu_probe_leaf::type_id::create("leaf_b", this);
      leaf_a.busy_ns = 10;                          // why: child's build_phase runs AFTER this one, so the value is in place
      leaf_b.busy_ns = 25;
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("PH", "connect", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);                // no objection raised here on purpose
      forever begin
        #12ns;
        `uvm_info("PH", "heartbeat", UVM_LOW)
      end
    endtask
  endclass

  class mcpu_phase_test extends uvm_test;
    `uvm_component_utils(mcpu_phase_test)
    mcpu_probe_mid mid;

    function new(string name = "mcpu_phase_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("PH", "build", UVM_LOW)
      mid = mcpu_probe_mid::type_id::create("mid", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("PH", "connect", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "test running");
      phase.phase_done.set_drain_time(this, 20ns);  // why: keep the phase alive 20 ns after the LAST objection drops
      #5ns;
      `uvm_info("PH", "run work done", UVM_LOW)
      phase.drop_objection(this, "test done");
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("PH", "report", UVM_LOW)
    endfunction
  endclass
endpackage

module tb_top_phase;
  import uvm_pkg::*;
  import mcpu_phase_pkg::*;
  initial run_test("mcpu_phase_test");
endmodule

// Expected log (hand-derived, not simulated)
// Time unit ns; UVM-internal lines elided. Order of messages at the SAME time between different
// components in run_phase is not specified by UVM; this example avoids same-time run_phase messages.
//
// UVM_INFO ... @ 0:  uvm_test_top              [PH] build
// UVM_INFO ... @ 0:  uvm_test_top.mid          [PH] build
// UVM_INFO ... @ 0:  uvm_test_top.mid.leaf_a   [PH] build
// UVM_INFO ... @ 0:  uvm_test_top.mid.leaf_b   [PH] build
// UVM_INFO ... @ 0:  uvm_test_top.mid.leaf_a   [PH] connect
// UVM_INFO ... @ 0:  uvm_test_top.mid.leaf_b   [PH] connect
// UVM_INFO ... @ 0:  uvm_test_top.mid          [PH] connect
// UVM_INFO ... @ 0:  uvm_test_top              [PH] connect
// UVM_INFO ... @ 5:  uvm_test_top              [PH] run work done
// UVM_INFO ... @ 10: uvm_test_top.mid.leaf_a   [PH] run work done
// UVM_INFO ... @ 12: uvm_test_top.mid          [PH] heartbeat
// UVM_INFO ... @ 24: uvm_test_top.mid          [PH] heartbeat
// UVM_INFO ... @ 25: uvm_test_top.mid.leaf_b   [PH] run work done
// UVM_INFO ... @ 36: uvm_test_top.mid          [PH] heartbeat
// UVM_INFO ... @ 45: uvm_test_top              [PH] report
//
// Derivation: build is top-down (parent before child); connect is bottom-up (children before parent).
// The last objection (leaf_b) drops at 25; drain time 20 ns puts phase end at 45. The heartbeat at 36 falls
// inside the drain window and still prints; the next would be 48, after the run_phase task was killed at 45.
// leaf_a/leaf_b sibling order in build/connect is library traversal order (name order); do not depend on it.
