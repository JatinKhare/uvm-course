# Module 10 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_expect_mismatch_catcher extends uvm_report_catcher;
  int unsigned n_caught;
  function new(string name = "mcpu_expect_mismatch_catcher");
    super.new(name);
  endfunction
  virtual function action_e catch();
    // TODO 1
    if (get_severity() == UVM_ERROR && get_id() == "RETIRE_MISMATCH") begin
      n_caught++;
      set_severity(UVM_INFO);
      return THROW;                       // keep the (now informational) message visible
    end
    return THROW;                         // everything else unchanged
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
    // TODO 2
    uvm_report_cb::add(null, catcher);
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    // TODO 3
    if (catcher.n_caught != 2)
      `uvm_error("NEG_COUNT", $sformatf("expected 2 RETIRE_MISMATCH reports, caught %0d", catcher.n_caught))
    else
      `uvm_info("NEG", "caught the 2 expected mismatches: PASS", UVM_LOW)
  endfunction
endclass
```

## TODO 1 — The subtle one: modify, then `THROW`

A catcher's `catch()` decides the **fate** of the message it examines: `THROW` lets it continue through the reporting chain (with any modification you made), `CAUGHT` stops it. After `set_severity(UVM_INFO)` the message must continue to be printed, so the return value is `THROW`. Both severity **and** ID must be tested: matching only the ID would also convert a `RETIRE_MISMATCH` warning or fatal; matching only the severity would convert every error in the run (including a real `PC_MISMATCH`).
**Wrong answers and symptoms:**
- `return CAUGHT` after counting: the two messages vanish from the log (requirement 4 fails); the count is right and the run summary is clean, which makes the test look better than it is.
- Condition on the ID only: a fatal `RETIRE_MISMATCH` (if the scoreboard ever used one) would be downgraded; the verdict could pass on a failure.
- Not changing the severity: the errors stay errors; the summary shows 2 `UVM_ERROR`s and the regression fails although the test "expected" them.

## TODO 2 — Install globally, early

`uvm_report_cb::add(null, catcher)`: `null` registers the catcher for **all** report objects (the scoreboard issues the messages, not the test). Done in `build_phase`, before any message can be issued by the scoreboard.
**Wrong answers and symptoms:** `uvm_report_cb::add(this, catcher)`: the catcher is registered for the *test object* only; the scoreboard's reports do not pass through it, the errors stay errors and `n_caught` remains 0. Installing it in `run_phase` or later is also risky: any report issued earlier misses the catcher (here the mismatches are at 135 and 195 ns, but the principle matters).

## TODO 3 — Exact expectation in `check_phase`

The verdict is a *count*, in `check_phase` (after the run phase). With the bug present the count must be exactly 2 → info `[NEG]`. Without the bug (no `+MCPU_BUG_ADD`) the count is 0 → `UVM_ERROR [NEG_COUNT]`: a negative test **fails when the bug is not detected**.
**Wrong answer:** `if (n_caught == 0) error` only: a run that produced 5 caught mismatches (a different bug or a regression in the bench) would pass.

## Self-review checklist

- [x] No config_db use; catcher and test have name/parent constructors appropriate to their base classes (`uvm_report_catcher` takes a name).
- [x] `super.build_phase`/`super.check_phase` called; the catcher is created before it is registered.
- [x] The catcher returns `THROW` on all paths; only the targeted messages are modified.
- [x] The verdict is exact and sits in `check_phase`.
- [x] Types and enumerations real: `UVM_ERROR`, `UVM_INFO`, `THROW`, `get_severity`, `set_severity`, `get_id`, `uvm_report_cb::add`.

## Expected log (hand-derived, not simulated)

With `+UVM_TESTNAME=mcpu_neg_test +MCPU_BUG_ADD`:

```
UVM_INFO  ... @ 135: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #3 exp: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000c | act: pc=0x00000008 instr=0x002081b3 rd=x3 data=0x0000000d
UVM_INFO  ... @ 195: uvm_test_top.env.sb [RETIRE_MISMATCH] retire #5 exp: pc=0x00000010 instr=0x00022283 rd=x5 data=0x0000000c | act: pc=0x00000010 instr=0x00022283 rd=x5 data=0x0000000d
UVM_INFO  ... @ 235: uvm_test_top.env.sb [SB] fetched=5 compared=5 mismatched=2
UVM_INFO  ... @ 235: uvm_test_top        [NEG] caught the 2 expected mismatches: PASS
```

The report summary shows 0 `UVM_ERROR`. Without the bug: `UVM_ERROR [NEG_COUNT] expected 2 RETIRE_MISMATCH reports, caught 0` at 235 ns.

## The result that matters

A regression needs tests that **fail when a bug escapes**: the catcher turns the scoreboard's *expected* errors into a count, and the count becomes the pass/fail verdict. Variation to try: parameterise the expected count per mutation (`+MCPU_BUG_ADD` → 2, a branch mutation → a different number) and think about what that costs in maintenance versus asserting only "at least one".
