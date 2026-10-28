// Module 08 / example02.sv -- coverage closure: measure, find holes, add targeted stimulus, measure again
// Demonstrates : three stimulus phases accumulating into one covergroup; what each phase closes and what stays open
// Lesson use   : "Code Walkthrough" section 4
// Tool note    : UVM 1.2. Compile this file; it includes example01.sv (and, through it, Modules 01/03/04/06).
//                Run from this directory; include-path resolution is SIMULATOR-DEPENDENT.

`define MCPU_SKIP_LEAF_TOPS
`include "../module08-functional-coverage/example01.sv"

`timescale 1ns/1ps

package mcpu_closure_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;
  import mcpu_sb_pkg::*;
  import mcpu_cov_pkg::*;

  class mcpu_closure_test extends uvm_test;
    `uvm_component_utils(mcpu_closure_test)
    mcpu_cov_env env;
    function new(string name = "mcpu_closure_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = mcpu_cov_env::type_id::create("env", this);
    endfunction
    function void feed(bit [31:0] w);
      mcpu_retire_txn t;
      t = mcpu_retire_txn::type_id::create("t");
      t.instr = w;
      env.cov.write(t);
    endfunction
    function void phase_report(string tag);
      `uvm_info("CLOSURE", {"after ", tag, ": ", env.cov.cov_line()}, UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "closure test");

      // Phase A: the Module 06 program (arithmetic, store, load)
      env.cov.reset_history();
      feed(mcpu_mk_word(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd5));
      feed(mcpu_mk_word(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd7));
      feed(mcpu_mk_word(OP_ADD,  5'd3, 5'd1, 5'd2, 12'd0));    // reads x2 (1 back) and x1 (2 back): nearest = 1
      feed(mcpu_mk_word(OP_SW,   5'd0, 5'd4, 5'd3, 12'd0));    // reads x3 (1 back)
      feed(mcpu_mk_word(OP_LW,   5'd5, 5'd4, 5'd0, 12'd0));    // x4 never written: no producer
      phase_report("A");

      // Phase B: targeted at the hazard-distance holes (distance 2 and 3) and at BEQ
      env.cov.reset_history();
      feed(mcpu_mk_word(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd1));
      feed(mcpu_mk_word(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd2));
      feed(mcpu_mk_word(OP_ADDI, 5'd3, 5'd0, 5'd0, 12'd3));
      feed(mcpu_mk_word(OP_ADD,  5'd4, 5'd1, 5'd2, 12'd0));    // x1 is 3 back, x2 is 2 back: nearest = 2
      feed(mcpu_mk_word(OP_BEQ,  5'd0, 5'd3, 5'd2, 12'd4));    // x3 is 2 back, x2 is 3 back: nearest = 2
      feed(mcpu_mk_word(OP_LW,   5'd6, 5'd3, 5'd0, 12'd0));    // BEQ wrote nothing, x4 is 2 back, x3 is 3 back: = 3
      phase_report("B");

      // Phase C: the one opcode class still missing (CSRRW)
      env.cov.reset_history();
      feed(mcpu_mk_word(OP_ADDI,  5'd1, 5'd0, 5'd0, 12'd5));
      feed(mcpu_mk_word(OP_CSRRW, 5'd2, 5'd1, 5'd0, 12'h300)); // reads x1 (1 back)
      phase_report("C");

      phase.drop_objection(this, "closure test done");
    endtask
  endclass
endpackage

module tb_top_closure;
  import uvm_pkg::*;
  import mcpu_closure_pkg::*;
  initial run_test("mcpu_closure_test");
endmodule

// Expected log (hand-derived, not simulated); all at time 0, UVM-internal lines elided. The coverage ACCUMULATES.
//
// UVM_INFO example02.sv(36)  @ 0: uvm_test_top [CLOSURE] after A: class=66.7 dist=50.0 cross=16.7 total=44.4
// UVM_INFO example02.sv(36)  @ 0: uvm_test_top [CLOSURE] after B: class=83.3 dist=100.0 cross=29.2 total=70.8
// UVM_INFO example02.sv(36)  @ 0: uvm_test_top [CLOSURE] after C: class=100.0 dist=100.0 cross=33.3 total=77.8
// UVM_INFO example01.sv(103) @ 0: uvm_test_top.env.cov [COV] class=100.0 dist=100.0 cross=33.3 total=77.8
//
// Phase A hits (addi,none) (r,d1) (sw,d1) (lw,none).
// Phase B samples: ADDI x3 none (x1 .. none); ADD -> (r,d2); BEQ -> (beq,d2); LW -> (lw,d3). New: classes beq; dists d2,d3;
//   cross +3 = 7 of 24 -> class 5/6 = 83.3, dist 4/4 = 100.0, cross 29.2, total (83.33 + 100 + 29.17)/3 = 70.8.
// Phase C: CSRRW reading x1 from 1 back -> (csr,d1): class 6/6 = 100.0, cross 8/24 = 33.3, total (100 + 100 + 33.33)/3 = 77.8.
// Closure lesson: the one-dimensional coverpoints close quickly; the cross stays at 8/24 and needs targeted or
// random-with-weights stimulus for the remaining 16 combinations.

