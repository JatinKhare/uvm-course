# Module 03 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

Two independent bugs in the stimulus code below. For each: locate it, explain the mechanism that produces the symptom, give a minimal fix, and say what the log would show after the fix.

## Setup / DUT assumptions

Same environment as `module03/example01.sv` (stub driver prints every item with `convert2string()`), except that the item class has been edited as shown. Only the changed part of the item is listed; `new`, `encode`, `convert2string` are unchanged. Enum `cpu_opcode_e` as in the lesson.

## Code

```systemverilog
class cpu_instr_item extends uvm_sequence_item;
  `uvm_object_utils(cpu_instr_item)
  rand cpu_opcode_e op;
  rand bit [4:0]    rd, rs1, rs2;
  bit [11:0]        imm;                                              // (as written)

  constraint c_small_regs { soft rd inside {[1:7]}; soft rs1 inside {[1:7]}; soft rs2 inside {[1:7]}; }
  constraint c_unused_rd  { (op inside {OP_SW, OP_BEQ}) -> rd == 0; }
  constraint c_align      { (op inside {OP_LW, OP_SW}) -> imm[1:0] == 2'b00; }
  constraint c_csr        { (op == OP_CSRRW) -> imm inside {12'h300, 12'h305, 12'h341}; }
  // new(), encode(), convert2string() unchanged
endclass

class mcpu_bad_seq extends uvm_sequence#(cpu_instr_item);
  `uvm_object_utils(mcpu_bad_seq)
  function new(string name = "mcpu_bad_seq");
    super.new(name);
  endfunction
  task body();
    cpu_instr_item it;
    repeat (3) begin
      it = cpu_instr_item::type_id::create("it");
      start_item(it);
      void'(it.randomize() with { op == OP_LW; imm[1:0] == 2'b01; });
      finish_item(it);
    end
  endtask
endclass
```

`mcpu_rand_seq` (from the lesson) is also used: it creates an item, `start_item`, `randomize()`, `finish_item`, 200 times.

## Symptoms

**Symptom 1.** Running `mcpu_bad_seq`, the simulator prints a randomisation failure message (wording is tool-specific) and the driver log shows three identical lines:

```
UVM_INFO ... [DRV] got OP_ADD rd=x0 rs1=x0 rs2=x0 imm=0x000 enc=0x00000033
UVM_INFO ... [DRV] got OP_ADD rd=x0 rs1=x0 rs2=x0 imm=0x000 enc=0x00000033
UVM_INFO ... [DRV] got OP_ADD rd=x0 rs1=x0 rs2=x0 imm=0x000 enc=0x00000033
```

**Symptom 2.** After the author "fixes" the inline constraint to make Symptom 1 go away, `mcpu_rand_seq` runs without any failure message, but across its 200 items the log shows: **no** `OP_CSRRW` ever, and **every** item has `imm=0x000` (including `ADDI`, `LW`, `SW`, `BEQ`).

## A correct answer must achieve

- Both root causes named, with the exact lines.
- An explanation of why Symptom 1 has **two** contributing causes in the code as given, and which fix(es) are needed.
- Why no failure message accompanies Symptom 2.
- The minimal code changes, and the expected log after them for `mcpu_bad_seq` (it must still request `OP_LW`).

Compare against `solutions/module03/exercise02_solution.md`.
