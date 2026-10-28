# Module 04 / Exercise 02 — Solution

## Full solution code (changed parts)

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
    seq_item_port.item_done();                         // Bug A fix
  end
endtask

// mcpu_ifetch_agent.connect_phase
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  mon.ap.connect(ap);
  if (cfg.is_active == UVM_ACTIVE)                     // Bug B fix: mirror the build_phase guard
    drv.seq_item_port.connect(seqr.seq_item_export);
endfunction
```

## Bug A — missing `item_done`

**Mechanism:** the first instruction is driven correctly (hence the `[IFD]` at 55 and `[FETCH]` at 65). The loop then restarts and calls `get_next_item` a second time while the first is still "open": the sequencer tracks that state and reports the error seen at 65. Meanwhile the **sequence** is still blocked inside `finish_item` for instruction 1, because only `item_done` releases it; therefore `body()` can never create instruction 2, and `seq.start` never returns. The test never drops its objection, so the run phase never ends. The driver's own behaviour after the error is library-dependent, but the cause of the hang is not: no `item_done`, no progress on the sequence side.
**Fix:** one `item_done` per `get_next_item`, after the item's bus activity completes.
**Common wrong fixes:** calling `item_done` right after `get_next_item` (the sequence resumes while the bus transaction is still in progress; instruction 2 is queued early and the timing of `finish_item` no longer reflects driving); calling `get` instead (acceptable alternative: `get` completes the handshake itself, but then the sequence resumes at fetch time, not drive-complete time).

## Bug B — unguarded `seq_item_port.connect` in a passive agent

**Mechanism:** `build_phase` creates `seqr` and `drv` only when `cfg.is_active == UVM_ACTIVE`. In a passive run they stay null, and `drv.seq_item_port.connect(...)` in `connect_phase` dereferences the null `drv` before any run-phase activity (the failure shows up in the connect phase, so no run-phase message appears).
**Fix:** the same `is_active` condition in `connect_phase`. **Proof:** the connect phase completes in passive mode.

## Self-review checklist

- [x] `cfg` obtained by `get` in the agent with a matching `set` (`this`, `"env.ifetch_agent"`, `"cfg"`, type `mcpu_agent_cfg`) in the test.
- [x] Ports connected: `mon.ap → agent.ap → bus_logger.analysis_export`; `drv.seq_item_port → seqr.seq_item_export` only when active.
- [x] `super.connect_phase` called.
- [x] `get_next_item`/`item_done` paired once per loop iteration.
- [x] Objections balanced (test raises/drops around `seq.start`).
- [x] Create/connect guards use the same condition.

## Expected log (hand-derived, not simulated)

Active run after both fixes (same as the Module 04 `example02.sv` trace):

```
@ 55  [IFD]   drive 0x00500093
@ 65  [FETCH] RD addr=0x00000000 data=0x00500093
@ 75  [IFD]   drive 0x00700113
@ 85  [FETCH] RD addr=0x00000004 data=0x00700113
@ 95  [IFD]   drive 0x002081b3
@ 105 [FETCH] RD addr=0x00000008 data=0x002081b3
@ 115 [IFD]   drive 0x00322023
@ 125 [FETCH] RD addr=0x0000000c data=0x00322023
```

The run phase ends at 145 ns (drain time 20 ns after the drop at 125).
**Passive run after Bug B's fix:** the connect phase completes and the monitor runs; there is no driver, so no `[IFD]` lines; `[FETCH]` lines appear only if something else drives `if_rvalid`/`if_rdata`. The test must not start a sequence on `env.ifetch_agent.seqr` in this mode (the handle is null), so test code should guard on the same `is_active` setting.

## The result that matters

The driver–sequencer handshake is a contract with two sides: `item_done` is the driver's promise that the item is finished, and every sequence's forward progress depends on it. When a sequence "stops" and the test hangs, look at the driver's `item_done` path first. Variation to try: add an early `continue` in the driver loop on reset and decide where `item_done` must go on that path.
