// Module 05 / example01.sv -- uvm_config_db: exact path, wildcard, precedence, type matching, defaults
// Demonstrates : set/get with a context, "env.*" wildcard, higher-level-wins precedence,
//                type mismatch (int vs int unsigned), get() failing and the default being kept
// Lesson use   : "Code Walkthrough" sections 1-2
// Tool note    : UVM 1.2. Compile this file alone (own top; no DUT).

`timescale 1ns/1ps

package mcpu_cfgdb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class mcpu_cfg_agent extends uvm_component;
    `uvm_component_utils(mcpu_cfg_agent)
    // defaults: kept when get() finds nothing
    int          delay      = 5;
    string       mode       = "slow";
    int          retries_i  = 5;
    int unsigned retries_u  = 7;

    function new(string name = "mcpu_cfg_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function string src(bit found);
      return found ? "set" : "default";
    endfunction

    function void build_phase(uvm_phase phase);
      bit f_delay, f_mode, f_ri, f_ru;
      super.build_phase(phase);
      // why: each get() names a TYPE, a context+path ("" = this component) and a field; the return value says if it matched
      f_delay = uvm_config_db#(int)::get(this, "", "delay", delay);
      f_mode  = uvm_config_db#(string)::get(this, "", "mode", mode);
      f_ri    = uvm_config_db#(int)::get(this, "", "retries", retries_i);
      f_ru    = uvm_config_db#(int unsigned)::get(this, "", "retries", retries_u);   // why: different type = different entry
      `uvm_info("CFG", $sformatf("delay=%0d(%s) mode=%s(%s) retries_int=%0d(%s) retries_uint=%0d(%s)",
                delay, src(f_delay), mode, src(f_mode), retries_i, src(f_ri), retries_u, src(f_ru)), UVM_LOW)
    endfunction
  endclass

  class mcpu_cfg_env extends uvm_env;
    `uvm_component_utils(mcpu_cfg_env)
    mcpu_cfg_agent agent_a, agent_b;

    function new(string name = "mcpu_cfg_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // why: a LOWER-level set; the test sets the same field from higher up and wins (see expected log)
      uvm_config_db#(int)::set(this, "agent_a", "delay", 99);
      agent_a = mcpu_cfg_agent::type_id::create("agent_a", this);
      agent_b = mcpu_cfg_agent::type_id::create("agent_b", this);
    endfunction
  endclass

  class mcpu_cfg_test extends uvm_test;
    `uvm_component_utils(mcpu_cfg_test)
    mcpu_cfg_env env;

    function new(string name = "mcpu_cfg_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // why: context = this, so the inst_name is RELATIVE to uvm_test_top; course habit: sets BEFORE the create
      //      (strictly, the deadline is the start of the target's own build_phase)
      uvm_config_db#(int)::set(this, "env.*", "delay", 10);                // wildcard: every descendant of env
      uvm_config_db#(string)::set(this, "env.agent_b", "mode", "fast");    // exact instance
      uvm_config_db#(int)::set(this, "env.agent_a", "retries", 3);         // stored as type int
      env = mcpu_cfg_env::type_id::create("env", this);
    endfunction
  endclass
endpackage

module tb_top_cfg;
  import uvm_pkg::*;
  import mcpu_cfgdb_pkg::*;
  initial run_test("mcpu_cfg_test");
endmodule

// Expected log (hand-derived, not simulated)
// All at time 0; siblings are built in name order (agent_a, agent_b). UVM-internal lines elided.
//
// UVM_INFO example01.sv(37) @ 0: uvm_test_top.env.agent_a [CFG] delay=10(set) mode=slow(default) retries_int=3(set) retries_uint=7(default)
// UVM_INFO example01.sv(37) @ 0: uvm_test_top.env.agent_b [CFG] delay=10(set) mode=fast(set) retries_int=5(default) retries_uint=7(default)
//
// agent_a delay: the test's set (context = test, higher in the hierarchy) beats the env's set of 99 for the same scope.
// agent_a mode: nobody set it for agent_a -> default. retries: stored as int, so only the int get matches;
// the int unsigned get is a different type and misses. agent_b: wildcard delay, exact mode, no retries set at all.

