`ifndef MCPU_INC_M04_EX01
`define MCPU_INC_M04_EX01
// Module 04 / example01.sv -- instruction-fetch agent: config object, bus transaction, driver, monitor, agent
// Demonstrates : get_next_item/item_done handshake, virtual-interface driving and sampling,
//                analysis-port monitor, active vs passive agent, config object hand-off
// Lesson use   : "Code Walkthrough" sections 1-4
// Tool note    : UVM 1.2. This file is a PACKAGE; compile it through example02.sv, which includes
//                Module 01's mini_cpu_if/mini_cpu and Module 03's cpu_instr_item first.
//
// Fetch-bus protocol implemented here (mini_cpu is the master, the agent is the memory side):
//   - DUT holds if_req high with if_addr = current pc.
//   - The agent answers with a ONE-cycle if_rvalid pulse and if_rdata = instruction word.
//   - DUT consumes the word at the clock edge where it samples if_rvalid = 1.
// Simplification: instructions are served in sequence order; if_addr is only OBSERVED (monitor), not used.

`timescale 1ns/1ps

package mcpu_ifetch_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;               // cpu_instr_item, mcpu_ifetch_seqr (Module 03)

  // What a monitor reports for one bus access (used by the fetch and, later, load/store sides)
  class mcpu_bus_txn extends uvm_sequence_item;
    `uvm_object_utils(mcpu_bus_txn)
    bit [31:0] addr, data;
    bit        is_write;
    function new(string name = "mcpu_bus_txn");
      super.new(name);
    endfunction
    virtual function string convert2string();
      return $sformatf("%s addr=0x%08h data=0x%08h", is_write ? "WR" : "RD", addr, data);
    endfunction
  endclass

  // Agent configuration: an OBJECT carrying the vif and the active/passive choice
  class mcpu_agent_cfg extends uvm_object;
    `uvm_object_utils(mcpu_agent_cfg)
    virtual mini_cpu_if     vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    function new(string name = "mcpu_agent_cfg");
      super.new(name);
    endfunction
  endclass

  class mcpu_ifetch_driver extends uvm_driver#(cpu_instr_item);
    `uvm_component_utils(mcpu_ifetch_driver)
    mcpu_agent_cfg      cfg;            // assigned by the agent right after create()
    virtual mini_cpu_if vif;

    function new(string name = "mcpu_ifetch_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null) `uvm_fatal("NOCFG", "ifetch driver: cfg was not set by the agent")
      vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
      vif.if_rvalid <= 1'b0;                              // why: idle value from time 0
      vif.if_rdata  <= '0;
      forever begin
        seq_item_port.get_next_item(req);                 // why: blocks until a sequence sends the next instruction
        do @(posedge vif.clk); while (!(vif.rst_n && vif.if_req));   // why: serve only a real request
        vif.if_rdata  <= req.encode();                    // why: non-blocking after the edge = race-free vs DUT sampling
        vif.if_rvalid <= 1'b1;
        `uvm_info("IFD", $sformatf("drive 0x%08h", req.encode()), UVM_LOW)
        @(posedge vif.clk);
        vif.if_rvalid <= 1'b0;                            // why: one-cycle pulse
        seq_item_port.item_done();                        // why: exactly one item_done per get_next_item
      end
    endtask
  endclass

  class mcpu_ifetch_monitor extends uvm_monitor;
    `uvm_component_utils(mcpu_ifetch_monitor)
    uvm_analysis_port#(mcpu_bus_txn) ap;
    mcpu_agent_cfg      cfg;
    virtual mini_cpu_if vif;

    function new(string name = "mcpu_ifetch_monitor", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);                               // why: analysis ports are constructed with new, not the factory
      if (cfg == null) `uvm_fatal("NOCFG", "ifetch monitor: cfg was not set by the agent")
      vif = cfg.vif;
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_bus_txn txn;
      forever begin
        @(posedge vif.clk);                               // why: sample at the edge = values from the previous cycle
        if (vif.rst_n && vif.if_rvalid) begin
          txn = mcpu_bus_txn::type_id::create("txn");     // why: NEW object per observation; subscribers keep the handle
          txn.addr     = vif.if_addr;
          txn.data     = vif.if_rdata;
          txn.is_write = 1'b0;
          ap.write(txn);                                  // why: non-blocking broadcast to every connected subscriber
        end
      end
    endtask
  endclass

  class mcpu_ifetch_agent extends uvm_agent;
    `uvm_component_utils(mcpu_ifetch_agent)
    mcpu_agent_cfg                   cfg;
    mcpu_ifetch_seqr                 seqr;
    mcpu_ifetch_driver               drv;
    mcpu_ifetch_monitor              mon;
    uvm_analysis_port#(mcpu_bus_txn) ap;

    function new(string name = "mcpu_ifetch_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(mcpu_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "mcpu_agent_cfg not found for ifetch agent")
      ap  = new("ap", this);
      mon = mcpu_ifetch_monitor::type_id::create("mon", this);
      mon.cfg = cfg;                                      // why: parent hands the config to the child after create
      if (cfg.is_active == UVM_ACTIVE) begin              // why: a passive agent has no driver or sequencer
        seqr = mcpu_ifetch_seqr::type_id::create("seqr", this);
        drv  = mcpu_ifetch_driver::type_id::create("drv", this);
        drv.cfg = cfg;
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      mon.ap.connect(ap);                                 // why: promote the monitor's port to the agent's boundary
      if (cfg.is_active == UVM_ACTIVE)
        drv.seq_item_port.connect(seqr.seq_item_export);  // why: driver pulls from this sequencer
    endfunction
  endclass
endpackage

// ---- end of file ----

`endif
