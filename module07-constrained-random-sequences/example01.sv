// Module 07 / example01.sv -- constraint patterns on cpu_instr_item, checked by properties
// Demonstrates : dist (:= vs :/), solve...before, inline with{}, rand_mode(0) turning a field into a constant,
//                constraint_mode(0) for deliberate negative stimulus, srandom reproducibility
// Lesson use   : "Code Walkthrough" sections 1-3
// Tool note    : UVM 1.2. Compile this file; it includes Module 03's example01.sv (sequence package) with
//                MCPU_NO_TOP defined. Run from this directory; include-path resolution is SIMULATOR-DEPENDENT.
//
// Random values cannot be hand-traced, so every check below is a PROPERTY that must hold for every seed;
// the expected log lists what the test prints when the constraints are right.

`define MCPU_NO_TOP
`include "../module03-transactions-sequences/example01.sv"

`timescale 1ns/1ps

package mcpu_rand_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;

  // Opcode mix as percentages (sum 100): R-type ALU 40 (10 each), ADDI 20, LW 15, SW 15, BEQ 5, CSRRW 5
  class mcpu_mix_item extends cpu_instr_item;
    `uvm_object_utils(mcpu_mix_item)
    // why :/ for the range: the weight 40 is SPLIT over the 4 values (10 each); := would give each value 40
    constraint c_mix   { op dist { [OP_ADD:OP_OR] :/ 40, OP_ADDI := 20, OP_LW := 15, OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5 }; }
    // why: choose op first, so the mix above is not skewed by how many imm values each op leaves legal
    constraint c_order { solve op before imm; }
    function new(string name = "mcpu_mix_item");
      super.new(name);
    endfunction
  endclass

  class mcpu_rand_test extends uvm_test;
    `uvm_component_utils(mcpu_rand_test)
    function new(string name = "mcpu_rand_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // legality properties that every generated item must satisfy
    function bit legal(cpu_instr_item it);
      if (it.op inside {OP_LW, OP_SW} && it.imm[1:0] != 2'b00) return 0;
      if (it.op == OP_CSRRW && !(it.imm inside {12'h300, 12'h305, 12'h341})) return 0;
      if (it.op inside {OP_SW, OP_BEQ} && it.rd != 0) return 0;
      return 1;
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_mix_item  mix;
      cpu_instr_item base, a, b;
      int unsigned   bad, forbidden;
      int            ok_on, ok_off;

      phase.raise_objection(this, "rand test");

      // Part 1: the mix item is always legal
      mix = mcpu_mix_item::type_id::create("mix");
      bad = 0;
      repeat (500) begin
        if (!mix.randomize()) `uvm_error("RAND", "mix randomize failed")
        if (!legal(mix)) bad++;
      end
      `uvm_info("GEN", $sformatf("part1: n=500 illegal_items=%0d", bad), UVM_LOW)

      // Part 2: inline constraint narrows the scenario
      bad = 0;
      repeat (200) begin
        if (!mix.randomize() with { op inside {OP_LW, OP_SW}; }) `uvm_error("RAND", "inline randomize failed")
        if (!(mix.op inside {OP_LW, OP_SW}) || !legal(mix)) bad++;
      end
      `uvm_info("GEN", $sformatf("part2: n=200 not_lw_sw_or_illegal=%0d", bad), UVM_LOW)

      // Part 3: a non-rand field is a constant; here imm = 0x123 (low bits 11) forbids LW, SW and CSRRW
      base = cpu_instr_item::type_id::create("base");
      base.imm.rand_mode(0);
      base.imm = 12'h123;
      forbidden = 0;  bad = 0;
      repeat (200) begin
        if (!base.randomize()) `uvm_error("RAND", "base randomize failed")
        if (base.op inside {OP_LW, OP_SW, OP_CSRRW}) forbidden++;
        if (base.imm != 12'h123) bad++;
      end
      `uvm_info("GEN", $sformatf("part3: n=200 forbidden_ops=%0d imm_changed=%0d", forbidden, bad), UVM_LOW)

      // Part 4: turn a LEGALITY constraint off on purpose to build a misaligned load
      a = cpu_instr_item::type_id::create("a");
      ok_on = a.randomize() with { op == OP_LW; imm == 12'h001; };   // c_align is on -> unsatisfiable (tool prints a solver message)
      a.c_align.constraint_mode(0);
      ok_off = a.randomize() with { op == OP_LW; imm == 12'h001; };
      `uvm_info("GEN", $sformatf("part4: misaligned LW randomize: c_align on=%0d, off=%0d (imm=0x%03h)", ok_on, ok_off, a.imm), UVM_LOW)

      // Part 5: same seed, same constraints -> same item
      a = cpu_instr_item::type_id::create("a2");
      b = cpu_instr_item::type_id::create("b2");
      a.srandom(32'd1234);
      b.srandom(32'd1234);
      void'(a.randomize());
      void'(b.randomize());
      `uvm_info("GEN", $sformatf("part5: same seed -> identical items: %0d", a.compare(b)), UVM_LOW)

      phase.drop_objection(this, "rand test done");
    endtask
  endclass
endpackage

module tb_top_rand;
  import uvm_pkg::*;
  import mcpu_rand_pkg::*;
  initial run_test("mcpu_rand_test");
endmodule

// Expected log (hand-derived, not simulated) -- properties that hold for every seed, all at time 0
// UVM-internal lines elided. Part 4 also makes the simulator print its own solver-failure message for the
// first randomize (wording tool-specific); that message is not a UVM message.
//
// UVM_INFO example01.sv(62) @ 0: uvm_test_top [GEN] part1: n=500 illegal_items=0
// UVM_INFO example01.sv(70) @ 0: uvm_test_top [GEN] part2: n=200 not_lw_sw_or_illegal=0
// UVM_INFO example01.sv(82) @ 0: uvm_test_top [GEN] part3: n=200 forbidden_ops=0 imm_changed=0
// UVM_INFO example01.sv(89) @ 0: uvm_test_top [GEN] part4: misaligned LW randomize: c_align on=0, off=1 (imm=0x001)
// UVM_INFO example01.sv(98) @ 0: uvm_test_top [GEN] part5: same seed -> identical items: 1
//
// Part 3 reasoning: imm is pinned to 0x123 (low two bits 11), so c_align makes LW/SW impossible and c_csr makes
// CSRRW impossible; only ADD, SUB, AND, OR, ADDI, BEQ remain. Part 4: with c_align on, (op==LW, imm==1) is
// unsatisfiable -> 0; with it off -> 1. The class mix itself (40/20/15/15/5/5) is a distribution, so it is
// reasoned in the lesson, not asserted here.

