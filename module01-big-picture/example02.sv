// Module 01 / example02.sv -- component hierarchy vs. object
// Demonstrates : uvm_component tree (test > env > agents/scoreboard), a uvm_object,
//                type_id::create for both, and this.print() of the hierarchy
// Lesson use   : "Code Walkthrough" section 5
// Tool note    : UVM 1.2. Compile this file alone (it has its own top; no DUT needed).
//
// mcpu_env, mcpu_ifetch_agent, mcpu_lsu_agent, mcpu_scoreboard are EMPTY SHELLS here.
// Modules 04 and 06 give them real bodies; their names and instance names stay the same.

`timescale 1ns/1ps

package mcpu_topo_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // uvm_object: data. Constructor takes only a name; no parent, no phases.
  class mcpu_run_info extends uvm_object;
    `uvm_object_utils(mcpu_run_info)       // why: object-flavour registration (uvm_object_registry)
    string       test_tag;
    int unsigned n_instr;

    function new(string name = "mcpu_run_info");
      super.new(name);
    endfunction

    virtual function string convert2string();   // why: the standard hook for one-line printing
      return $sformatf("tag=%s n_instr=%0d", test_tag, n_instr);
    endfunction
  endclass

  // uvm_component shells. Constructor takes (name, parent).
  class mcpu_ifetch_agent extends uvm_agent;
    `uvm_component_utils(mcpu_ifetch_agent)
    function new(string name = "mcpu_ifetch_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class mcpu_lsu_agent extends uvm_agent;
    `uvm_component_utils(mcpu_lsu_agent)
    function new(string name = "mcpu_lsu_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class mcpu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mcpu_scoreboard)
    function new(string name = "mcpu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class mcpu_env extends uvm_env;
    `uvm_component_utils(mcpu_env)
    mcpu_ifetch_agent ifetch_agent;
    mcpu_lsu_agent    lsu_agent;
    mcpu_scoreboard   scoreboard;

    function new(string name = "mcpu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // why: type_id::create (not new) so the factory can substitute these later (Module 02)
      ifetch_agent = mcpu_ifetch_agent::type_id::create("ifetch_agent", this);
      lsu_agent    = mcpu_lsu_agent::type_id::create("lsu_agent", this);
      scoreboard   = mcpu_scoreboard::type_id::create("scoreboard", this);
    endfunction
  endclass

  class mcpu_topo_test extends uvm_test;
    `uvm_component_utils(mcpu_topo_test)
    mcpu_env      env;
    mcpu_run_info info;

    function new(string name = "mcpu_topo_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env  = mcpu_env::type_id::create("env", this);
      info = mcpu_run_info::type_id::create("info");   // why: objects get a name only, no parent
      info.test_tag = "topo";
      info.n_instr  = 0;
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      `uvm_info("TOPO", {"run info: ", info.convert2string()}, UVM_LOW)
      this.print();                        // why: prints this component and everything beneath it
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("RUN", "empty run phase", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module tb_top_topo;
  import uvm_pkg::*;
  import mcpu_topo_pkg::*;
  initial run_test("mcpu_topo_test");
endmodule

// Expected log (hand-derived, not simulated)
// All lines at time 0. Table column widths and the @<id> instance numbers are simulator/run-dependent;
// UVM 1.2 also prints a similar table by itself under [UVMTOP] unless uvm_top.enable_print_topology = 0.
//
// UVM_INFO example02.sv(91) @ 0: uvm_test_top [TOPO] run info: tag=topo n_instr=0
// Name                 Type                Size  Value
// -------------------------------------------------------
// uvm_test_top         mcpu_topo_test      -     @<id>
//   env                mcpu_env            -     @<id>
//     ifetch_agent     mcpu_ifetch_agent   -     @<id>
//     lsu_agent        mcpu_lsu_agent      -     @<id>
//     scoreboard       mcpu_scoreboard     -     @<id>
// UVM_INFO example02.sv(97) @ 0: uvm_test_top [RUN] empty run phase
//
// Note: "info" does NOT appear in the table: it is an object, not a child component.

