# Module 02 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

The code compiles. It has **two independent bugs**. For each: point at the line(s), explain via UVM mechanics why the log shows the symptom, give the minimal fix, and state the expected log after both fixes.

## Setup / DUT assumptions

No DUT. `mcpu_scoreboard` and `mcpu_strict_scoreboard` are as in `example02.sv` (the scoreboard logs `I am <type name>` in `build_phase`).

## Code

```systemverilog
class mcpu_worker extends uvm_component;
  `uvm_component_utils(mcpu_worker)
  function new(string name = "mcpu_worker", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "worker");
    for (int step = 1; step <= 5; step++) begin
      #10ns;
      `uvm_info("WRK", $sformatf("step %0d", step), UVM_LOW)
      if (step == 2) begin
        `uvm_error("WRK", "check failed, abandoning run")
        return;
      end
    end
    phase.drop_objection(this, "worker done");
  endtask
endclass

class mcpu_dbg_env extends uvm_env;
  `uvm_component_utils(mcpu_dbg_env)
  mcpu_scoreboard sb;
  mcpu_worker     wrk;
  function new(string name = "mcpu_dbg_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sb  = new("sb", this);
    wrk = mcpu_worker::type_id::create("wrk", this);
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      #100ns;
      `uvm_info("ENV", "heartbeat", UVM_LOW)
    end
  endtask
endclass

class mcpu_dbg_test extends uvm_test;
  `uvm_component_utils(mcpu_dbg_test)
  mcpu_dbg_env env;
  function new(string name = "mcpu_dbg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mcpu_scoreboard::type_id::set_type_override(mcpu_strict_scoreboard::get_type());
    env = mcpu_dbg_env::type_id::create("env", this);
  endfunction
endclass
```

## Symptoms

**Symptom 1.** The test's intent is that every scoreboard is strict. The log at time 0 shows:

```
UVM_INFO ... @ 0: uvm_test_top.env.sb [SB] I am mcpu_scoreboard
```

**Symptom 2.** The log then continues:

```
UVM_INFO  ... @ 10:  uvm_test_top.env.wrk [WRK] step 1
UVM_INFO  ... @ 20:  uvm_test_top.env.wrk [WRK] step 2
UVM_ERROR ... @ 20:  uvm_test_top.env.wrk [WRK] check failed, abandoning run
UVM_INFO  ... @ 100: uvm_test_top.env     [ENV] heartbeat
UVM_INFO  ... @ 200: uvm_test_top.env     [ENV] heartbeat
...
```

and the heartbeat lines never stop; the simulation has to be killed externally.

## A correct answer must achieve

- Each bug located, with the mechanism (not just the fix).
- Minimal fixes that keep the `uvm_error` behaviour (the failed check must still be reported and counted).
- The expected log after both fixes, with times.
- One sentence on a testbench-level safeguard that would turn Symptom 2 into a clean failure instead of a hang.

Compare against `solutions/module02/exercise02_solution.md`.
