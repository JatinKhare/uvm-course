# Module 07 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

A verification engineer wrote an opcode-mix item that should produce **40% R-type ALU, 20% ADDI, 15% LW, 15% SW, 5% BEQ, 5% CSRRW**. Two independent bugs make the statistics wrong. For each: locate it, explain the mechanism, give the minimal fix, and compute the numbers (derive them; do not guess).

## Setup / DUT assumptions

`cpu_instr_item` is the Module 03 item with its constraints (`c_small_regs`, `c_unused_rd`, `c_align`, `c_csr`). The subclass below is used for 10,000 randomisations. Count only the `(op, imm)` pairs when reasoning about solution counts (ignore the register fields).

## Code

```systemverilog
class mcpu_bad_mix_item extends cpu_instr_item;
  `uvm_object_utils(mcpu_bad_mix_item)
  constraint c_mix   { op dist { [OP_ADD:OP_OR] := 40, OP_ADDI := 20, OP_LW := 15,
                                 OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5 }; }
  constraint c_order { solve imm before op; }
  function new(string name = "mcpu_bad_mix_item");
    super.new(name);
  endfunction
endclass
```

## Symptoms

Over 10,000 items, the tallies show:

- **R-type ALU (ADD, SUB, AND, OR combined): about 83.5%** (intended 40%). ADDI about 10.4%, BEQ about 2.6%, **LW about 1.7%, SW about 1.7%** (intended 15% each).
- **`OP_CSRRW`: zero occurrences** in 10,000 items.
- Every generated item is legal; `randomize()` never fails.

## A correct answer must achieve

- Bug 1 identified, with the exact weights and the resulting probabilities **if it were the only bug** (compute the total weight): this is *not* the 83.5% above.
- Bug 2 identified, with an explanation of why CSRRW and also LW/SW are suppressed, including the probability that a uniformly chosen `imm` makes each of them legal, and the combined effect of both bugs on the tallies (derive 83.5%, 10.4%, 2.6%, 1.7%).
- The minimal corrected constraint block.
- The probability of each opcode class after the fix (state the assumption that makes "40/20/15/15/5/5" exact, and why legality constraints do not change it with the right solve order).
- One sentence on how a test could detect a distribution bug automatically.

Compare against `solutions/module07/exercise02_solution.md`.
