# Module 10 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// mcpu_env_base_test.build_phase
uvm_top.set_timeout(10us, 0);              // Bug A fix (and a policy, see below)

// mcpu_reset_test.run_phase
task run_phase(uvm_phase phase);
  mcpu_smoke_prog_seq s1, s2;
  mcpu_rst_scoreboard rsb;
  phase.raise_objection(this, "reset test");
  phase.phase_done.set_drain_time(this, 50ns);
  s1 = mcpu_smoke_prog_seq::type_id::create("s1");
  s1.start(env.ifetch_agent.seqr);
  #52ns;                                   // Bug B fix: settle (not an edge time; last retirement observed at 195)
  rstc.req = 1'b1;
  @(negedge vif.rst_n);
  @(posedge vif.rst_n);
  if (!$cast(rsb, env.sb)) `uvm_fatal("CAST", "scoreboard is not the reset-capable variant")
  rsb.flush();
  s2 = mcpu_smoke_prog_seq::type_id::create("s2");
  s2.start(env.ifetch_agent.seqr);
  phase.drop_objection(this, "reset test done");
endtask
```

## Bug A — a timeout shorter than the test

**Mechanism:** `uvm_top.set_timeout(100ns, 0)` limits the run phase to 100 ns. Program 1 alone ends at 185 ns (last execution at the 185 ns edge). At 100 ns the phase timeout fires — a `UVM_FATAL` whose ID is typically `PH_TIMEOUT` (ID and text **SIMULATOR/VERSION-DEPENDENT**) — and UVM ends the simulation abruptly, so the scoreboard's `report_phase` never runs: no summary.
**Policy, not just a bigger number:** the timeout must be (a) much longer than the longest legitimate test (here the whole reset test ends at 455 ns; 10 µs is about 20×), (b) short enough that a hang fails fast in CI, and (c) settable per test (`overridable = 1` or the `+UVM_TIMEOUT` plusarg) for long soak tests. A hung test should produce a **clean, classifiable failure** (timeout signature), never a stuck job.

## Bug B — reset requested before the last retirement is observed

**Timeline of the buggy run (after Bug A is fixed):**
- Program 1's last item completes at 185 ns; `s1.start` returns.
- `#7ns` → **192 ns**: the test requests reset; `tb_top` drives `rst_n = 0` at 192.
- The last retire record (instruction #5, executed at the 185 ns edge) is visible from 185 to 195 and would be sampled by the retire monitor **at the 195 ns edge**. But at 195 `rst_n` is already 0, and the monitor's condition is `rst_n && retire_valid`: **the retirement is not published**. (The DUT's synchronous reset clears `retire_valid` at the same edge anyway.)
- The fetch observation of instruction #5 had already happened (at 185), so the scoreboard holds one **expected** entry with no actual partner.
- Reset releases at the 210 ns negedge; the test calls `rsb.flush()`, which **deletes** `exp_q`, including that pending entry.
- Program 2 runs normally: 5 fetches, 5 comparisons.
Totals: fetched 5 + 5 = 10; compared 4 (program 1: #1–#4, at 75, 105, 135, 165) + 5 = **9**; no mismatch; and the run ends earlier than the correct run (program 2 starts at 210 instead of 260: it ends at 355, plus 50 ns drain → 405 ns).
**Why nothing reports it:** the pending expectation was *removed* by `flush()` before `check_phase` could count it (`SB_INFLIGHT` looks at `exp_q` at the end of the test, and it is empty). The `n_cmp == 0` check only fires when *nothing* was compared. Reset logic that silently discards state is a classic way to lose coverage of a check.
**Fix:** let the retirement be observed and compared before reset, e.g. `#52ns` (237 ns is after the 195 ns observation and not on an edge), or better, wait for the scoreboard to be quiescent:

```systemverilog
wait (rsb.exp_q.size() == 0 && rsb.act_q.size() == 0);   // after the $cast, before requesting reset
```

(valid because the last instruction's expectation is queued at its fetch observation and consumed only by its retirement.) Add an explicit warning to `flush()` if it discards a non-empty queue.

## Expected log after both fixes (hand-derived, not simulated)

The Module 10 `example02.sv` reset-test timeline: reset at 237, release at 260, program 2 executions at 285, 315, 345, 375, 405:

```
UVM_INFO ... @ 455: uvm_test_top.env.sb [SB] fetched=10 compared=10 mismatched=0
```

## Self-review checklist

- [x] Timeout ≫ longest test and policy stated.
- [x] Reset ordering: settle → reset → wait for release → flush → restart.
- [x] Reset request not issued on a clock-edge time (race-free).
- [x] `flush()` runs after the previous program is fully compared.
- [x] Counters tie out: fetched = compared + 0 left over.

## The result that matters

Two different classes of bug: a **loud** one (timeout) and a **silent** one (a lost comparison). The silent one is found by *counting*: every fetched instruction must be compared exactly once, so `compared` must equal `fetched` at the end. Make that equality an end-of-test check. Variation to try: make `flush()` print a warning with the number of discarded entries and predict the Run-2 log with the bug present.
