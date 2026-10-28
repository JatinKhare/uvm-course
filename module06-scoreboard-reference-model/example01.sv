`ifndef MCPU_INC_M06_EX01
`define MCPU_INC_M06_EX01
// Module 06 / example01.sv -- retire transaction, reference model (ISS) and the in-order scoreboard
// Demonstrates : do_compare with 4-state-safe === ; a software ISS used as predictor; a two-input
//                scoreboard (uvm_analysis_imp_decl) with expected/actual queues; end-of-test checks
// Lesson use   : "Code Walkthrough" sections 1-4
// Tool note    : UVM 1.2. This file is a PACKAGE; compile through example02.sv (it includes this file).
//                Includes below pull in Module 01 (interface), 03 (sequences) and 04 (mcpu_bus_txn).
//                Run from this directory; include-path resolution is SIMULATOR-DEPENDENT.
//
// ISS scope: ADD, SUB, AND, OR, ADDI, LW, SW, BEQ, CSRRW as encoded by cpu_instr_item.encode().
// Anything else retires as "no register write". Memory and CSRs are sparse arrays.

`define MCPU_NO_TOP
`include "../module01-big-picture/example01.sv"
`include "../module03-transactions-sequences/example01.sv"
`include "../module04-driver-sequencer-monitor-agent/example01.sv"

