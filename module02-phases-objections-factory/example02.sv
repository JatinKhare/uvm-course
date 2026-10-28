// Module 02 / example02.sv -- factory: type_id::create, type override, instance override, new() bypass
// Demonstrates : override precedence (instance > type), overrides set before create, new() ignoring overrides
// Lesson use   : "Code Walkthrough" sections 4-5
// Tool note    : UVM 1.2. Compile this file alone (own top; no DUT).
//
// mcpu_scoreboard is an empty shell here (real body: Module 06).

`timescale 1ns/1ps

package mcpu_factory_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class mcpu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mcpu_scoreboard)
    function new(string name = "mcpu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("SB", {"I am ", get_type_name()}, UVM_LOW)   // why: get_type_name() reveals which class the factory built
    endfunction
  endclass

  // Overrides must extend the class they replace, and each needs its own registration macro.
  class mcpu_verbose_scoreboard extends mcpu_scoreboard;
    `uvm_component_utils(mcpu_verbose_scoreboard)
    function new(string name = "mcpu_verbose_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class mcpu_strict_scoreboard extends mcpu_scoreboard;
    `uvm_component_utils(mcpu_strict_scoreboard)
    function new(string name = "mcpu_strict_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class mcpu_ovr_env extends uvm_env;
    `uvm_component_utils(mcpu_ovr_env)
    mcpu_scoreboard sb_a, sb_b, sb_c;

    function new(string name = "mcpu_ovr_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sb_a = mcpu_scoreboard::type_id::create("sb_a", this);   // why: goes through the factory -> overrides apply
      sb_b = mcpu_scoreboard::type_id::create("sb_b", this);   // why: same, but an instance override targets this one
      sb_c = new("sb_c", this);                                // why: direct new() bypasses the factory entirely
    endfunction
  endclass

  class mcpu_ovr_test extends uvm_test;
    `uvm_component_utils(mcpu_ovr_test)
    mcpu_ovr_env env;

    function new(string name = "mcpu_ovr_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // why: overrides are consulted at create() time, so they must be registered BEFORE env is created
      mcpu_scoreboard::type_id::set_type_override(mcpu_verbose_scoreboard::get_type());
      mcpu_scoreboard::type_id::set_inst_override(mcpu_strict_scoreboard::get_type(),
                                                  "uvm_test_top.env.sb_b");   // why: full hierarchical path
      env = mcpu_ovr_env::type_id::create("env", this);
    endfunction
  endclass
endpackage

module tb_top_factory;
  import uvm_pkg::*;
  import mcpu_factory_pkg::*;
  initial run_test("mcpu_ovr_test");
endmodule

// Expected log (hand-derived, not simulated)
// All at time 0, in build order (env's children are built after env, in name order). File/line elided.
//
// UVM_INFO ... @ 0: uvm_test_top.env.sb_a [SB] I am mcpu_verbose_scoreboard
// UVM_INFO ... @ 0: uvm_test_top.env.sb_b [SB] I am mcpu_strict_scoreboard
// UVM_INFO ... @ 0: uvm_test_top.env.sb_c [SB] I am mcpu_scoreboard
//
// sb_a: type override applies. sb_b: instance override beats the type override (instance > type).
// sb_c: created with new(), so no override can reach it. The run phase has no objections and ends at time 0.
