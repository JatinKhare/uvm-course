`ifndef MCPU_INC_M01_EX01
`define MCPU_INC_M01_EX01
// Module 01 / example01.sv -- first UVM testbench around mini_cpu
// Demonstrates : mini_cpu_if, a stub DUT, tb_top, mcpu_base_test, run_test()
// Lesson use   : "Code Walkthrough" sections 1-4
// Tool note    : UVM 1.2 (IEEE 1800.2-2017). Compile this file alone.
//
// The DUT here is a STUB: it fetches sequential addresses and "retires" whatever
// the fetch bus returns. It exists only so the testbench has signals to observe.
// The fetch-bus responder in tb_top is a placeholder; Module 04 replaces it with an agent.

`timescale 1ns/1ps

//--------------------------------------------------------------------------
// Interface: the single bundle of DUT-facing signals (static SV, not a class)
//--------------------------------------------------------------------------
interface mini_cpu_if (input logic clk, input logic rst_n);
  // Instruction-fetch bus
  logic        if_req;
  logic [31:0] if_addr;
  logic        if_rvalid;
  logic [31:0] if_rdata;
  // Load/store bus
  logic        ls_req;
  logic        ls_we;
  logic [31:0] ls_addr;
  logic [31:0] ls_wdata;
  logic        ls_rvalid;
  logic [31:0] ls_rdata;
  // Interrupt line
  logic        irq;
  // Retire trace (one entry per retired instruction)
  logic        retire_valid;
  logic [31:0] retire_pc;
  logic [31:0] retire_instr;
  logic [4:0]  retire_rd;
  logic [31:0] retire_data;

  modport dut (
    input  clk, rst_n, if_rvalid, if_rdata, ls_rvalid, ls_rdata, irq,
    output if_req, if_addr, ls_req, ls_we, ls_addr, ls_wdata,
           retire_valid, retire_pc, retire_instr, retire_rd, retire_data
  );
endinterface

//--------------------------------------------------------------------------
// Stub DUT
//--------------------------------------------------------------------------
module mini_cpu (mini_cpu_if.dut bus);
  logic [31:0] pc;

  assign bus.if_addr = pc;

  always_ff @(posedge bus.clk) begin
    // defaults: units this stub does not model stay quiet
    bus.ls_req    <= 1'b0;
    bus.ls_we     <= 1'b0;
    bus.ls_addr   <= '0;
    bus.ls_wdata  <= '0;
    bus.retire_rd   <= '0;
    bus.retire_data <= '0;
    if (!bus.rst_n) begin
      pc               <= 32'h0000_0000;
      bus.if_req       <= 1'b0;
      bus.retire_valid <= 1'b0;
      bus.retire_pc    <= '0;
      bus.retire_instr <= '0;
    end else begin
      bus.if_req       <= 1'b1;
      bus.retire_valid <= bus.if_rvalid;
      if (bus.if_rvalid) begin
        bus.retire_pc    <= pc;
        bus.retire_instr <= bus.if_rdata;
        pc               <= pc + 32'd4;
      end
    end
  end
endmodule

//--------------------------------------------------------------------------
// TB package: class world
//--------------------------------------------------------------------------
package mcpu_pkg;
  import uvm_pkg::*;                 // why: brings in all UVM classes and run_test()
  `include "uvm_macros.svh"          // why: macros are preprocessor text, not part of the package

  class mcpu_base_test extends uvm_test;
    `uvm_component_utils(mcpu_base_test)   // why: registers the class with the factory so run_test("mcpu_base_test") can find it

    virtual mini_cpu_if vif;               // why: handle that lets class code reach the static interface

    function new(string name = "mcpu_base_test", uvm_component parent = null);
      super.new(name, parent);             // why: links this component into the hierarchy under parent
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);            // why: base-class build work; always call first
      // why: fetch the vif that tb_top stored; the get() return value MUST be checked
      if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
      `uvm_info("BUILD", "mcpu_base_test built, vif acquired", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "mcpu_base_test running");   // why: without an objection the run phase ends at time 0
      `uvm_info("RUN", "waiting for reset release", UVM_LOW)
      @(posedge vif.rst_n);
      `uvm_info("RUN", "reset released; observing 5 retired instructions", UVM_LOW)
      repeat (5) begin
        @(posedge vif.clk);
        while (!vif.retire_valid) @(posedge vif.clk);
        `uvm_info("RUN", $sformatf("retire pc=0x%08h instr=0x%08h", vif.retire_pc, vif.retire_instr), UVM_LOW)
      end
      phase.drop_objection(this, "observed 5 retires");        // why: lets the run phase end once the test is done
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("REPORT", "mcpu_base_test finished", UVM_LOW)
    endfunction
  endclass
endpackage

//--------------------------------------------------------------------------
// Top: module world. Clock, reset, DUT, interface, and the hand-off to UVM.
//--------------------------------------------------------------------------
`ifndef MCPU_NO_TOP   // later modules `define MCPU_NO_TOP and `include this file to reuse mini_cpu_if / mini_cpu
module tb_top;
  import uvm_pkg::*;
  import mcpu_pkg::*;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5 clk = ~clk;                 // 10 ns period: posedges at 5, 15, 25, ...
  initial begin
    #42 rst_n = 1'b1;                   // release reset at 42 ns
  end

  mini_cpu_if vif (.clk(clk), .rst_n(rst_n));
  mini_cpu    dut (.bus(vif));

  // Placeholder fetch-bus responder: every request is answered next cycle with NOP (ADDI x0,x0,0).
  always @(posedge clk) begin
    vif.if_rvalid <= vif.if_req;
    vif.if_rdata  <= 32'h0000_0013;
  end
  initial begin
    vif.ls_rvalid = 1'b0;
    vif.ls_rdata  = '0;
    vif.irq       = 1'b0;
  end

  initial begin
    // why: set BEFORE run_test(); path "uvm_test_top" is the instance name UVM gives the test
    uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);
    run_test("mcpu_base_test");         // why: builds the test via the factory, runs all phases, then $finish
  end
