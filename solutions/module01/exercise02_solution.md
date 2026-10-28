# Module 01 / Exercise 02 — Solution

## Full solution code

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
    phase.raise_objection(this, "dbg test running");          // fix for Bug B
    `uvm_info("RUN", "waiting for reset release", UVM_LOW)
    @(posedge vif.rst_n);
    `uvm_info("RUN", "reset released", UVM_LOW)
    repeat (3) @(posedge vif.clk);
    `uvm_info("RUN", "three cycles after reset", UVM_LOW)
    phase.drop_objection(this, "dbg test done");              // fix for Bug B
  endtask
endclass

// in tb_top:
initial begin
  uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);   // fix for Bug A
  run_test("mcpu_dbg_test");
end
```

## Bug A — config_db instance path `"uvm_test"` instead of `"uvm_test_top"`

**Why the symptom:** `run_test` names the test instance `uvm_test_top`. `set(null, "uvm_test", "vif", vif)` stores the value for a component whose full name is exactly `uvm_test`; no such component exists. The `get(this, "", "vif", vif)` in the test looks up the field for `uvm_test_top`, finds no matching entry, returns 0, and the testbench's own `uvm_fatal` fires at time 0 in `build_phase`.
**Fix:** `"uvm_test_top"` in the `set`. **Proof:** the `[NOVIF]` fatal disappears and `[RUN] waiting for reset release` appears.
**Common wrong fixes:** changing the field name (it already matches); adding a wildcard `"*"` (works, but hides the mistake and over-broadens the scope — Module 05); removing the `if` check around `get` (turns a clear fatal into a null-handle error later).

## Bug B — no objection in `run_phase`

**Why the symptom:** all `run_phase` tasks start at time 0, and the phase ends when no component holds an objection. This test never raises one, so the run phase ends at the end of time 0, right after the first `uvm_info` executes. The `@(posedge vif.rst_n)` statement (42 ns) is simply abandoned. The other phases (`extract`, `check`, `report`, `final`) run normally, so the simulation finishes without any error.
**Fix:** raise before the first blocking statement; drop at the end. **Proof:** the `reset released` line appears at 42 ns.
**Common wrong fix:** raise after `@(posedge vif.rst_n)` — still ends at time 0.

## Self-review checklist

- [x] The one `get` matches the one `set`: `(virtual mini_cpu_if, "uvm_test_top", "vif")`.
- [x] No ports.
- [x] `super.new`, `super.build_phase` present.
- [x] Objections balanced (one raise, one drop, no early exit).
- [x] Phases correct (function build, task run).
- [x] No undeclared identifiers.

## Expected log (hand-derived, not simulated)

Clock edges at 5, 15, 25, ...; reset released at 42. `repeat (3) @(posedge vif.clk)` after 42 waits for edges at 45, 55, 65.

```
UVM_INFO dbg.sv(<n>) @ 0:  uvm_test_top [RUN] waiting for reset release
UVM_INFO dbg.sv(<n>) @ 42: uvm_test_top [RUN] reset released
UVM_INFO dbg.sv(<n>) @ 65: uvm_test_top [RUN] three cycles after reset
```

## The result that matters

Run 2's failure is silent: zero errors, zero warnings, normal summary. A test that ends early *looks like a pass*. Habit: have every test log a deliberate "done" line late in the run (or check that simulation time is sane in the summary) so a time-0 exit cannot hide. Variation to try: fix only Bug B first and re-trace; you will hit Bug A's fatal before any run phase starts, because build comes first.
