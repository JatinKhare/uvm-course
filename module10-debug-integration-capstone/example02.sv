// Module 10 / example02.sv -- the integrated environment, base test, smoke test and a mid-run reset test
// Demonstrates : env wiring (fetch agent, retire monitor, scoreboard, coverage), a base test that owns configuration,
//                timeout and the factory override, reset handling with scoreboard flush, tests selected by +UVM_TESTNAME,
//                a plusarg-selected DUT bug for negative testing
// Lesson use   : "Code Walkthrough" sections 2-5
// Tool note    : UVM 1.2. Compile THIS file from its own directory; it includes Module 06 example02 (retire monitor, chain
//                to Modules 01/03/04/06), Module 08 example01 (coverage), and example01.sv (DUT). Include-path
//                resolution is SIMULATOR-DEPENDENT.
// Run          : +UVM_TESTNAME=mcpu_smoke_test | mcpu_reset_test ; optional +MCPU_BUG_ADD (DUT mutation)

`define MCPU_SKIP_LEAF_TOPS
`include "../module06-scoreboard-reference-model/example02.sv"
`include "../module08-functional-coverage/example01.sv"
`include "example01.sv"

`timescale 1ns/1ps

package mcpu_integ_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;
  import mcpu_ifetch_pkg::*;
  import mcpu_sb_pkg::*;
  import mcpu_sb_env_pkg::*;                        // mcpu_retire_monitor
  import mcpu_cov_pkg::*;                           // mcpu_instr_cov

  // Scoreboard variant that can be brought back in step after a DUT reset (installed by factory override)
  class mcpu_rst_scoreboard extends mcpu_scoreboard;
    `uvm_component_utils(mcpu_rst_scoreboard)
    function new(string name = "mcpu_rst_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void flush();                          // forget in-flight work, restart the model; keep the counters
      exp_q.delete();
      act_q.delete();
      iss = new();
    endfunction
  endclass

  // The program of Module 06: ADDI x1,5 ; ADDI x2,7 ; ADD x3,x1,x2 ; SW x3,0(x4) ; LW x5,0(x4)
  class mcpu_smoke_prog_seq extends mcpu_instr_seq_base;
    `uvm_object_utils(mcpu_smoke_prog_seq)
    function new(string name = "mcpu_smoke_prog_seq");
      super.new(name);
    endfunction
    task body();
      send_instr(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd5);
      send_instr(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd7);
      send_instr(OP_ADD,  5'd3, 5'd1, 5'd2, 12'd0);
      send_instr(OP_SW,   5'd0, 5'd4, 5'd3, 12'd0);
      send_instr(OP_LW,   5'd5, 5'd4, 5'd0, 12'd0);
    endtask
  endclass

  class mcpu_env extends uvm_env;
    `uvm_component_utils(mcpu_env)
    mcpu_agent_cfg      cfg;
    mcpu_ifetch_agent   ifetch_agent;
    mcpu_retire_monitor retire_mon;
    mcpu_scoreboard     sb;
    mcpu_instr_cov      cov;
    function new(string name = "mcpu_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(mcpu_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "mcpu_env: cfg not set by the test")
      uvm_config_db#(mcpu_agent_cfg)::set(this, "ifetch_agent", "cfg", cfg);
      ifetch_agent = mcpu_ifetch_agent::type_id::create("ifetch_agent", this);
      retire_mon   = mcpu_retire_monitor::type_id::create("retire_mon", this);
      retire_mon.cfg = cfg;
      sb           = mcpu_scoreboard::type_id::create("sb", this);          // factory: may be overridden
      cov          = mcpu_instr_cov::type_id::create("cov", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      ifetch_agent.ap.connect(sb.fetch_imp);
      retire_mon.ap.connect(sb.retire_imp);
      retire_mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  class mcpu_env_base_test extends uvm_test;
    `uvm_component_utils(mcpu_env_base_test)
    mcpu_env            env;
    mcpu_agent_cfg      cfg;
    virtual mini_cpu_if vif;
    function new(string name = "mcpu_env_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
      cfg = mcpu_agent_cfg::type_id::create("cfg");
      cfg.vif       = vif;
      cfg.is_active = UVM_ACTIVE;
      uvm_config_db#(mcpu_agent_cfg)::set(this, "env", "cfg", cfg);
      mcpu_scoreboard::type_id::set_type_override(mcpu_rst_scoreboard::get_type());   // overrides BEFORE the env is created
      uvm_top.set_timeout(10us, 0);                                                  // a hung test becomes a clean fatal
      env = mcpu_env::type_id::create("env", this);
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      `uvm_info("TEST", $sformatf("running %s (run-phase timeout 10 us)", get_type_name()), UVM_LOW)
    endfunction
  endclass

  class mcpu_smoke_test extends mcpu_env_base_test;
    `uvm_component_utils(mcpu_smoke_test)
    function new(string name = "mcpu_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      mcpu_smoke_prog_seq seq;
      phase.raise_objection(this, "smoke");
      phase.phase_done.set_drain_time(this, 50ns);          // let the last retirement be observed and compared
      seq = mcpu_smoke_prog_seq::type_id::create("seq");
      seq.start(env.ifetch_agent.seqr);
      phase.drop_objection(this, "smoke done");
    endtask
  endclass

  class mcpu_reset_test extends mcpu_env_base_test;
    `uvm_component_utils(mcpu_reset_test)
    virtual mcpu_rst_ctl_if rstc;
    function new(string name = "mcpu_reset_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual mcpu_rst_ctl_if)::get(this, "", "rstc", rstc))
        `uvm_fatal("NORSTC", "reset control interface 'rstc' not found")
    endfunction
    task run_phase(uvm_phase phase);
      mcpu_smoke_prog_seq s1, s2;
      mcpu_rst_scoreboard rsb;
      phase.raise_objection(this, "reset test");
      phase.phase_done.set_drain_time(this, 50ns);
      s1 = mcpu_smoke_prog_seq::type_id::create("s1");
      s1.start(env.ifetch_agent.seqr);
      #52ns;                                            // settle: the last retirement is observed and compared BEFORE reset
      rstc.req = 1'b1;                                  // tb_top pulses rst_n low for two clocks
      @(negedge vif.rst_n);
      @(posedge vif.rst_n);                             // the DUT is out of reset
      if (!$cast(rsb, env.sb)) `uvm_fatal("CAST", "scoreboard is not the reset-capable variant")
      rsb.flush();                                      // model and queues back to their initial state
      s2 = mcpu_smoke_prog_seq::type_id::create("s2");
      s2.start(env.ifetch_agent.seqr);
      phase.drop_objection(this, "reset test done");
    endtask
  endclass
endpackage

module tb_top;
  import uvm_pkg::*;
  import mcpu_integ_pkg::*;
  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  initial #42 rst_n = 1'b1;

  mini_cpu_if     vif  (.clk(clk), .rst_n(rst_n));
  mcpu_rst_ctl_if rstc ();
  mini_cpu_core   dut  (.bus(vif));

  always @(posedge rstc.req) begin                      // test-requested reset: low for 2 posedges, released on a negedge
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    rstc.req = 1'b0;
  end

  initial begin                                         // unused inputs of the DUT port
    vif.ls_rvalid = 1'b0;
    vif.ls_rdata  = '0;
    vif.irq       = 1'b0;
  end

  initial begin
    uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);
    uvm_config_db#(virtual mcpu_rst_ctl_if)::set(null, "uvm_test_top", "rstc", rstc);
    run_test();                                         // test name from +UVM_TESTNAME
  end
endmodule

// Expected log (hand-derived, not simulated). UVM-internal lines elided. "M06" / "M08" name the example01.sv the line is in.
// Timing comes from example01.sv: executions at 65, 95, 125, 155, 185; retire records observed at 75, 105, 135, 165, 195.
//
// 1) +UVM_TESTNAME=mcpu_smoke_test  (program 1 ends at 185; drain 50 ns -> run phase ends at 235)
//    UVM_INFO example02.sv(106) @ 0:   uvm_test_top [TEST] running mcpu_smoke_test (run-phase timeout 10 us)
//    UVM_INFO M08(103)  @ 235: uvm_test_top.env.cov [COV] class=66.7 dist=50.0 cross=16.7 total=44.4
//    UVM_INFO M06(169)  @ 235: uvm_test_top.env.sb  [SB] fetched=5 compared=5 mismatched=0
//    (the order of the last two lines at the same time is not specified by UVM)
//
// 2) +UVM_TESTNAME=mcpu_smoke_test +MCPU_BUG_ADD  (DUT mutation: ADD returns a+b+1, so x3 = 13)
//    UVM_ERROR M06(152) @ 135: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #3 exp: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000c | act: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000d
//    UVM_ERROR M06(152) @ 195: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #5 exp: pc=0x00000010 instr=0x00022283 rd=x5 data=0x0000000c | act: pc=0x00000010 instr=0x00022283 rd=x5 data=0x0000000d
//    UVM_INFO M06(169)  @ 235: uvm_test_top.env.sb [SB] fetched=5 compared=5 mismatched=2
//    The SW (retirement #4) matches because stores retire with rd=0, data=0; the wrong x3 is stored and loaded back, so
//    the LW (#5) mismatches too. Report summary: 2 UVM_ERRORs. The bug is caught at the first affected retirement.
//
// 3) +UVM_TESTNAME=mcpu_reset_test
//    Program 1 ends at 185. #52ns -> 237: reset requested (rst_n low at 237, DUT sees it at edges 245 and 255, released at
//    the 260 negedge). The test flushes the scoreboard at 260 and starts program 2: the DUT has been reset (pc 0, registers
//    and data memory cleared), so executions are at 285, 315, 345, 375, 405 and program 2 ends at 405; drain -> 455.
//    UVM_INFO example02.sv(106) @ 0:   uvm_test_top [TEST] running mcpu_reset_test (run-phase timeout 10 us)
//    UVM_INFO M08(103)  @ 455: uvm_test_top.env.cov [COV] class=66.7 dist=50.0 cross=16.7 total=44.4
//    UVM_INFO M06(169)  @ 455: uvm_test_top.env.sb  [SB] fetched=10 compared=10 mismatched=0
//    (program 2 produces the same coverage samples as program 1, so the coverage numbers do not change.)

