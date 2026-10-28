# Module 01 / Exercise 01 — Complete `mcpu_smoke_test` (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection (no simulator needed).

## Goal

Write a test, `mcpu_smoke_test`, that waits for reset release and then logs the first **3** retired instructions of `mini_cpu`, and ends the simulation cleanly right after the third.

## Setup / DUT assumptions

- Use the `mini_cpu_if`, the stub `mini_cpu`, and `tb_top` from `example01.sv` unchanged, except:
  - `tb_top` calls `run_test("mcpu_smoke_test");`
  - your class goes into `mcpu_pkg` in place of `mcpu_base_test`.
- `tb_top` stores the virtual interface with `uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);`
- Clock period 10 ns, reset released at 42 ns, as in `example01.sv`.

## Skeleton

```systemverilog
class mcpu_smoke_test extends uvm_test;
  // TODO 1: make this class creatable by run_test("mcpu_smoke_test")
  // YOUR CODE HERE

  virtual mini_cpu_if vif;

  // TODO 2: constructor with the standard component signature and defaults
  // YOUR CODE HERE

  function void build_phase(uvm_phase phase);
    // TODO 3: do the base-class work, then obtain vif; if it is missing,
    //         the simulation must stop with a clear message (ID "NOVIF")
    // YOUR CODE HERE
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned n_retired = 0;

    // TODO 4: make sure the run phase cannot end before the third retire is logged
    // YOUR CODE HERE

    @(posedge vif.rst_n);
    while (n_retired < 3) begin
      @(posedge vif.clk);
      if (vif.retire_valid) begin
        n_retired++;
        `uvm_info("RUN", $sformatf("retire #%0d pc=0x%08h", n_retired, vif.retire_pc), UVM_LOW)
      end
    end

    // TODO 5: allow the run phase to end now
    // YOUR CODE HERE
  endtask
endclass
```

## A correct answer must achieve

1. `run_test("mcpu_smoke_test")` finds and starts the test (no `INVTST` fatal).
2. If `vif` is not in `uvm_config_db`, the simulation stops in `build_phase` with `[NOVIF]`.
3. All three `[RUN] retire #n` lines appear in the log, with their expected times.
4. The simulation does not end before the third retire line and does not hang after it.
5. Every `super.*` call that the UVM pattern requires is present.

Write your answer, then compare against `solutions/module01/exercise01_solution.md`.
