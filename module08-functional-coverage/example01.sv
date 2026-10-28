// Module 08 / example01.sv -- instruction coverage: class x RAW-hazard distance, sampled from the retire stream
// Demonstrates : embedded covergroup in a uvm_subscriber, coverpoints with explicit bins, ignore_bins, a cross,
//                option.per_instance, sampling once per observed instruction, hand-derived coverage numbers
// Lesson use   : "Code Walkthrough" sections 1-3
// Tool note    : UVM 1.2 + SystemVerilog covergroups. Compile this file; it includes Module 06's example01.sv
//                (which includes Modules 01/03/04). Run from this directory; include-path resolution is
//                SIMULATOR-DEPENDENT. Coverage percentages are computed with the LRM formula (see the end).

`define MCPU_NO_TOP
`include "../module06-scoreboard-reference-model/example01.sv"

`ifndef MCPU_INC_M08_EX01
`define MCPU_INC_M08_EX01

`timescale 1ns/1ps

package mcpu_cov_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import mcpu_seq_pkg::*;                           // cpu_instr_item, cpu_opcode_e
  import mcpu_sb_pkg::*;                            // mcpu_retire_txn

  typedef enum {C_R, C_ADDI, C_LW, C_SW, C_BEQ, C_CSR, C_OTHER} mcpu_cls_e;
  typedef enum {D_NONE, D1, D2, D3}                              mcpu_dist_e;   // value = RAW distance, 0 = none

  // Build an instruction word without randomisation (used by tests to drive known programs)
  function automatic bit [31:0] mcpu_mk_word(cpu_opcode_e o, bit [4:0] d, s1, s2, bit [11:0] i);
    cpu_instr_item it;
    it = cpu_instr_item::type_id::create("it");
    it.op = o;  it.rd = d;  it.rs1 = s1;  it.rs2 = s2;  it.imm = i;
    return it.encode();
  endfunction

  class mcpu_instr_cov extends uvm_subscriber#(mcpu_retire_txn);
    `uvm_component_utils(mcpu_instr_cov)

    mcpu_cls_e  cls;                                // sampled values, set in write() BEFORE cg.sample()
    mcpu_dist_e dist;
    bit [4:0]   hist [3];                           // destination registers of the last three instructions, newest first

    covergroup cg;
      option.per_instance = 1;                      // why: so get_inst_coverage() reports THIS instance
      cp_class: coverpoint cls {
        bins r    = {C_R};
        bins addi = {C_ADDI};
        bins lw   = {C_LW};
        bins sw   = {C_SW};
        bins beq  = {C_BEQ};
        bins csr  = {C_CSR};
        ignore_bins other = {C_OTHER};              // why: opcodes the model does not cover are not holes
      }
      cp_dist: coverpoint dist {
        bins none = {D_NONE};
        bins d1   = {D1};
        bins d2   = {D2};
        bins d3   = {D3};
      }
      x_class_dist: cross cp_class, cp_dist;        // 6 x 4 = 24 bins
    endgroup

    function new(string name = "mcpu_instr_cov", uvm_component parent = null);
      super.new(name, parent);
      cg = new();                                   // why: an embedded covergroup MUST be constructed in new()
    endfunction

    function void reset_history();
      foreach (hist[i]) hist[i] = '0;
    endfunction

    function void write(mcpu_retire_txn t);         // why: uvm_subscriber's analysis callback = one sample per retirement
      bit [31:0] w;
      bit [4:0]  rs1, rs2, rd;
      bit        uses1, uses2, writes;
      int        best;
      w = t.instr;  rs1 = w[19:15];  rs2 = w[24:20];  rd = w[11:7];
      uses1 = 1'b0;  uses2 = 1'b0;  writes = 1'b0;
      case (w[6:0])
        7'b0110011: begin cls = C_R;    uses1 = 1; uses2 = 1; writes = 1; end
        7'b0010011: begin cls = C_ADDI; uses1 = 1;            writes = 1; end
        7'b0000011: begin cls = C_LW;   uses1 = 1;            writes = 1; end
        7'b0100011: begin cls = C_SW;   uses1 = 1; uses2 = 1;             end
        7'b1100011: begin cls = C_BEQ;  uses1 = 1; uses2 = 1;             end
        7'b1110011: begin cls = C_CSR;  uses1 = 1;            writes = 1; end
        default:    cls = C_OTHER;
      endcase
      best = 0;                                     // nearest producer of a source register within 3 instructions
      for (int d = 1; d <= 3; d++)
        if (best == 0 && ((uses1 && rs1 != 0 && hist[d-1] == rs1) || (uses2 && rs2 != 0 && hist[d-1] == rs2)))
          best = d;
      dist = mcpu_dist_e'(best);
      cg.sample();                                  // why: ONE sample per instruction, after the fields are set
      hist[2] = hist[1];  hist[1] = hist[0];  hist[0] = (writes && rd != 0) ? rd : 5'd0;
    endfunction

    function string cov_line();
      return $sformatf("class=%0.1f dist=%0.1f cross=%0.1f total=%0.1f",
                       cg.cp_class.get_inst_coverage(), cg.cp_dist.get_inst_coverage(),
                       cg.x_class_dist.get_inst_coverage(), cg.get_inst_coverage());
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("COV", cov_line(), UVM_LOW)
    endfunction
  endclass

  class mcpu_cov_env extends uvm_env;
    `uvm_component_utils(mcpu_cov_env)
    mcpu_instr_cov cov;
    function new(string name = "mcpu_cov_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cov = mcpu_instr_cov::type_id::create("cov", this);
    endfunction
  endclass

  class mcpu_cov_test extends uvm_test;
    `uvm_component_utils(mcpu_cov_test)
    mcpu_cov_env env;
    function new(string name = "mcpu_cov_test", uvm_component parent = null);
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
      env.cov.write(t);                             // stands in for the retire monitor's ap.write
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "cov test");
      env.cov.reset_history();
      feed(mcpu_mk_word(OP_ADDI, 5'd1, 5'd0, 5'd0, 12'd5));    // ADDI x1,x0,5
      feed(mcpu_mk_word(OP_ADDI, 5'd2, 5'd0, 5'd0, 12'd7));    // ADDI x2,x0,7
      feed(mcpu_mk_word(OP_ADD,  5'd3, 5'd1, 5'd2, 12'd0));    // ADD  x3,x1,x2
      feed(mcpu_mk_word(OP_SW,   5'd0, 5'd4, 5'd3, 12'd0));    // SW   x3,0(x4)
      feed(mcpu_mk_word(OP_LW,   5'd5, 5'd4, 5'd0, 12'd0));    // LW   x5,0(x4)
      phase.drop_objection(this, "cov test done");
    endtask
  endclass
