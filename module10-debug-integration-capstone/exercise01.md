# Module 10 / Exercise 01 — A negative test with a report catcher (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

The DUT is run with `+MCPU_BUG_ADD` (ADD returns `a+b+1`). The scoreboard correctly reports two `RETIRE_MISMATCH` errors. Write `mcpu_neg_test`, a test that **expects** exactly those two errors: it turns them into informational messages, counts them, and passes only if the count is exactly 2. Any other error must still count as an error.

## Setup / DUT assumptions

- The bench is `module10/example02.sv`; `mcpu_neg_test` extends `mcpu_smoke_test` and is run as `+UVM_TESTNAME=mcpu_neg_test +MCPU_BUG_ADD`. The mismatch messages carry the ID `RETIRE_MISMATCH` and severity `UVM_ERROR`.
- `uvm_report_catcher` provides `get_severity()`, `set_severity(sev)`, `get_id()` and the callback `catch()`, which returns `THROW` (let the message continue) or `CAUGHT` (swallow it).
- A report callback is installed with `uvm_report_cb::add(obj, catcher)`; `obj == null` means **every** report in the simulation.

## Skeleton

```systemverilog
class mcpu_expect_mismatch_catcher extends uvm_report_catcher;
  int unsigned n_caught;
  function new(string name = "mcpu_expect_mismatch_catcher");
    super.new(name);
  endfunction
  virtual function action_e catch();
    // TODO 1: for a UVM_ERROR with ID "RETIRE_MISMATCH": count it and turn it into a UVM_INFO that is still printed.
    //         Every other message passes through unchanged.
    // YOUR CODE HERE
  endfunction
endclass

class mcpu_neg_test extends mcpu_smoke_test;
  `uvm_component_utils(mcpu_neg_test)
  mcpu_expect_mismatch_catcher catcher;

  function new(string name = "mcpu_neg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    catcher = new();
    // TODO 2: install the catcher for all reports, before any message can be produced
    // YOUR CODE HERE
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // TODO 3: the test passes only if exactly 2 mismatches were caught; otherwise it is an error
    //         (message ID "NEG_COUNT"); on success print an info with ID "NEG"
    // YOUR CODE HERE
  endfunction
endclass
```

## A correct answer must achieve

1. In the log, both mismatches (at 135 ns and 195 ns) appear as `UVM_INFO` lines (not errors) with their original ID and text.
2. The final UVM report summary shows **zero** `UVM_ERROR`s when the bug is present as expected.
3. If the DUT is run **without** `+MCPU_BUG_ADD` the test fails with `NEG_COUNT` (caught 0, expected 2); if a different error occurs (for example a `PC_MISMATCH`) it is **not** hidden.
4. The catcher does not swallow the messages: they remain visible.

Compare against `solutions/module10/exercise01_solution.md`.