endmodule
`endif

// Expected log (hand-derived, not simulated)
// Assumes: global time unit ns; UVM-internal lines (banner, RNTST, TEST_DONE, report summary) elided;
// the file path printed after UVM_INFO is whatever path your compile used.
//
// [... UVM banner and "Running test mcpu_base_test..." ...]
// UVM_INFO example01.sv(101)  @ 0:   uvm_test_top [BUILD]  mcpu_base_test built, vif acquired
// UVM_INFO example01.sv(106) @ 0:   uvm_test_top [RUN]    waiting for reset release
// UVM_INFO example01.sv(108) @ 42:  uvm_test_top [RUN]    reset released; observing 5 retired instructions
// UVM_INFO example01.sv(112) @ 75:  uvm_test_top [RUN]    retire pc=0x00000000 instr=0x00000013
// UVM_INFO example01.sv(112) @ 85:  uvm_test_top [RUN]    retire pc=0x00000004 instr=0x00000013
// UVM_INFO example01.sv(112) @ 95:  uvm_test_top [RUN]    retire pc=0x00000008 instr=0x00000013
// UVM_INFO example01.sv(112) @ 105: uvm_test_top [RUN]    retire pc=0x0000000c instr=0x00000013
// UVM_INFO example01.sv(112) @ 115: uvm_test_top [RUN]    retire pc=0x00000010 instr=0x00000013
// UVM_INFO example01.sv(119) @ 115: uvm_test_top [REPORT] mcpu_base_test finished
// [... UVM report summary ...]
//
// Derivation of 75 ns: reset releases at 42; first posedge after is 45 (DUT raises if_req, visible after 45);
// responder sees if_req at 55 -> if_rvalid high after 55; DUT sees if_rvalid at 65 -> retire_valid high after 65;
// the test samples retire_valid at posedge 75 (before that edge's non-blocking updates). Then one per 10 ns.


`endif