endpackage

`ifndef MCPU_SKIP_LEAF_TOPS
module tb_top_cov;
  import uvm_pkg::*;
  import mcpu_cov_pkg::*;
  initial run_test("mcpu_cov_test");
endmodule
`endif

// Expected log (hand-derived, not simulated); all at time 0, UVM-internal lines elided
//
// UVM_INFO example01.sv(103) @ 0: uvm_test_top.env.cov [COV] class=66.7 dist=50.0 cross=16.7 total=44.4
//
// Derivation. Rate per sample (class, nearest-producer distance), history reset before the first instruction:
//   ADDI x1,x0,5 -> (ADDI, none)   ADDI x2,x0,7 -> (ADDI, none)   ADD x3,x1,x2 -> (R, d1)  [x2 is 1 back, x1 is 2 back]
//   SW x3,0(x4)  -> (SW, d1)       LW x5,0(x4)   -> (LW, none)    [x4 never written; the SW wrote no register]
// cp_class: bins hit = addi, r, sw, lw = 4 of 6            -> 66.7%   (beq and csr are holes; `other` is ignored)
// cp_dist : bins hit = none, d1 = 2 of 4                    -> 50.0%
// cross   : bins hit = (addi,none) (r,d1) (sw,d1) (lw,none) = 4 of 6 x 4 = 24 -> 16.7%
// covergroup (LRM: weighted average, default weights 1): (66.67 + 50 + 16.67) / 3 = 44.4%
// Rounding of the last digit is the simulator's printf; the structure (4/6, 2/4, 4/24) is what matters.
`endif
