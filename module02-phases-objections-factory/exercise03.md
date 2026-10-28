# Module 02 / Exercise 03 — Predict the log

**Type:** Predict the log. No simulator needed; this is hand-tracing.

## Goal

Predict every `[P]` line the code below produces, in order, with its simulation time. Then state: (a) which messages exist in the source but **never** print, and (b) the time at which `report_phase` runs and why.

## Setup / DUT assumptions

No DUT. Time unit ns. No drain time is set anywhere. All three classes are registered and created through the factory from `tb_top` via `run_test("mcpu_p_test")`. Ignore UVM-internal lines (banner, summary); only `[P]` lines matter. Where two messages could share a time, the code is written so that they do not.

## Code

```systemverilog
class mcpu_p_agent extends uvm_component;
  `uvm_component_utils(mcpu_p_agent)
  function new(string name = "mcpu_p_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("P", "agent build", UVM_LOW)
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info("P", "agent connect", UVM_LOW)
  endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #20ns;
    `uvm_info("P", "agent run done", UVM_LOW)
    phase.drop_objection(this);
  endtask
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("P", "agent report", UVM_LOW)
  endfunction
endclass

class mcpu_p_env extends uvm_env;
  `uvm_component_utils(mcpu_p_env)
  mcpu_p_agent agent;
  function new(string name = "mcpu_p_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("P", "env build", UVM_LOW)
    agent = mcpu_p_agent::type_id::create("agent", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info("P", "env connect", UVM_LOW)
  endfunction
  task run_phase(uvm_phase phase);          // raises no objection
    #15ns;
    `uvm_info("P", "env tick 1", UVM_LOW)
    #20ns;
    `uvm_info("P", "env tick 2", UVM_LOW)
  endtask
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("P", "env report", UVM_LOW)
  endfunction
endclass

class mcpu_p_test extends uvm_test;
  `uvm_component_utils(mcpu_p_test)
  mcpu_p_env env;
  function new(string name = "mcpu_p_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("P", "test build", UVM_LOW)
    env = mcpu_p_env::type_id::create("env", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info("P", "test connect", UVM_LOW)
  endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #10ns;
    `uvm_info("P", "test run done", UVM_LOW)
    phase.drop_objection(this);
  endtask
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("P", "test report", UVM_LOW)
  endfunction
endclass
```

## A correct answer must achieve

- The full ordered list of `[P]` lines with times (the hierarchy path in the log is not required, only the message and time).
- Correct build/connect/report orders across the three components.
- Correct identification of the messages that never print, with the reason.
- The time of the report lines and the mechanism that fixes it.

Compare against `solutions/module02/exercise03_solution.md`.
