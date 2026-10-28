# Module 10 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

Two independent bugs in the integrated bench's test code. The first stops the run; after you fix it, the second produces a run that **looks perfect** but has skipped a check. For each: locate it, explain the mechanism with the arithmetic, give the minimal fix, and state the expected log after both fixes.

## Setup / DUT assumptions

Everything is as in `module10/example01.sv` and `example02.sv` (executions at 65, 95, 125, 155, 185 ns for program 1; retire records observed 10 ns after each execution; clock edges at 5, 15, …; reset mid-run request pulses `rst_n` low for two clocks and releases on a negedge) **except** the two pieces below. The DUT has no bug.

## Code

```systemverilog
// in mcpu_env_base_test.build_phase
uvm_top.set_timeout(100ns, 0);

// mcpu_reset_test.run_phase
task run_phase(uvm_phase phase);
  mcpu_smoke_prog_seq s1, s2;
  mcpu_rst_scoreboard rsb;
  phase.raise_objection(this, "reset test");
  phase.phase_done.set_drain_time(this, 50ns);
  s1 = mcpu_smoke_prog_seq::type_id::create("s1");
  s1.start(env.ifetch_agent.seqr);
  #7ns;
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

## Symptoms

**Run 1** (`+UVM_TESTNAME=mcpu_reset_test`): the simulation stops with a `UVM_FATAL` from the phase timeout at 100 ns. No `[SB]` summary is printed.

**Run 2** (after Bug A is fixed): the run completes with no `UVM_ERROR` and no `UVM_WARNING`, but the summary reads

```
[SB] fetched=10 compared=9 mismatched=0
```

whereas a correct run compares every instruction.

## A correct answer must achieve

- Bug A: the cause of the timeout at 100 ns, what time program 1 would have ended, and a reasonable timeout policy (not just a bigger number).
- Bug B: the exact times that explain **why exactly one comparison is lost** (reset time versus the observation time of the last retirement), what the monitor does while `rst_n` is low, and why neither `SB_INFLIGHT` nor any other check reports it.
- Minimal fixes for both, and the expected final summary and end time after the fixes.
- One robust alternative to a fixed delay for the settling step.

Compare against `solutions/module10/exercise02_solution.md`.
