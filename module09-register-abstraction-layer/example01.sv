// Module 09 / example01.sv -- the CSR register model and its bus-free API (desired vs mirrored, predict, reset)
// Demonstrates : uvm_reg_field/uvm_reg/uvm_reg_block/uvm_reg_map construction, access policies (RW, RO),
//                reset values, field set/get, predict(DIRECT vs WRITE), block reset, register addresses
// Lesson use   : "Code Walkthrough" sections 1-3
// Tool note    : UVM 1.2. Compile this file alone (own top; no DUT, no bus). example02.sv includes it.
//
// CSR set (fictional, RISC-V-flavoured numbers):
//   mstatus 0x300  MIE[3] RW, MPIE[7] RW            reset 0
//   mtvec   0x305  BASE[31:2] RW (reset 0x40), MODE[1:0] RW      -> reset value 0x100
//   mepc    0x341  EPC[31:1] RW, ZERO[0] RO          reset 0
//   mcause  0x342  CODE[31:0] RO, volatile (hardware sets it)    reset 0

`ifndef MCPU_INC_M09_EX01
`define MCPU_INC_M09_EX01

`timescale 1ns/1ps

package mcpu_ral_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  function automatic string mcpu_fmt32(uvm_reg_data_t v);
    return $sformatf("0x%08h", v[31:0]);
  endfunction

  class mcpu_mstatus_reg extends uvm_reg;
    `uvm_object_utils(mcpu_mstatus_reg)
    rand uvm_reg_field mie, mpie;
    function new(string name = "mstatus");
      super.new(name, 32, UVM_NO_COVERAGE);             // why: 32-bit register, no built-in coverage
    endfunction
    virtual function void build();
      mie  = uvm_reg_field::type_id::create("mie");
      mpie = uvm_reg_field::type_id::create("mpie");
      // configure(parent, size, lsb, access, volatile, reset, has_reset, is_rand, individually_accessible)
      mie.configure (this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
      mpie.configure(this, 1, 7, "RW", 0, 1'b0, 1, 1, 0);
    endfunction
  endclass

  class mcpu_mtvec_reg extends uvm_reg;
    `uvm_object_utils(mcpu_mtvec_reg)
    rand uvm_reg_field base, mode;
    function new(string name = "mtvec");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      base = uvm_reg_field::type_id::create("base");
      mode = uvm_reg_field::type_id::create("mode");
      base.configure(this, 30, 2, "RW", 0, 30'h40, 1, 1, 0);   // reset BASE = 0x40 -> register reads 0x100
      mode.configure(this,  2, 0, "RW", 0, 2'b00,  1, 1, 0);
    endfunction
  endclass

  class mcpu_mepc_reg extends uvm_reg;
    `uvm_object_utils(mcpu_mepc_reg)
    rand uvm_reg_field epc, zero;
    function new(string name = "mepc");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      epc  = uvm_reg_field::type_id::create("epc");
      zero = uvm_reg_field::type_id::create("zero");
      epc.configure (this, 31, 1, "RW", 0, 31'h0, 1, 1, 0);
      zero.configure(this,  1, 0, "RO", 0, 1'b0,  1, 0, 0);    // bit 0 is read-only zero: modelled so a stuck-1 bug is visible
    endfunction
  endclass

  class mcpu_mcause_reg extends uvm_reg;
    `uvm_object_utils(mcpu_mcause_reg)
    rand uvm_reg_field code;
    function new(string name = "mcause");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      code = uvm_reg_field::type_id::create("code");
      code.configure(this, 32, 0, "RO", 1, 32'h0, 1, 0, 0);    // volatile: hardware changes it; not checked by mirror
    endfunction
  endclass

  class mcpu_csr_block extends uvm_reg_block;
    `uvm_object_utils(mcpu_csr_block)
    rand mcpu_mstatus_reg mstatus;
    rand mcpu_mtvec_reg   mtvec;
    rand mcpu_mepc_reg    mepc;
    rand mcpu_mcause_reg  mcause;
    function new(string name = "mcpu_csr_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      // one address unit per register (CSR number), 4-byte data, not byte addressed
      default_map = create_map("csr_map", 'h0, 4, UVM_LITTLE_ENDIAN, 0);
      mstatus = mcpu_mstatus_reg::type_id::create("mstatus");
      mstatus.configure(this, null, "");             // why: attach register to this block (no regfile, no hdl path yet)
      mstatus.build();
      default_map.add_reg(mstatus, 'h300, "RW");
      mtvec = mcpu_mtvec_reg::type_id::create("mtvec");
      mtvec.configure(this, null, "");
      mtvec.build();
      default_map.add_reg(mtvec, 'h305, "RW");
      mepc = mcpu_mepc_reg::type_id::create("mepc");
      mepc.configure(this, null, "");
      mepc.build();
      default_map.add_reg(mepc, 'h341, "RW");
      mcause = mcpu_mcause_reg::type_id::create("mcause");
      mcause.configure(this, null, "");
      mcause.build();
      default_map.add_reg(mcause, 'h342, "RO");
    endfunction
  endclass

  class mcpu_ral_model_test extends uvm_test;
    `uvm_component_utils(mcpu_ral_model_test)
    mcpu_csr_block blk;
    function new(string name = "mcpu_ral_model_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      blk = mcpu_csr_block::type_id::create("blk");
      blk.configure(null, "");
      blk.build();
      blk.lock_model();                              // why: freezes the model and computes addresses; required before use
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this, "ral model test");
      blk.reset();                                   // mirror and desired := reset values
      `uvm_info("RAL", $sformatf("reset: mstatus=%s mtvec=%s mepc=%s mcause=%s",
                mcpu_fmt32(blk.mstatus.get_mirrored_value()), mcpu_fmt32(blk.mtvec.get_mirrored_value()),
                mcpu_fmt32(blk.mepc.get_mirrored_value()), mcpu_fmt32(blk.mcause.get_mirrored_value())), UVM_LOW)
      `uvm_info("RAL", $sformatf("addresses: mstatus=0x%0h mtvec=0x%0h mepc=0x%0h mcause=0x%0h",
                blk.mstatus.get_address(), blk.mtvec.get_address(), blk.mepc.get_address(), blk.mcause.get_address()), UVM_LOW)

      blk.mstatus.mie.set(1);                        // desired value only: nothing has touched the DUT
      blk.mstatus.mpie.set(1);
      `uvm_info("RAL", $sformatf("after set mie=1 mpie=1: desired=%s mirrored=%s",
                mcpu_fmt32(blk.mstatus.get()), mcpu_fmt32(blk.mstatus.get_mirrored_value())), UVM_LOW)

      void'(blk.mstatus.predict(32'h88, -1, UVM_PREDICT_WRITE));   // as if a frontdoor write of 0x88 completed
      `uvm_info("RAL", $sformatf("after predict WRITE 0x88: mirrored=%s", mcpu_fmt32(blk.mstatus.get_mirrored_value())), UVM_LOW)

      void'(blk.mcause.predict(32'hDEAD, -1, UVM_PREDICT_WRITE));  // RO field ignores a software write
      `uvm_info("RAL", $sformatf("mcause predict WRITE 0xDEAD: mirrored=%s", mcpu_fmt32(blk.mcause.get_mirrored_value())), UVM_LOW)
      void'(blk.mcause.predict(32'hB, -1, UVM_PREDICT_DIRECT));    // hardware updated it (e.g. observed by a monitor)
      `uvm_info("RAL", $sformatf("mcause predict DIRECT 0xB: mirrored=%s", mcpu_fmt32(blk.mcause.get_mirrored_value())), UVM_LOW)

      void'(blk.mepc.predict(32'h1001, -1, UVM_PREDICT_WRITE));    // bit 0 is RO zero
      `uvm_info("RAL", $sformatf("mepc predict WRITE 0x1001: mirrored=%s", mcpu_fmt32(blk.mepc.get_mirrored_value())), UVM_LOW)

      blk.reset();
      `uvm_info("RAL", $sformatf("after reset(): mstatus=%s mepc=%s mcause=%s",
                mcpu_fmt32(blk.mstatus.get_mirrored_value()), mcpu_fmt32(blk.mepc.get_mirrored_value()),
                mcpu_fmt32(blk.mcause.get_mirrored_value())), UVM_LOW)
      phase.drop_objection(this, "ral model test done");
    endtask
  endclass
endpackage

`ifndef MCPU_SKIP_LEAF_TOPS
module tb_top_ralmodel;
  import uvm_pkg::*;
  import mcpu_ral_pkg::*;
  initial run_test("mcpu_ral_model_test");
endmodule
`endif

// Expected log (hand-derived, not simulated); all at time 0, UVM-internal lines elided
//
// UVM_INFO example01.sv(128) @ 0: uvm_test_top [RAL] reset: mstatus=0x00000000 mtvec=0x00000100 mepc=0x00000000 mcause=0x00000000
// UVM_INFO example01.sv(131) @ 0: uvm_test_top [RAL] addresses: mstatus=0x300 mtvec=0x305 mepc=0x341 mcause=0x342
// UVM_INFO example01.sv(136) @ 0: uvm_test_top [RAL] after set mie=1 mpie=1: desired=0x00000088 mirrored=0x00000000
// UVM_INFO example01.sv(140) @ 0: uvm_test_top [RAL] after predict WRITE 0x88: mirrored=0x00000088
// UVM_INFO example01.sv(143) @ 0: uvm_test_top [RAL] mcause predict WRITE 0xDEAD: mirrored=0x00000000
// UVM_INFO example01.sv(145) @ 0: uvm_test_top [RAL] mcause predict DIRECT 0xB: mirrored=0x0000000b
// UVM_INFO example01.sv(148) @ 0: uvm_test_top [RAL] mepc predict WRITE 0x1001: mirrored=0x00001000
// UVM_INFO example01.sv(151) @ 0: uvm_test_top [RAL] after reset(): mstatus=0x00000000 mepc=0x00000000 mcause=0x00000000
//
// mtvec reset: BASE field reset 0x40 at bit 2 -> 0x40 << 2 = 0x100. The field set() changes the DESIRED value only (0x88);
// the mirror (what the model believes the DUT holds) changes only on predict/read/write. A WRITE prediction applies the access
// policy: the RO mcause ignores it; a DIRECT prediction forces the value (used for hardware-driven changes). mepc: EPC gets
// 0x1001 >> 1 = 0x800 -> register 0x1000; bit 0 is RO zero.
`endif
