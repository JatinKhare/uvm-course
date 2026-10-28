# Module 06 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

Two independent bugs in the checking code. For each: locate it, explain the mechanism behind the symptom, give the minimal fix, and say what the log looks like afterwards.

## Setup / DUT assumptions

The scoreboard, feeder, env and test are exactly as in `module06/example01.sv` / `example02.sv` (same program, same timing: fetches at 0,10,20,30,40 ns, retirements 15 ns later) **except** for the two pieces below. The "DUT" retirement stream is the correct one in Run 1 (all five retirements right). In Run 2 the DUT stream has the third retirement's `data` equal to 13 instead of 12.

## Code

```systemverilog
// in mcpu_iss: the predictor
class mcpu_iss;
  bit [31:0] regs [32];
  bit [31:0] mem  [bit [31:0]];
  bit [31:0] csr  [bit [11:0]];
  bit [31:0] pc;
  mcpu_retire_txn last;                                  // <-- member
  function new();
    foreach (regs[i]) regs[i] = '0;
    pc = '0;
    last = mcpu_retire_txn::type_id::create("exp");
  endfunction

  function mcpu_retire_txn step(bit [31:0] instr);
    // ... decode/execute exactly as in example01.sv, computing opc, rd, we, wdata, next_pc ...
    last.pc    = pc;
    last.instr = instr;
    last.rd    = (we && rd != 0) ? rd    : 5'd0;
    last.data  = (we && rd != 0) ? wdata : 32'd0;
    if (we && rd != 0) regs[rd] = wdata;
    pc = next_pc;
    return last;
  endfunction
endclass

// in mcpu_retire_txn
virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  mcpu_retire_txn r;
  if (!$cast(r, rhs)) return 0;
  return super.do_compare(rhs, comparer) &&
         (pc === r.pc) && (instr === r.instr) && (rd === r.rd);
endfunction
```

## Symptoms

**Run 1 (correct DUT stream).** The scoreboard prints `UVM_ERROR [RETIRE_MISMATCH]` for most or all retirements. In each message the `exp:` side shows an instruction **different from the one being compared** (its `pc` is different from the `act:` side's `pc`), and several messages show the same `exp:` contents.

**Run 2 (after Run 1 is fixed; DUT stream has the wrong `data` on retirement #3).** The log ends with `UVM_INFO [SB] fetched=5 compared=5 mismatched=0` and no errors; the DUT bug is not reported.

## A correct answer must achieve

- Both root causes named with the exact lines.
- Why Run 1's `exp:` sides look like "later" instructions (trace the queue contents at the first compare, using the example's timing).
- Why Run 2 shows a perfect result.
- Minimal fixes, plus one **negative test** that would have caught Bug B immediately.

Compare against `solutions/module06/exercise02_solution.md`.
