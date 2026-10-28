# Module 06 / Exercise 01 — Solution

## Full solution code

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

  // TODO 1
  function void write_exp(mcpu_retire_txn t);
    exp_q.push_back(t);
    try_compare();
  endfunction

  // TODO 2
  function void write_act(mcpu_retire_txn t);
    act_q.push_back(t);
    try_compare();
  endfunction

  // TODO 3
  function void try_compare();
    mcpu_retire_txn e, a;
    while (exp_q.size() > 0 && act_q.size() > 0) begin
      e = exp_q.pop_front();
      a = act_q.pop_front();
      n_cmp++;
      if (!e.compare(a)) begin
        n_bad++;
        `uvm_error("CMP_MISMATCH", $sformatf("compare #%0d exp: %s | act: %s", n_cmp, e.convert2string(), a.convert2string()))
      end
    end
  endfunction

  // TODO 4
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (n_cmp == 0)
      `uvm_error("CMP_EMPTY", "no pairs were compared: nothing was checked")
    if (exp_q.size() > 0)
      `uvm_error("CMP_LEFT_EXP", $sformatf("%0d expected items never matched by an actual", exp_q.size()))
    if (act_q.size() > 0)
      `uvm_error("CMP_LEFT_ACT", $sformatf("%0d actual items had no expected partner", act_q.size()))
  endfunction
endclass
```

## TODO 1 and 2 — Push then try to compare

Each callback pushes and calls `try_compare()`, so whichever stream arrives last triggers the comparison. This is what makes the comparator order-independent within a time step: if the actual arrives first it waits in `act_q`; when the expected arrives, `write_exp` runs the loop and pairs them.
**Wrong answer:** `write_act` pops `exp_q` directly. **Symptom:** when an actual arrives in the same time step before its expected, the pop of an empty queue is a runtime error (simulator-specific message) or a stale entry is compared; intermittent because it depends on call order in that time step.

## TODO 3 — The subtle one: `while`, and pop both on every iteration

- `while (both non-empty)` drains a backlog: three expecteds arriving before the first actual, then three actuals in one step, are all compared. With `if`, only one pair is compared per callback; the rest wait for the *next* callback, and at the end two pairs are left over (`CMP_LEFT_*` errors although nothing is wrong).
- Pop **both** entries before comparing, whatever the result. If the code pops only on match, the first mismatch leaves both entries in the queues; every later comparison is then off by one and the log floods with errors that hide the first (real) one.
**Wrong answer:** compare `exp_q[0]` with `act_q[0]` and pop only if equal. **Symptom:** one real mismatch followed by errors for every subsequent pair.

## TODO 4 — End-of-test verdicts

Three independent errors with counts. `CMP_EMPTY` catches "actual stream not connected / monitor dead"; `CMP_LEFT_EXP` catches missing actuals; `CMP_LEFT_ACT` catches extra actuals.
**Wrong answer:** checking only the queue sizes: with nothing connected both are 0 and the test passes silently.

## Self-review checklist

- [x] No `config_db` use; ports are imps (constructed in `build_phase`); the env connects both producers (not part of this class).
- [x] `write_exp` / `write_act` names match the macro suffixes `_exp` / `_act`.
- [x] `super.new`, `super.build_phase`, `super.check_phase` called.
- [x] No objections used in this component.
- [x] Types match (`mcpu_retire_txn` everywhere); no undeclared identifiers.
- [x] The producers must create a new `mcpu_retire_txn` per item (the comparator stores handles). Cloning on entry would need a correct `do_copy` in the transaction (the course's `mcpu_retire_txn` has none), so the contract is "producers never reuse an object".

## Expected log (hand-derived, not simulated)

For a test in which the expected stream is `A, B, C` and the actual stream is `A, B', C` with `B'` differing in `data`, items arriving in any order within their time steps, exactly one error:

```
UVM_ERROR ... [CMP_MISMATCH] compare #2 exp: <B> | act: <B'>
```

and no `CMP_*` errors at the end. If the actual stream never arrives: a single `CMP_EMPTY` and a `CMP_LEFT_EXP` with count 3.

## The result that matters

A comparator's correctness is about **what it does under reordering and under failure**: buffer both sides, drain with `while`, consume both on every compare, and make absence of data an error. Variation to try: bound the in-flight difference (`exp_q.size() - act_q.size()`) at, say, the pipeline depth and report an error if the actual stream falls further behind.
