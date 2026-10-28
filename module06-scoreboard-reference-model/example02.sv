`ifndef MCPU_INC_M06_EX02
`define MCPU_INC_M06_EX02
// Module 06 / example02.sv -- env and test exercising the scoreboard with a synthetic DUT-side stream
// Demonstrates : monitor -> scoreboard wiring, a deliberately corrupted retirement being caught,
//                the retire monitor that will observe the real DUT (not used in this synthetic run)
// Lesson use   : "Code Walkthrough" section 5
// Tool note    : UVM 1.2. Compile THIS file; it includes example01.sv (which includes Modules 01/03/04).
//
// WHY SYNTHETIC: the Module 01 stub DUT does not execute instructions (it always retires rd=0, data=0), so a
// full-compare against the ISS would report mismatches that say nothing about the testbench. The feeder below
// plays "fetch monitor" and "retire monitor" with hand-picked data; the third retirement is wrong on purpose.

`include "../module06-scoreboard-reference-model/example01.sv"

`timescale 1ns/1ps

package mcpu_sb_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_ifetch_pkg::*;
  import mcpu_sb_pkg::*;

  // Monitor for the DUT's retire trace (for the integrated bench, Module 10)
  class mcpu_retire_monitor extends uvm_monitor;
    `uvm_component_utils(mcpu_retire_monitor)
    uvm_analysis_port#(mcpu_retire_txn) ap;
    mcpu_agent_cfg      cfg;
    virtual mini_cpu_if vif;
    function new(string name = "mcpu_retire_monitor", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (cfg == null) `uvm_fatal("NOCFG", "retire monitor: cfg was not set")
      vif = cfg.vif;
    endfunction
    task run_phase(uvm_phase phase);
      mcpu_retire_txn t;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n && vif.retire_valid) begin
          t = mcpu_retire_txn::type_id::create("t");
          t.pc = vif.retire_pc;  t.instr = vif.retire_instr;  t.rd = vif.retire_rd;  t.data = vif.retire_data;
          ap.write(t);
        end
      end
    endtask
  endclass

  // Synthetic stand-in for both monitors (the "DUT" retires the right thing except for the 3rd instruction)
  class mcpu_sb_feed extends uvm_component;
    `uvm_component_utils(mcpu_sb_feed)
    uvm_analysis_port#(mcpu_bus_txn)    fetch_ap;
    uvm_analysis_port#(mcpu_retire_txn) retire_ap;
    // ADDI x1,x0,5 ; ADDI x2,x0,7 ; ADD x3,x1,x2 ; SW x3,0(x4) ; LW x5,0(x4)
    bit [31:0] prog     [5] = '{32'h00500093, 32'h00700113, 32'h002081b3, 32'h00322023, 32'h00022283};
    bit [4:0]  act_rd   [5] = '{5'd1, 5'd2, 5'd3, 5'd0, 5'd5};
    bit [31:0] act_data [5] = '{32'd5, 32'd7, 32'd13, 32'd0, 32'd12};   // 13 is wrong: x1+x2 = 12

    function new(string name = "mcpu_sb_feed", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      fetch_ap  = new("fetch_ap", this);
      retire_ap = new("retire_ap", this);
    endfunction

    task send_fetches();                               // fetch observations at 0, 10, 20, 30, 40 ns
      mcpu_bus_txn t;
      for (int i = 0; i < 5; i++) begin
        t = mcpu_bus_txn::type_id::create("f");
        t.addr = i * 4;  t.data = prog[i];  t.is_write = 1'b0;
        fetch_ap.write(t);
        #10ns;
      end
    endtask

    task send_retires();                               // retirements 15 ns later: 15, 25, 35, 45, 55 ns
      mcpu_retire_txn t;
      #15ns;
      for (int i = 0; i < 5; i++) begin
        t = mcpu_retire_txn::type_id::create("r");
        t.pc = i * 4;  t.instr = prog[i];  t.rd = act_rd[i];  t.data = act_data[i];
        retire_ap.write(t);
        #10ns;
      end
    endtask

    task run_phase(uvm_phase phase);
      fork
        send_fetches();
        send_retires();
      join
    endtask
  endclass

  class mcpu_sb_env extends uvm_env;
    `uvm_component_utils(mcpu_sb_env)
    mcpu_sb_feed    feed;
    mcpu_scoreboard sb;
    function new(string name = "mcpu_sb_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      feed = mcpu_sb_feed::type_id::create("feed", this);
      sb   = mcpu_scoreboard::type_id::create("sb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      feed.fetch_ap.connect(sb.fetch_imp);
      feed.retire_ap.connect(sb.retire_imp);
    endfunction
  endclass

  class mcpu_sb_test extends uvm_test;
    `uvm_component_utils(mcpu_sb_test)
    mcpu_sb_env env;
    function new(string name = "mcpu_sb_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mcpu_sb_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "sb test");
      #100ns;
      phase.drop_objection(this, "sb test done");
    endtask
  endclass
endpackage

`ifndef MCPU_SKIP_LEAF_TOPS
module tb_top_sb;
  import uvm_pkg::*;
  import mcpu_sb_env_pkg::*;
  initial run_test("mcpu_sb_test");
endmodule
`endif

// Expected log (hand-derived, not simulated)
// Fetch observations at 0,10,20,30,40 ns (each runs the ISS and queues an expected entry); retirements at
// 15,25,35,45,55 ns. Comparison #n happens when retirement n arrives (its expected entry is already queued).
// ISS: x1=5, x2=7, x3=x1+x2=12, SW stores 12 at mem[x4+0]=mem[0], LW x5 reads mem[0]=12.
// UVM-internal lines elided; the file name is where the macro lives (example01.sv).
//
// UVM_ERROR example01.sv(152) @ 35: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #3 exp: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000c | act: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000d
// UVM_INFO  example01.sv(169) @ 100: uvm_test_top.env.sb [SB] fetched=5 compared=5 mismatched=1
//
// Retirements #1, #2, #4, #5 match (SW and the check on x0: rd=x0 data=0 on both sides). No PC_MISMATCH: fetch
// addresses 0,4,8,12,16 equal the ISS pc (no taken branch). check_phase finds both queues empty and n_cmp=5,
// so no SB_* messages. The UVM report summary shows 1 UVM_ERROR; the run phase (and report_phase) end at 100 ns.


`endif
