# Module 02 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// mcpu_worker.run_phase
task run_phase(uvm_phase phase);
  phase.raise_objection(this, "worker");
  for (int step = 1; step <= 5; step++) begin
    #10ns;
    `uvm_info("WRK", $sformatf("step %0d", step), UVM_LOW)
    if (step == 2) begin
      `uvm_error("WRK", "check failed, abandoning run")
      break;                                   // Bug B fix: leave the loop, not the task
    end
  end
  phase.drop_objection(this, "worker done");   // now reached on every path
endtask

// mcpu_dbg_env.build_phase
sb  = mcpu_scoreboard::type_id::create("sb", this);     // Bug A fix
wrk = mcpu_worker::type_id::create("wrk", this);
```

## Bug A — `sb = new("sb", this)`

**Mechanism:** the test registers `set_type_override(mcpu_strict_scoreboard)` correctly and before the env is created, but `new()` never calls the factory, so the override cannot reach `sb`. The component is still built (it logs in `build_phase`) as the plain base class.
**Fix:** `type_id::create("sb", this)`. **Proof:** `[SB] I am mcpu_strict_scoreboard`.
**Common wrong fix:** moving the override call around; the ordering was already right.

## Bug B — `return` skips `drop_objection`

**Mechanism:** the error path leaves the task with the objection still raised. The count for `wrk` (and its ancestors) never returns to zero, so the run phase never starts ending. `mcpu_dbg_env.run_phase` is a `forever` loop (legal: it is killed at phase end), so it keeps printing heartbeats indefinitely. `uvm_error` itself does not end the simulation by default.
**Fix:** a single exit path that always reaches the drop (`break`, then drop after the loop). **Proof:** after the error line the simulation ends at 20 ns with no heartbeat.
**Common wrong fixes:** adding a second `drop_objection` before `return` (works here but is how double-drop bugs start); `` `uvm_fatal `` instead of `uvm_error` (ends the run but changes the required behaviour).
**Safeguard (one sentence):** set a realistic phase timeout in the base test (`uvm_top.set_timeout(<time>, 1)`), so a stuck objection becomes a clean fatal; the timeout default and message ID are **SIMULATOR/VERSION-DEPENDENT**.

## Self-review checklist

- [x] No `config_db`.
- [x] No ports.
- [x] `super.new`, `super.build_phase` called in all components.
- [x] Objections balanced on every path (single drop after the loop).
- [x] Override registered before the env is created; created with `type_id::create`.
- [x] Types match (`mcpu_strict_scoreboard` derives from `mcpu_scoreboard`).

## Expected log (hand-derived, not simulated)

```
UVM_INFO  ... @ 0:  uvm_test_top.env.sb  [SB]  I am mcpu_strict_scoreboard
UVM_INFO  ... @ 10: uvm_test_top.env.wrk [WRK] step 1
UVM_INFO  ... @ 20: uvm_test_top.env.wrk [WRK] step 2
UVM_ERROR ... @ 20: uvm_test_top.env.wrk [WRK] check failed, abandoning run
```

The run phase ends at 20 ns (no drain time); the summary reports 1 `UVM_ERROR`. The env heartbeat (first at 100 ns) never prints.

## The result that matters

Objections are a resource: every raise needs exactly one drop on every control-flow path, including error paths. A hung test is almost always an objection leak or a sequence stuck on a handshake. Variation to try: keep `return` but wrap the body in a `try`-style pattern with a single exit label; compare readability with the `break` version.
