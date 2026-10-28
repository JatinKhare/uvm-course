`ifndef MCPU_INC_M03_EX01
`define MCPU_INC_M03_EX01
// Module 03 / example01.sv -- cpu_instr_item, sequences, a stub driver, and a test
// Demonstrates : constrained-random item with RV32I-style encode(), do_copy/do_compare/convert2string,
//                directed sequence via randomize() with, random sequence, start_item/finish_item handshake
// Lesson use   : "Code Walkthrough" sections 1-4
// Tool note    : UVM 1.2. Compile this file alone. example02.sv `include`s it with MCPU_NO_TOP defined.
//
// mcpu_stub_driver is a THROWAWAY consumer so the sequences have something to talk to. Its handshake
// (get_next_item / item_done) is explained in Module 04, which replaces it with the real fetch driver.

`timescale 1ns/1ps

package mcpu_seq_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit [3:0] {OP_ADD, OP_SUB, OP_AND, OP_OR, OP_ADDI, OP_LW, OP_SW, OP_BEQ, OP_CSRRW} cpu_opcode_e;

  //------------------------------------------------------------------------
  // One instruction. uvm_sequence_item = a uvm_object that can travel through a sequencer.
  //------------------------------------------------------------------------
  class cpu_instr_item extends uvm_sequence_item;
    `uvm_object_utils(cpu_instr_item)                  // why: factory registration (object flavour)

    rand cpu_opcode_e op;
    rand bit [4:0]    rd, rs1, rs2;
    rand bit [11:0]   imm;       // I/S: offset; BEQ: offset bits [12:1]; CSRRW: CSR address

    // soft: a default preference that any harder constraint may override (x0 is allowed when asked for)
    constraint c_small_regs { soft rd inside {[1:7]}; soft rs1 inside {[1:7]}; soft rs2 inside {[1:7]}; }
    constraint c_unused_rd  { (op inside {OP_SW, OP_BEQ}) -> rd == 0; }          // these ops write no register
    constraint c_align      { (op inside {OP_LW, OP_SW}) -> imm[1:0] == 2'b00; } // word-aligned offset
    constraint c_csr        { (op == OP_CSRRW) -> imm inside {12'h300, 12'h305, 12'h341}; }

    function new(string name = "cpu_instr_item");     // why: objects take a name only
      super.new(name);
    endfunction

    function bit [31:0] encode();                       // RV32I-style 32-bit encoding
      case (op)
        OP_ADD:   return {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
        OP_SUB:   return {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
        OP_AND:   return {7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011};
        OP_OR:    return {7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011};
        OP_ADDI:  return {imm, rs1, 3'b000, rd, 7'b0010011};
        OP_LW:    return {imm, rs1, 3'b010, rd, 7'b0000011};
        OP_SW:    return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
        OP_BEQ:   return {imm[11], imm[9:4], rs2, rs1, 3'b000, imm[3:0], imm[10], 7'b1100011};
        OP_CSRRW: return {imm, rs1, 3'b001, rd, 7'b1110011};
        default:  return 32'h0000_0013;                 // NOP = ADDI x0,x0,0
      endcase
    endfunction

    virtual function string convert2string();           // why: one-line print used by logs
      return $sformatf("%s rd=x%0d rs1=x%0d rs2=x%0d imm=0x%03h", op.name(), rd, rs1, rs2, imm);
    endfunction

    virtual function void do_copy(uvm_object rhs);      // why: hook behind copy()
      cpu_instr_item rhs_;
      if (!$cast(rhs_, rhs)) `uvm_fatal("CAST", "do_copy: rhs is not a cpu_instr_item")
      super.do_copy(rhs);
      op = rhs_.op; rd = rhs_.rd; rs1 = rhs_.rs1; rs2 = rhs_.rs2; imm = rhs_.imm;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);   // why: hook behind compare()
      cpu_instr_item rhs_;
      if (!$cast(rhs_, rhs)) return 0;
      // compare the ENCODING: ignores fields the opcode does not use (e.g. rd of a SW)
      return super.do_compare(rhs, comparer) && (encode() == rhs_.encode());
    endfunction
  endclass

  typedef uvm_sequencer#(cpu_instr_item) mcpu_ifetch_seqr;

  //------------------------------------------------------------------------
  // Sequences (uvm_object: no parent, started on a sequencer)
  //------------------------------------------------------------------------
  class mcpu_instr_seq_base extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_instr_seq_base)
    function new(string name = "mcpu_instr_seq_base");
      super.new(name);
    endfunction

    // Send exactly one fully specified instruction through the sequencer handshake.
    task send_instr(cpu_opcode_e o, bit [4:0] d, s1, s2, bit [11:0] i);
      cpu_instr_item it;
      it = cpu_instr_item::type_id::create("it");       // why: fresh object per instruction
      start_item(it);                                   // why: wait for the sequencer to grant this sequence
      if (!it.randomize() with { op == o; rd == d; rs1 == s1; rs2 == s2; imm == i; })
        `uvm_error("RAND", "randomize failed for directed instruction")
      finish_item(it);                                  // why: hand the item to the driver; blocks until item_done
    endtask
  endclass

  class mcpu_directed_seq extends mcpu_instr_seq_base;
    `uvm_object_utils(mcpu_directed_seq)
    function new(string name = "mcpu_directed_seq");
      super.new(name);
    endfunction
    task body();                                        // why: the sequence's entry point, called by start()
      send_instr(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd5);     // ADDI x1,x0,5
      send_instr(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd7);     // ADDI x2,x0,7
      send_instr(OP_ADD,  5'd3, 5'd1, 5'd2, 12'd0);     // ADD  x3,x1,x2
      send_instr(OP_SW,   5'd0, 5'd4, 5'd3, 12'd0);     // SW   x3,0(x4)
    endtask
  endclass

  class mcpu_rand_seq extends uvm_sequence#(cpu_instr_item);
    `uvm_object_utils(mcpu_rand_seq)
    rand int unsigned n_instr;
    constraint c_n { n_instr inside {[1:20]}; }
    function new(string name = "mcpu_rand_seq");
      super.new(name);
    endfunction
    task body();
      cpu_instr_item it;
      repeat (n_instr) begin
        it = cpu_instr_item::type_id::create("it");
        start_item(it);
        if (!it.randomize()) `uvm_error("RAND", "randomize failed")
        finish_item(it);
      end
    endtask
  endclass

  //------------------------------------------------------------------------
  // Throwaway driver + test (real driver: Module 04)
  //------------------------------------------------------------------------
  class mcpu_stub_driver extends uvm_driver#(cpu_instr_item);
    `uvm_component_utils(mcpu_stub_driver)
    function new(string name = "mcpu_stub_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);               // why: pull the next item from the sequencer
        `uvm_info("DRV", {"got ", req.convert2string(), $sformatf(" enc=0x%08h", req.encode())}, UVM_LOW)
        #10ns;                                          // stands in for driving the bus
        seq_item_port.item_done();                      // why: releases the sequence's finish_item
      end
    endtask
  endclass

  class mcpu_seq_test extends uvm_test;
    `uvm_component_utils(mcpu_seq_test)
    mcpu_ifetch_seqr seqr;
    mcpu_stub_driver drv;

    function new(string name = "mcpu_seq_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = mcpu_ifetch_seqr::type_id::create("seqr", this);
      drv  = mcpu_stub_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);  // why: driver pulls from this sequencer
    endfunction

    task run_phase(uvm_phase phase);
      mcpu_directed_seq dseq;
      mcpu_rand_seq     rseq;
      phase.raise_objection(this, "seq test");
      dseq = mcpu_directed_seq::type_id::create("dseq");
      dseq.start(seqr);                                 // why: blocks until body() returns
      rseq = mcpu_rand_seq::type_id::create("rseq");
      if (!rseq.randomize() with { n_instr == 2; }) `uvm_error("RAND", "rseq randomize failed")
      rseq.start(seqr);
      phase.drop_objection(this, "seq test done");
    endtask
  endclass
endpackage

`ifndef MCPU_NO_TOP
module tb_top_seq;
  import uvm_pkg::*;
  import mcpu_seq_pkg::*;
  initial run_test("mcpu_seq_test");
endmodule
`endif

// Expected log (hand-derived, not simulated)
// UVM-internal lines elided. Driver holds each item 10 ns before item_done, so items are 10 ns apart.
//
// UVM_INFO example01.sv(138) @ 0:  uvm_test_top.drv [DRV] got OP_ADDI rd=x1 rs1=x0 rs2=x0 imm=0x005 enc=0x00500093
// UVM_INFO example01.sv(138) @ 10: uvm_test_top.drv [DRV] got OP_ADDI rd=x2 rs1=x0 rs2=x0 imm=0x007 enc=0x00700113
// UVM_INFO example01.sv(138) @ 20: uvm_test_top.drv [DRV] got OP_ADD rd=x3 rs1=x1 rs2=x2 imm=0x000 enc=0x002081b3
// UVM_INFO example01.sv(138) @ 30: uvm_test_top.drv [DRV] got OP_SW rd=x0 rs1=x4 rs2=x3 imm=0x000 enc=0x00322023
// UVM_INFO example01.sv(138) @ 40: uvm_test_top.drv [DRV] got <random item #1>      <- values depend on the seed
// UVM_INFO example01.sv(138) @ 50: uvm_test_top.drv [DRV] got <random item #2>
//
// dseq.start() returns at 40 (4th item_done); rseq.start() returns at 60 (2nd random item_done);
// the objection drops at 60 and the run phase ends. Properties that hold for ANY seed in the random lines:
// rd/rs1/rs2 are x1..x7 except where an opcode forces rd=x0 (SW, BEQ); LW/SW offsets have imm[1:0]==0;
// CSRRW immediates are one of 0x300, 0x305, 0x341.
//
// Encoding check (ADD x3,x1,x2): funct7=0000000 rs2=00010 rs1=00001 funct3=000 rd=00011 opcode=0110011
//   -> 0000 0000 0010 0000 1000 0001 1011 0011 = 0x002081b3.


`endif
