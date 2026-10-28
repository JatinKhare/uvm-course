# Module 01 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

The testbench below compiles cleanly. It has **two independent bugs**. For each: name the bug, explain why the log shows the symptom, give the minimal fix, and say what log line proves the fix worked.

## Setup / DUT assumptions

- `mini_cpu_if`, `mini_cpu` as in `example01.sv`; fetch responder and clock/reset the same (reset releases at 42 ns).
- Only the class `mcpu_dbg_test` and the `tb_top` hand-off are shown.

## Code

```systemverilog
class mcpu_dbg_test extends uvm_test;
  `uvm_component_utils(mcpu_dbg_test)
  virtual mini_cpu_if vif;

  function new(string name = "mcpu_dbg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    `uvm_info("RUN", "waiting for reset release", UVM_LOW)
    @(posedge vif.rst_n);
    `uvm_info("RUN", "reset released", UVM_LOW)
    repeat (3) @(posedge vif.clk);
    `uvm_info("RUN", "three cycles after reset", UVM_LOW)
  endtask
endclass

// in tb_top:
initial begin
  uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test", "vif", vif);
  run_test("mcpu_dbg_test");
end
```

## Symptoms

**Run 1.** The log ends almost immediately:

```
UVM_FATAL example_dbg.sv(<n>) @ 0: uvm_test_top [NOVIF] virtual interface 'vif' not found in config_db
```

**Run 2** (after you fix whatever caused Run 1). No fatal, but the log shows:

```
UVM_INFO example_dbg.sv(<n>) @ 0: uvm_test_top [RUN] waiting for reset release
[... UVM report summary ...]
```

and the simulation finishes at time 0. The `reset released` and `three cycles after reset` lines never print.

## A correct answer must achieve

- Both bugs located by pointing at the specific line(s), with the UVM mechanism that produces each symptom.
- A fix for each that changes as little as possible.
- The expected log (times included) after both fixes.
- One sentence on why Run 2's symptom is invisible if you only look at pass/fail status.

Compare against `solutions/module01/exercise02_solution.md`.
