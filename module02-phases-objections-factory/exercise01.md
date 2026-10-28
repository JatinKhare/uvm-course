# Module 02 / Exercise 01 — Override one scoreboard and keep late activity alive (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Write `mcpu_x_test` so that:
- the env's `sb_b` is a `mcpu_strict_scoreboard` while `sb_a` stays a plain `mcpu_scoreboard`, and
- a late monitor event (33 ns) still appears in the log although the test finishes its work at 30 ns.

## Setup / DUT assumptions

No DUT. Reuse from `example02.sv` of this module: `mcpu_scoreboard` (logs `I am <type>` in `build_phase`) and `mcpu_strict_scoreboard`. The following are given and must not be edited:

```systemverilog
class mcpu_late_mon extends uvm_component;
  `uvm_component_utils(mcpu_late_mon)
  function new(string name = "mcpu_late_mon", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);          // note: raises no objection
    #33ns;
    `uvm_info("LATE", "late event observed", UVM_LOW)
  endtask
endclass

class mcpu_x_env extends uvm_env;
  `uvm_component_utils(mcpu_x_env)
  mcpu_scoreboard sb_a, sb_b;
  mcpu_late_mon   late;
  function new(string name = "mcpu_x_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb_a = mcpu_scoreboard::type_id::create("sb_a", this);
    sb_b = mcpu_scoreboard::type_id::create("sb_b", this);
    late = mcpu_late_mon::type_id::create("late", this);
  endfunction
endclass
```

## Skeleton

```systemverilog
class mcpu_x_test extends uvm_test;
  `uvm_component_utils(mcpu_x_test)
  mcpu_x_env env;

  function new(string name = "mcpu_x_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO 1: make ONLY sb_b a mcpu_strict_scoreboard
    // YOUR CODE HERE

    // TODO 2: create the env under this test with instance name "env"
    // YOUR CODE HERE
  endfunction

  task run_phase(uvm_phase phase);
    // TODO 3: hold the phase open for this test's work, and make sure the 33 ns event
    //         is not cut off; the objection must still be dropped at 30 ns
    // YOUR CODE HERE
    #30ns;
    `uvm_info("TEST", "work done, releasing objection", UVM_LOW)
    // TODO 4: release
    // YOUR CODE HERE
  endtask
endclass
```

## A correct answer must achieve

1. Log lines `sb_a ... I am mcpu_scoreboard` and `sb_b ... I am mcpu_strict_scoreboard`, both at time 0.
2. `[TEST] work done` at 30 ns **and** `[LATE] late event observed` at 33 ns.
3. The objection is dropped at 30 ns (not later): do not solve the late event by extending the test's own delay.
4. The simulation ends: no objection left raised.

Compare against `solutions/module02/exercise01_solution.md`.
