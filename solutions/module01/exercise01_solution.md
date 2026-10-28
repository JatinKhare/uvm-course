# Module 01 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_smoke_test extends uvm_test;
  `uvm_component_utils(mcpu_smoke_test)               // TODO 1

  virtual mini_cpu_if vif;

  function new(string name = "mcpu_smoke_test", uvm_component parent = null);   // TODO 2
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);          // TODO 3
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned n_retired = 0;

    phase.raise_objection(this, "smoke test running"); // TODO 4

    @(posedge vif.rst_n);
    while (n_retired < 3) begin
      @(posedge vif.clk);
      if (vif.retire_valid) begin
        n_retired++;
        `uvm_info("RUN", $sformatf("retire #%0d pc=0x%08h", n_retired, vif.retire_pc), UVM_LOW)
      end
    end

    phase.drop_objection(this, "3 retires seen");      // TODO 5
  endtask
endclass
```

## TODO 1 — Factory registration

`` `uvm_component_utils(mcpu_smoke_test) `` adds the class to the factory's name table. `run_test("mcpu_smoke_test")` looks the string up there.
**Wrong answer:** omit it, or use `` `uvm_object_utils `` (wrong registry flavour; a test is a component). **Log symptom:** `UVM_FATAL ... [INVTST]` at time 0 stating the requested test was not found; no phase runs.

## TODO 2 — Constructor

Signature must be `(string name, uvm_component parent)`; defaults are conventional. Body is only `super.new(name, parent)`.
**Wrong answer:** `new(string name)` for a component. **Symptom:** compile error when the factory registry instantiates it with two arguments.

## TODO 3 — `super.build_phase` then checked `get`

`super.build_phase(phase)` first (base-class work), then `get(this, "", "vif", vif)`. The `get` call matches the `set` in `tb_top`: type `virtual mini_cpu_if`, instance path `uvm_test_top` (which is what `this` plus `""` resolves to), field `"vif"`. The `if (!...)` is the point of TODO 3: `get` returns 0 on a miss and leaves `vif` null.
**Wrong answer:** call `get` without checking. **Symptom:** nothing at build; a null-handle runtime error at the first `vif.rst_n` access in `run_phase` (message wording is simulator-dependent).

## TODO 4 — The subtle one: raise before the first delay

The objection must be raised **before** `@(posedge vif.rst_n)`. All `run_phase` tasks start at time 0; the phase ends when the objection count is zero at the end of a delta. The `@(posedge vif.rst_n)` blocks until 42 ns; if the raise were placed after it, no objection exists at time 0 and the phase ends there.
**Wrong answer:** raise inside or after the `while` loop, or after `@(posedge vif.rst_n)`. **Symptom:** log shows no `[RUN] retire` lines; simulation ends at time 0; no error is reported, so it looks like a pass.

## TODO 5 — Drop after the loop

The drop belongs after the last `uvm_info` of the loop, so the third retire line appears before the phase ends.
**Wrong answer:** drop inside the loop after the first increment, or immediately after the raise. **Symptom:** the log is cut short (fewer than three retire lines), or the phase ends at 75 ns.
**Wrong answer (opposite):** forget the drop. **Symptom:** simulation hangs past 95 ns until a simulator timeout (the run phase has a default timeout whose size is library-dependent, **SIMULATOR/VERSION-DEPENDENT**).

## Self-review checklist

- [x] Every `get` has a matching `set`: `(virtual mini_cpu_if, "uvm_test_top", "vif")`.
- [x] No ports to connect in this test.
- [x] `super.new` and `super.build_phase` called.
- [x] One `raise_objection`, one `drop_objection`, on the same object (`this`), no path that skips the drop.
- [x] `build_phase` is a function, `run_phase` a task.
- [x] Types match; no undeclared identifiers (`n_retired` is declared in `run_phase`).

## Expected log (hand-derived, not simulated)

Using `example01.sv`'s clock/reset/DUT behaviour (retires sampled at 75, 85, 95). Line numbers depend on your file layout.

```
UVM_INFO smoke.sv(<n>) @ 75: uvm_test_top [RUN] retire #1 pc=0x00000000
UVM_INFO smoke.sv(<n>) @ 85: uvm_test_top [RUN] retire #2 pc=0x00000004
UVM_INFO smoke.sv(<n>) @ 95: uvm_test_top [RUN] retire #3 pc=0x00000008
```

The run phase ends at 95 ns.

## The result that matters

An objection is a promise made *at time 0* that more work follows; raising it after any blocking statement is the same as never raising it. Variation to try: move `raise_objection` after `@(posedge vif.rst_n)` and predict the log before reasoning about why it looks like a pass.
