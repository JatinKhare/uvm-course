// Module 10 / example01.sv -- the DUT side of the integrated bench: an executing core and a reset-control interface
// Demonstrates : mini_cpu_core (resolves the Module 06 gap: it EXECUTES instructions and retires real rd/data),
//                a built-in, plusarg-selectable bug for negative testing, mcpu_rst_ctl_if
// Lesson use   : "Code Walkthrough" section 1
// Tool note    : SystemVerilog (no UVM here). This file is included by example02.sv; it includes Module 01's example01.sv
//                for mini_cpu_if. Run from this directory; include-path resolution is SIMULATOR-DEPENDENT.
//
// mini_cpu_core: single-issue, one instruction in flight. It raises if_req, waits for the one-cycle if_rvalid pulse that
// the fetch agent drives (Module 04 protocol), executes the word at the edge where it samples if_rvalid, and presents ONE
// retire_* record the next cycle. Data memory is internal (256 words); ls_* pins are an OBSERVATION pulse only (no response
// needed): the Module 04 Exercise 01 handshake remains the design target for a core with an external data memory.
// Not modelled: traps, interrupts (irq is ignored), CSR privilege rules, an error-response signal.

`define MCPU_NO_TOP
`include "../module01-big-picture/example01.sv"

`ifndef MCPU_INC_M10_EX01
`define MCPU_INC_M10_EX01

`timescale 1ns/1ps

interface mcpu_rst_ctl_if;
  bit req;                                          // a test sets req = 1; tb_top pulses reset and clears it
endinterface

module mini_cpu_core (mini_cpu_if.dut bus);
  logic [31:0] pc;
  logic [31:0] regs [32];
  logic [31:0] dmem [256];
  logic [31:0] csrf [4096];
  logic        bug_add;

  initial bug_add = $test$plusargs("MCPU_BUG_ADD");   // +MCPU_BUG_ADD: ADD returns a+b+1 (a mutation for negative tests)

  assign bus.if_addr = pc;

  always_ff @(posedge bus.clk) begin
    logic [31:0] i, imm_i, imm_s, imm_b, a, b, res, npc, ea;
    logic [4:0]  rd, rs1, rs2;
    logic        we;
    bus.retire_valid <= 1'b0;
    bus.ls_req       <= 1'b0;
    bus.ls_we        <= 1'b0;
    if (!bus.rst_n) begin
      pc <= '0;
      bus.if_req <= 1'b0;
      bus.ls_addr <= '0;  bus.ls_wdata <= '0;
      bus.retire_pc <= '0;  bus.retire_instr <= '0;  bus.retire_rd <= '0;  bus.retire_data <= '0;
      foreach (regs[k]) regs[k] <= '0;
      foreach (dmem[k]) dmem[k] <= '0;
      foreach (csrf[k]) csrf[k] <= '0;
    end else if (!bus.if_req) begin
      bus.if_req <= 1'b1;                           // (re)raise the fetch request
    end else if (bus.if_rvalid) begin               // response sampled: execute this instruction now
      bus.if_req <= 1'b0;
      i   = bus.if_rdata;
      rd  = i[11:7];  rs1 = i[19:15];  rs2 = i[24:20];
      imm_i = {{20{i[31]}}, i[31:20]};
      imm_s = {{20{i[31]}}, i[31:25], i[11:7]};
      imm_b = {{19{i[31]}}, i[31], i[7], i[30:25], i[11:8], 1'b0};
      a = regs[rs1];  b = regs[rs2];  res = '0;  we = 1'b0;  npc = pc + 32'd4;  ea = '0;
      case (i[6:0])
        7'b0110011: begin
          we = 1'b1;
          case ({i[31:25], i[14:12]})
            {7'b0000000, 3'b000}: res = a + b + (bug_add ? 32'd1 : 32'd0);
            {7'b0100000, 3'b000}: res = a - b;
            {7'b0000000, 3'b111}: res = a & b;
            {7'b0000000, 3'b110}: res = a | b;
            default:              we = 1'b0;
          endcase
        end
        7'b0010011: begin we = 1'b1; res = a + imm_i; end
        7'b0000011: begin ea = a + imm_i; we = 1'b1; res = dmem[ea[9:2]];
                          bus.ls_req <= 1'b1; bus.ls_we <= 1'b0; bus.ls_addr <= ea; end
        7'b0100011: begin ea = a + imm_s; dmem[ea[9:2]] <= b;
                          bus.ls_req <= 1'b1; bus.ls_we <= 1'b1; bus.ls_addr <= ea; bus.ls_wdata <= b; end
        7'b1100011: if (a == b) npc = pc + imm_b;
        7'b1110011: begin we = 1'b1; res = csrf[i[31:20]]; csrf[i[31:20]] <= a; end
        default: ;
      endcase
      if (we && rd != 5'd0) regs[rd] <= res;
      bus.retire_pc    <= pc;
      bus.retire_instr <= i;
      bus.retire_rd    <= (we && rd != 5'd0) ? rd  : 5'd0;
      bus.retire_data  <= (we && rd != 5'd0) ? res : 32'd0;
      bus.retire_valid <= 1'b1;
      pc <= npc;
    end
  end
endmodule

// Expected behaviour (hand-derived, not simulated). Clock posedges at 5, 15, ...; reset released at 42; the fetch agent
// of Module 04 serves instructions (it drives if_rvalid one edge after it SEES if_req).
//   edge 45 : core sets if_req <= 1                          edge 55 : agent samples if_req = 1, drives if_rvalid/if_rdata
//   edge 65 : core samples if_rvalid = 1 -> executes instruction #1 (pc 0); if_req <= 0; retire_valid <= 1; pc <= 4
//   edge 75 : retire record visible to a monitor that samples at this edge; core sets if_req <= 1
//   edge 85 : agent sees if_req = 1 and drives the next word  ...  edge 95: core executes instruction #2
// => executions at 65, 95, 125, 155, 185 (one per 30 ns); retire records sampled at 75, 105, 135, 165, 195.
// For the Module 06 program (ADDI x1,5; ADDI x2,7; ADD x3,x1,x2; SW x3,0(x4); LW x5,0(x4)) the retire records are
// (pc 0, rd 1, 5) (4, rd 2, 7) (8, rd 3, 12) (12, rd 0, 0) (16, rd 5, 12). With +MCPU_BUG_ADD the third is data 13 and,
// because x3 = 13 is stored and loaded back, the fifth is also data 13.
`endif
