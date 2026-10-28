// Module 07 / example02.sv -- layered sequences: an instruction-stream generator with checkable structure
// Demonstrates : scenario -> burst -> item layering, child sequences via start(m_sequencer, this),
//                inline constraints referencing sequence knobs (local:: where names clash),
//                forward-only branches, a recording driver, seed-controlled reproducibility
// Lesson use   : "Code Walkthrough" sections 4-5
// Tool note    : UVM 1.2. Compile this file; it includes Module 03's example01.sv (MCPU_NO_TOP defined).
//                Run from this directory; include-path resolution is SIMULATOR-DEPENDENT.
//
// As in example01, random values are not traceable; the test checks STRUCTURE (pinned by n_alu == 4).

`define MCPU_NO_TOP
`include "../module03-transactions-sequences/example01.sv"

`timescale 1ns/1ps

package mcpu_stream_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;

  // Layer 1: a burst of ALU instructions; with `hazard`, each reads the register the previous one wrote
  class mcpu_alu_burst_seq extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_alu_burst_seq)
    rand int unsigned n;
    rand bit          hazard;
    constraint c_n { n inside {[1:6]}; }
    function new(string name = "mcpu_alu_burst_seq");
      super.new(name);
    endfunction
    task body();
      cpu_instr_item it;
      bit [4:0]      prev_rd;
      for (int idx = 0; idx < n; idx++) begin
        it = cpu_instr_item::type_id::create("it");
        start_item(it);
        // idx / prev_rd / hazard are not item fields, so they resolve to this sequence's scope
        if (!it.randomize() with { op inside {OP_ADD, OP_SUB, OP_AND, OP_OR}; rd != 0;
                                   if (idx > 0 && hazard) { rs1 == prev_rd; } })
          `uvm_error("RAND", "alu burst randomize failed")
        finish_item(it);
        prev_rd = it.rd;
      end
    endtask
  endclass

  // Layer 1: SW then LW to the same address (same base register and offset)
  class mcpu_sw_lw_burst_seq extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_sw_lw_burst_seq)
    rand bit [4:0]  base_reg;
    rand bit [11:0] off;
    constraint c_b { base_reg inside {[1:7]}; off[1:0] == 2'b00; }
    function new(string name = "mcpu_sw_lw_burst_seq");
      super.new(name);
    endfunction
    task body();
      cpu_instr_item st, ld;
      st = cpu_instr_item::type_id::create("st");
      start_item(st);
      if (!st.randomize() with { op == OP_SW; rs1 == base_reg; imm == off; }) `uvm_error("RAND", "sw randomize failed")
      finish_item(st);
      ld = cpu_instr_item::type_id::create("ld");
      start_item(ld);
      if (!ld.randomize() with { op == OP_LW; rs1 == base_reg; imm == off; }) `uvm_error("RAND", "lw randomize failed")
      finish_item(ld);
    endtask
  endclass

  // Layer 1: one FORWARD branch (offset bits [12:1] in 2..16 => 4..32 bytes ahead): a generated program must terminate
  class mcpu_branch_seq extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_branch_seq)
    function new(string name = "mcpu_branch_seq");
      super.new(name);
    endfunction
    task body();
      cpu_instr_item br;
      br = cpu_instr_item::type_id::create("br");
      start_item(br);
      if (!br.randomize() with { op == OP_BEQ; imm inside {[12'd2:12'd16]}; }) `uvm_error("RAND", "beq randomize failed")
      finish_item(br);
    endtask
  endclass

  // Layer 2: the scenario. Knobs are rand, so a test can pin them with an inline constraint.
  class mcpu_stream_seq extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_stream_seq)
    rand int unsigned n_alu;
    rand bit          hazard;
    constraint c_n { n_alu inside {[1:6]}; }
    function new(string name = "mcpu_stream_seq");
      super.new(name);
    endfunction
    task body();
      mcpu_alu_burst_seq    alu;
      mcpu_sw_lw_burst_seq  mem;
      mcpu_branch_seq       br;
      alu = mcpu_alu_burst_seq::type_id::create("alu");
      // why local::: alu has its own field named hazard; local::hazard is THIS sequence's knob
      if (!alu.randomize() with { n == local::n_alu; hazard == local::hazard; }) `uvm_error("RAND", "alu seq randomize failed")
      alu.start(m_sequencer, this);                     // why: child sequence on the same sequencer, parent = this
      mem = mcpu_sw_lw_burst_seq::type_id::create("mem");
      if (!mem.randomize()) `uvm_error("RAND", "mem seq randomize failed")
      mem.start(m_sequencer, this);
      br = mcpu_branch_seq::type_id::create("br");
      br.start(m_sequencer, this);
    endtask
  endclass

  // Throwaway driver that records what it was given (items are new objects, so keeping handles is safe)
  class mcpu_rec_driver extends uvm_driver#(cpu_instr_item);
    `uvm_component_utils(mcpu_rec_driver)
    cpu_instr_item seen[$];
    function new(string name = "mcpu_rec_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        seen.push_back(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class mcpu_stream_test extends uvm_test;
    `uvm_component_utils(mcpu_stream_test)
    mcpu_ifetch_seqr seqr;
    mcpu_rec_driver  drv;
    function new(string name = "mcpu_stream_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = mcpu_ifetch_seqr::type_id::create("seqr", this);
      drv  = mcpu_rec_driver::type_id::create("drv", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_stream_seq seq, sa, sb;
      bit alu_ok, chain_ok, mem_ok, br_ok;
      phase.raise_objection(this, "stream test");
      seq = mcpu_stream_seq::type_id::create("seq");
      if (!seq.randomize() with { n_alu == 4; hazard == 1; }) `uvm_error("RAND", "stream seq randomize failed")
      seq.start(seqr);

      alu_ok = 1;  chain_ok = 1;
      for (int i = 0; i < 4; i++) begin
        if (!(drv.seen[i].op inside {OP_ADD, OP_SUB, OP_AND, OP_OR}) || drv.seen[i].rd == 0) alu_ok = 0;
        if (i > 0 && drv.seen[i].rs1 != drv.seen[i-1].rd) chain_ok = 0;
      end
      mem_ok = (drv.seen[4].op == OP_SW) && (drv.seen[5].op == OP_LW) &&
               (drv.seen[4].rs1 == drv.seen[5].rs1) && (drv.seen[4].imm == drv.seen[5].imm);
      br_ok  = (drv.seen[6].op == OP_BEQ) && (drv.seen[6].imm inside {[12'd2:12'd16]});
      `uvm_info("CHK", $sformatf("stream length=%0d alu_ok=%0d hazard_chain_ok=%0d swlw_same_addr=%0d branch_last_forward=%0d",
                drv.seen.size(), alu_ok, chain_ok, mem_ok, br_ok), UVM_LOW)

      // reproducibility: two scenario objects with the same seed make the same choices
      sa = mcpu_stream_seq::type_id::create("sa");
      sb = mcpu_stream_seq::type_id::create("sb");
      sa.srandom(32'd42);
      sb.srandom(32'd42);
      void'(sa.randomize());
      void'(sb.randomize());
      `uvm_info("SEED", $sformatf("same seed 42: n_alu equal=%0d hazard equal=%0d", sa.n_alu == sb.n_alu, sa.hazard == sb.hazard), UVM_LOW)
      phase.drop_objection(this, "stream test done");
    endtask
  endclass
endpackage

module tb_top_stream;
  import uvm_pkg::*;
  import mcpu_stream_pkg::*;
  initial run_test("mcpu_stream_test");
endmodule

// Expected log (hand-derived, not simulated) -- structure, valid for every seed; all at time 0
// n_alu is pinned to 4 and hazard to 1, so the stream is 4 ALU ops + SW + LW + BEQ = 7 items:
//   items 0-3: ALU ops with rd != 0 and rs1(i) == rd(i-1) for i = 1..3 (hazard chain)
//   item 4: SW, item 5: LW (same base register and offset), item 6: forward BEQ (imm in 2..16)
//
// UVM_INFO example02.sv(157) @ 0: uvm_test_top [CHK] stream length=7 alu_ok=1 hazard_chain_ok=1 swlw_same_addr=1 branch_last_forward=1
// UVM_INFO example02.sv(167) @ 0: uvm_test_top [SEED] same seed 42: n_alu equal=1 hazard equal=1
//
// No simulation time passes: the recording driver completes every item in the same time step.

