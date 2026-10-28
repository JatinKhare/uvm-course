# Module 04 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

Two independent bugs. For each: name it, point at the lines, explain the mechanism that gives the symptom, give the minimal fix, and state the expected log after both fixes.

## Setup / DUT assumptions

Everything is as in `module04/example01.sv` and `example02.sv` (same test, env, sequence, `mini_cpu` stub, timing: reset released at 42 ns, `mcpu_directed_seq` with 4 instructions) **except** the two pieces below.

## Code

```systemverilog
// mcpu_ifetch_driver.run_phase
task run_phase(uvm_phase phase);
  vif.if_rvalid <= 1'b0;
  vif.if_rdata  <= '0;
  forever begin
    seq_item_port.get_next_item(req);
    do @(posedge vif.clk); while (!(vif.rst_n && vif.if_req));
    vif.if_rdata  <= req.encode();
    vif.if_rvalid <= 1'b1;
    `uvm_info("IFD", $sformatf("drive 0x%08h", req.encode()), UVM_LOW)
    @(posedge vif.clk);
    vif.if_rvalid <= 1'b0;
  end
endtask

// mcpu_ifetch_agent.connect_phase  (build_phase is unchanged: seqr/drv exist only when active)
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  mon.ap.connect(ap);
  drv.seq_item_port.connect(seqr.seq_item_export);
endfunction
```

## Symptoms

**Symptom 1 (active run, as in `example02.sv`).** The log shows

```
UVM_INFO  ... @ 55: uvm_test_top.env.ifetch_agent.drv [IFD] drive 0x00500093
UVM_INFO  ... @ 65: uvm_test_top.env.bus_logger       [FETCH] RD addr=0x00000000 data=0x00500093
UVM_ERROR ... @ 65: <sequencer path> [...] (message complains that get_next_item was called twice)
```

and the second program instruction (`0x00700113`) is **never** driven or fetched. The test never reaches its end-of-run (the objection is never released); the log does not show a normal end-of-test. What the driver itself does right after the error is library-version dependent, so reason from the sequencer/sequence side: why can the sequence never produce instruction 2?

**Symptom 2 (a separate run with `ifetch_cfg.is_active = UVM_PASSIVE`, no sequence started).** The run stops with a null-object error during the connect phase, before any run-phase message. The message names the agent's `connect_phase` (wording is tool-specific).

## A correct answer must achieve

- Each bug located, with the mechanism that explains **exactly** the log shown (including why the simulation hangs rather than just stopping).
- Minimal fixes.
- The expected log of the active run after the fix (times from the example's derivation).
- One sentence on what the passive run should look like after the fix and what the test must not do.

Compare against `solutions/module04/exercise02_solution.md`.