`timescale 1ns/1ps

package mcpu_sb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_ifetch_pkg::*;                       // mcpu_bus_txn (what the fetch monitor publishes)

  // One retired instruction. 4-state fields so an X from the DUT is visible to the compare.
  class mcpu_retire_txn extends uvm_sequence_item;
    `uvm_object_utils(mcpu_retire_txn)
    logic [31:0] pc, instr, data;
    logic [4:0]  rd;                               // 0 = no register written

    function new(string name = "mcpu_retire_txn");
      super.new(name);
    endfunction

    virtual function string convert2string();
      return $sformatf("pc=0x%08h instr=0x%08h rd=x%0d data=0x%08h", pc, instr, rd, data);
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      mcpu_retire_txn r;
      if (!$cast(r, rhs)) return 0;
      // why ===: with == an X in DUT data makes the result X; consumers like `if (a != b) error` then see "false" (silent pass)
      return super.do_compare(rhs, comparer) &&
             (pc === r.pc) && (instr === r.instr) && (rd === r.rd) && (data === r.data);
    endfunction
  endclass

  // Reference model: executes one instruction word at a time, returns the expected retirement.
  class mcpu_iss;
    bit [31:0] regs [32];
    bit [31:0] mem  [bit [31:0]];
    bit [31:0] csr  [bit [11:0]];
    bit [31:0] pc;

    function new();
      foreach (regs[i]) regs[i] = '0;
      pc = '0;
    endfunction

    function mcpu_retire_txn step(bit [31:0] instr);
      mcpu_retire_txn r;
      bit [6:0]  opc, f7;
      bit [4:0]  rd, rs1, rs2;
      bit [2:0]  f3;
      bit [31:0] imm_i, imm_s, imm_b, addr, next_pc, wdata;
      bit        we;
      r   = mcpu_retire_txn::type_id::create("exp");     // why: a NEW object per instruction (queues keep handles)
      opc = instr[6:0];   rd = instr[11:7];  f3 = instr[14:12];
      rs1 = instr[19:15]; rs2 = instr[24:20]; f7 = instr[31:25];
      imm_i = {{20{instr[31]}}, instr[31:20]};
      imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      next_pc = pc + 32'd4;  wdata = '0;  we = 1'b0;  addr = '0;
      case (opc)
        7'b0110011: begin                                  // R-type
          we = 1'b1;
          case ({f7, f3})
            {7'b0000000, 3'b000}: wdata = regs[rs1] + regs[rs2];
            {7'b0100000, 3'b000}: wdata = regs[rs1] - regs[rs2];
            {7'b0000000, 3'b111}: wdata = regs[rs1] & regs[rs2];
            {7'b0000000, 3'b110}: wdata = regs[rs1] | regs[rs2];
            default:              we = 1'b0;
          endcase
        end
        7'b0010011: begin we = 1'b1; wdata = regs[rs1] + imm_i; end                    // ADDI
        7'b0000011: begin addr = regs[rs1] + imm_i; we = 1'b1;                         // LW
                          wdata = mem.exists(addr) ? mem[addr] : 32'h0; end
        7'b0100011: begin addr = regs[rs1] + imm_s; mem[addr] = regs[rs2]; end         // SW
        7'b1100011: if (regs[rs1] == regs[rs2]) next_pc = pc + imm_b;                  // BEQ
        7'b1110011: begin we = 1'b1;                                                   // CSRRW
                          wdata = csr.exists(instr[31:20]) ? csr[instr[31:20]] : 32'h0;
                          csr[instr[31:20]] = regs[rs1]; end
        default: ;
      endcase
      r.pc    = pc;
      r.instr = instr;
      r.rd    = (we && rd != 0) ? rd    : 5'd0;
      r.data  = (we && rd != 0) ? wdata : 32'd0;
      if (we && rd != 0) regs[rd] = wdata;
      pc = next_pc;
      return r;
    endfunction
  endclass

  `uvm_analysis_imp_decl(_fetch)                       // why: two inputs in one class -> write_fetch / write_retire
  `uvm_analysis_imp_decl(_retire)

  class mcpu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mcpu_scoreboard)
    uvm_analysis_imp_fetch #(mcpu_bus_txn,    mcpu_scoreboard) fetch_imp;
    uvm_analysis_imp_retire#(mcpu_retire_txn, mcpu_scoreboard) retire_imp;
    mcpu_iss        iss;
    mcpu_retire_txn exp_q[$], act_q[$];
    int unsigned    n_fetch, n_cmp, n_bad;

    function new(string name = "mcpu_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      fetch_imp  = new("fetch_imp", this);
      retire_imp = new("retire_imp", this);
      iss        = new();
    endfunction

    function void write_fetch(mcpu_bus_txn t);         // predictor: every fetched word becomes an expected retirement
      mcpu_retire_txn e;
      n_fetch++;
      if (t.addr !== iss.pc)
        `uvm_error("PC_MISMATCH", $sformatf("fetch #%0d: DUT fetched 0x%08h, ISS expects pc 0x%08h", n_fetch, t.addr, iss.pc))
      e = iss.step(t.data);
      exp_q.push_back(e);
      try_compare();
    endfunction

    function void write_retire(mcpu_retire_txn t);     // actual: queue, then compare if possible
      act_q.push_back(t);
      try_compare();
    endfunction

    // Both streams buffer, so it does not matter which write_* runs first in a time step.
    function void try_compare();
      mcpu_retire_txn e, a;
      while (exp_q.size() > 0 && act_q.size() > 0) begin
        e = exp_q.pop_front();                         // why: pop BOTH, also on mismatch, or the streams slip
        a = act_q.pop_front();
        n_cmp++;
        if (!e.compare(a)) begin
          n_bad++;
          `uvm_error("RETIRE_MISMATCH", $sformatf("retire #%0d exp: %s | act: %s", n_cmp, e.convert2string(), a.convert2string()))
        end
      end
    endfunction

    function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (n_cmp == 0)
        `uvm_error("SB_EMPTY", "no retirements were compared: nothing was checked")
      if (act_q.size() > 0)
        `uvm_error("SB_LEFTOVER", $sformatf("%0d retirements had no expected entry", act_q.size()))
      if (exp_q.size() > 0)
        `uvm_warning("SB_INFLIGHT", $sformatf("%0d fetched instructions never retired (in flight at end of test?)", exp_q.size()))
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SB", $sformatf("fetched=%0d compared=%0d mismatched=%0d", n_fetch, n_cmp, n_bad), UVM_LOW)
    endfunction
  endclass
endpackage

// Expected log: this file defines the package only. The hand-derived log of a run is at the end of example02.sv.
// ISS hand-check (ADD x3,x1,x2 after ADDI x1,x0,5 and ADDI x2,x0,7): regs[1]=5, regs[2]=7 -> wdata=12,
// retire = pc 8, rd x3, data 0x0000000c.


`endif
