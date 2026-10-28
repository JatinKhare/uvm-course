# Module 04 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_lsu_monitor extends uvm_monitor;
  `uvm_component_utils(mcpu_lsu_monitor)
  uvm_analysis_port#(mcpu_bus_txn) ap;
  mcpu_agent_cfg      cfg;
  virtual mini_cpu_if vif;

  function new(string name = "mcpu_lsu_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);                                                  // TODO 1
    if (cfg == null) `uvm_fatal("NOCFG", "lsu monitor: cfg was not set by the agent")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    bit          pending = 1'b0;
    bit [31:0]   p_addr, p_wdata;
    bit          p_we;
    mcpu_bus_txn txn;

    forever begin
      @(posedge vif.clk);                                                  // TODO 2

      if (!vif.rst_n) begin
        pending = 1'b0;
      end else if (vif.ls_req && !pending) begin
        p_addr  = vif.ls_addr;                                             // TODO 3
        p_we    = vif.ls_we;
        p_wdata = vif.ls_wdata;
        pending = 1'b1;
      end else if (vif.ls_rvalid && pending) begin
        txn = mcpu_bus_txn::type_id::create("txn");                        // TODO 4
        txn.addr     = p_addr;
        txn.is_write = p_we;
        txn.data     = p_we ? p_wdata : vif.ls_rdata;
        ap.write(txn);
        pending = 1'b0;
      end
    end
  endtask
endclass
```

## TODO 1 — Port, vif, checked cfg

`ap = new("ap", this)`; `vif = cfg.vif` after a `cfg == null` check with `[NOCFG]`. A null `cfg` would otherwise be a null dereference with a poor message.

## TODO 2 — The subtle one: sample on the clock, every cycle

`@(posedge vif.clk)` — one decision per cycle, on the same instant the DUT samples.
**Wrong answers and symptoms:**
- `@(posedge vif.ls_req)`: `ls_req` stays high across back-to-back accesses, so the second and later requests produce **no rising edge**; they are never captured, the following response finds `pending == 0` and is ignored → published transactions are fewer than the DUT's accesses, only the first of a burst appears. It also samples after the DUT's non-blocking update, mixing cycle conventions.
- `wait (vif.ls_req)`: a level wait returns immediately every time it is already true → a zero-delay infinite loop (simulation hangs at one time step).
- `@(vif.ls_rvalid)`: catches only changes; a response in consecutive cycles is missed.

## TODO 3 — Capture the request when `ls_req && !pending`

Save address, direction and write data now: for loads the *response* cycle carries the data, for stores the request carries it, but by the response cycle the request fields may already have been replaced by a back-to-back successor. `pending = 1` marks an access in flight. The `!pending` condition prevents re-capturing the same held request on every cycle.

## TODO 4 — One new transaction per completed access

`type_id::create` inside the branch, fill from the saved request and (for loads) `ls_rdata`, `ap.write`, then clear `pending`.
**Wrong answers and symptoms:**
- A single `txn` created in `build_phase` and reused: a scoreboard that queues handles sees all entries equal to the last access; a logger that prints inside `write` looks fine and hides the bug.
- Using `vif.ls_wdata` at response time for stores: for back-to-back traffic it may already belong to the next request.
- Publishing at request time for loads: `ls_rdata` is not valid yet.

## Self-review checklist

- [x] No config_db in this class; `cfg` is assigned by the agent (as in Module 04 example01).
- [x] `ap` created in `build_phase`; `super.build_phase` called; ports connected by the agent.
- [x] No signal is driven.
- [x] Every path through the loop body awaits a clock edge (no zero-delay loop).
- [x] A new transaction object per access.
- [x] Types match (`mcpu_bus_txn`, `virtual mini_cpu_if`).

## Expected log (hand-derived, not simulated)

Illustrative scenario for a logger subscribed to `ap`: edges at 5, 15, 25, ...; the DUT presents a store to `0x100` of `0x2a` (sampled high from edge 105), the slave responds with `ls_rvalid = 1` (sampled at edge 115); `ls_req` stays high and a load of `0x100` is presented (sampled from 125); `ls_rvalid = 1` with `ls_rdata = 0x2a` sampled at 135:

```
@ 115 [LSU] WR addr=0x00000100 data=0x0000002a
@ 135 [LSU] RD addr=0x00000100 data=0x0000002a
```

(the monitor captures the store at 105, completes it at 115, captures the load at 125, completes it at 135).

## The result that matters

A monitor is a cycle-by-cycle state machine driven by the clock, not by signal edges: levels and held signals (like `ls_req`) carry no edge information. Variation to try: let the response and the next request's first cycle coincide (response edge also samples a new `ls_req`) — decide how the single `pending` flag and the branch ordering handle it, and what extra state you would need if a second outstanding access were allowed.
