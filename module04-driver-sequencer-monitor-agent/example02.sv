// Module 04 / example02.sv -- env, test and top around the ifetch agent and the real mini_cpu stub
// Demonstrates : config object created in the test and delivered through config_db, agent -> subscriber hookup,
//                drain time so the monitor sees the last instruction, end-to-end timing against the DUT
// Lesson use   : "Code Walkthrough" section 5
// Tool note    : UVM 1.2. Compile THIS file from its own directory; it includes (in order) Module 01's
//                interface + DUT, Module 03's sequence package, and example01.sv. Include-path resolution
//                is SIMULATOR-DEPENDENT: run from this directory or add +incdir.

`define MCPU_NO_TOP
`include "../module01-big-picture/example01.sv"
`include "../module03-transactions-sequences/example01.sv"
`include "example01.sv"

`timescale 1ns/1ps

package mcpu_ifetch_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;
  import mcpu_ifetch_pkg::*;

  // Temporary consumer so the monitor's output is visible (real consumers: scoreboard, coverage)
  class mcpu_bus_logger extends uvm_subscriber#(mcpu_bus_txn);
    `uvm_component_utils(mcpu_bus_logger)
    function new(string name = "mcpu_bus_logger", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void write(mcpu_bus_txn t);                  // why: uvm_subscriber's required analysis callback
      `uvm_info("FETCH", t.convert2string(), UVM_LOW)
    endfunction
  endclass

  class mcpu_env extends uvm_env;
    `uvm_component_utils(mcpu_env)
    mcpu_ifetch_agent ifetch_agent;
    mcpu_bus_logger   bus_logger;

    function new(string name = "mcpu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ifetch_agent = mcpu_ifetch_agent::type_id::create("ifetch_agent", this);
      bus_logger   = mcpu_bus_logger::type_id::create("bus_logger", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      ifetch_agent.ap.connect(bus_logger.analysis_export);   // why: broadcast fetch observations to the logger
    endfunction
  endclass

  class mcpu_ifetch_test extends uvm_test;
    `uvm_component_utils(mcpu_ifetch_test)
    mcpu_env            env;
    virtual mini_cpu_if vif;
    mcpu_agent_cfg      ifetch_cfg;

    function new(string name = "mcpu_ifetch_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
      ifetch_cfg = mcpu_agent_cfg::type_id::create("ifetch_cfg");
      ifetch_cfg.vif       = vif;
      ifetch_cfg.is_active = UVM_ACTIVE;
      // why: path is relative to this test; resolves to uvm_test_top.env.ifetch_agent
      uvm_config_db#(mcpu_agent_cfg)::set(this, "env.ifetch_agent", "cfg", ifetch_cfg);
      env = mcpu_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_directed_seq seq;
      phase.raise_objection(this, "ifetch test");
      phase.phase_done.set_drain_time(this, 20ns);           // why: monitor/logger finish the last observation
      seq = mcpu_directed_seq::type_id::create("seq");
      seq.start(env.ifetch_agent.seqr);                      // why: stimulus goes through the agent's sequencer
      phase.drop_objection(this, "ifetch test done");
    endtask
  endclass
endpackage

module tb_top;
  import uvm_pkg::*;
  import mcpu_ifetch_env_pkg::*;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  initial #42 rst_n = 1'b1;

  mini_cpu_if vif (.clk(clk), .rst_n(rst_n));
  mini_cpu    dut (.bus(vif));

  initial begin                       // load/store side and irq are not used in this module
    vif.ls_rvalid = 1'b0;
    vif.ls_rdata  = '0;
    vif.irq       = 1'b0;
  end

  initial begin
    uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);
    run_test("mcpu_ifetch_test");
  end
endmodule

// Expected log (hand-derived, not simulated)
// Time unit ns; UVM-internal lines elided. mcpu_directed_seq (Module 03) supplies 4 instructions.
// Clock posedges at 5, 15, 25, ...; reset released at 42. mini_cpu (Module 01 stub): if_req goes high after
// the first posedge following reset release (45), pc advances at each edge where if_rvalid is sampled high.
//
// UVM_INFO example01.sv(69) @ 55:  uvm_test_top.env.ifetch_agent.drv [IFD]   drive 0x00500093
// UVM_INFO example02.sv(29) @ 65:  uvm_test_top.env.bus_logger       [FETCH] RD addr=0x00000000 data=0x00500093
// UVM_INFO example01.sv(69) @ 75:  uvm_test_top.env.ifetch_agent.drv [IFD]   drive 0x00700113
// UVM_INFO example02.sv(29) @ 85:  uvm_test_top.env.bus_logger       [FETCH] RD addr=0x00000004 data=0x00700113
// UVM_INFO example01.sv(69) @ 95:  uvm_test_top.env.ifetch_agent.drv [IFD]   drive 0x002081b3
// UVM_INFO example02.sv(29) @ 105: uvm_test_top.env.bus_logger       [FETCH] RD addr=0x00000008 data=0x002081b3
// UVM_INFO example01.sv(69) @ 115: uvm_test_top.env.ifetch_agent.drv [IFD]   drive 0x00322023
// UVM_INFO example02.sv(29) @ 125: uvm_test_top.env.bus_logger       [FETCH] RD addr=0x0000000c data=0x00322023
//
// Derivation (first instruction): get_next_item returns at 0; the driver waits for if_req && rst_n. if_req is
// registered by the DUT at edge 45 (sampled high from edge 55), so the driver drives at 55 (visible after 55).
// The DUT and the monitor both see if_rvalid = 1 at edge 65 (they sample before that edge's non-blocking
// updates): the monitor reports addr = pc = 0 and the instruction word; the driver clears if_rvalid at 65 and
// calls item_done. Each further instruction costs 20 ns: one edge to see a fresh request/idle, one to drive.
// The 4th item_done is at 125, the objection drops then; drain time 20 ns ends the run phase at 145.

