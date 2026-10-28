# Module 07 / Exercise 01 — An item with a "reuse the previous destination" knob (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Complete `mcpu_hazard_item`, a subclass of `cpu_instr_item` used by a stream sequence to create dependent instruction pairs. The sequence sets `prev` to the previously sent instruction (it is `null` for the very first one) and then randomises the item. The knob `reuse_prev` says whether this instruction reads, in `rs1`, the register the previous one wrote.

## Setup / DUT assumptions

- `cpu_instr_item` and its constraints are as in Module 03 (`rd`, `rs1`, `rs2` are 5 bits; register `x0` is hard-wired to zero, so a previous `rd` of 0 means the previous instruction wrote no register).
- `prev` is a **non-rand** handle, set by the sequence before each `randomize()`.
- Intended behaviour: when a reuse is *possible* (previous instruction exists and wrote a register), `reuse_prev` should be 1 about 70% of the time and 0 about 30%; when it is *not possible*, `reuse_prev` must be 0 and randomisation must still succeed.

## Skeleton

```systemverilog
class mcpu_hazard_item extends cpu_instr_item;
  `uvm_object_utils(mcpu_hazard_item)

  cpu_instr_item prev;                 // previous instruction in the stream, or null
  rand bit       reuse_prev;           // 1: rs1 must equal prev.rd

  // TODO 1: weight reuse_prev so that 1 is chosen 70% and 0 30% of the time
  // YOUR CODE HERE

  // TODO 2: if there is no previous instruction, reuse_prev is 0;
  //         if there is one, reuse_prev == 1 requires that it wrote a register (prev.rd != 0) and rs1 == prev.rd.
  //         The first instruction of a stream (prev == null) must randomise without error.
  // YOUR CODE HERE

  // TODO 3: make the 70/30 choice independent of how many rs1 values each case leaves
  // YOUR CODE HERE

  function new(string name = "mcpu_hazard_item");
    super.new(name);
  endfunction
endclass
```

## A correct answer must achieve

1. `randomize()` succeeds for the first instruction (`prev == null`) and returns `reuse_prev == 0`.
2. If `prev != null` and `prev.rd == 0`, `reuse_prev == 0` and `randomize()` still succeeds.
3. If `prev != null` and `prev.rd != 0`: `reuse_prev == 1` implies `rs1 == prev.rd`; the choice follows the 70/30 weights.
4. All legality constraints of the base item still hold (the subclass adds, never removes).
5. No constraint evaluates a field of `prev` when `prev` is `null`.

Compare against `solutions/module07/exercise01_solution.md`.
