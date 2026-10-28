# Module 06 / Exercise 01 — Order-independent two-queue comparator (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Complete `mcpu_cmp`, a comparator with two inputs — an **expected** stream and an **actual** stream of `mcpu_retire_txn` — that compares in order and reports problems in a way that cannot hide the first failure.

## Setup / DUT assumptions

- `mcpu_retire_txn` (with its `do_compare` and `convert2string`) is as in `module06/example01.sv`.
- Both streams carry the same number of items per test, in program order. Items may arrive in **either order** within a time step; several expected items may arrive before the first actual.
- At the end of a correct test every item has a partner; the test uses drain time so in-flight items complete.

## Skeleton

```systemverilog
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class mcpu_cmp extends uvm_scoreboard;
  `uvm_component_utils(mcpu_cmp)
  uvm_analysis_imp_exp#(mcpu_retire_txn, mcpu_cmp) exp_imp;
  uvm_analysis_imp_act#(mcpu_retire_txn, mcpu_cmp) act_imp;
  mcpu_retire_txn exp_q[$], act_q[$];
  int unsigned    n_cmp, n_bad;

  function new(string name = "mcpu_cmp", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  // TODO 1: callback for the expected stream
  // YOUR CODE HERE

  // TODO 2: callback for the actual stream
  // YOUR CODE HERE

  // TODO 3: compare every pair that is currently available; each mismatch must be reported
  //         with both sides visible (ID "CMP_MISMATCH") and must not disturb later comparisons
  function void try_compare();
    mcpu_retire_txn e, a;
    // YOUR CODE HERE
  endfunction

  // TODO 4: end-of-test verdicts: nothing compared (ID "CMP_EMPTY"), items left on either queue
  //         (IDs "CMP_LEFT_EXP", "CMP_LEFT_ACT"); each as an error with the count
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // YOUR CODE HERE
  endfunction
endclass
```

## A correct answer must achieve

1. If an actual item arrives in the same time step **before** its expected partner, it is still compared, once, when the partner arrives.
2. If three expected items arrive before the first actual, then three actuals arrive in one time step, all three compares occur and the queues are empty afterwards.
3. After a mismatch, later items are still paired correctly (no offset).
4. A test in which no actual stream is connected produces an error at the end; so does a test with extra items on either side.
5. No handle that the producer may later reuse is relied upon beyond the compare.

Compare against `solutions/module06/exercise01_solution.md`.
