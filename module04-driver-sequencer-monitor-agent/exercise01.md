# Module 04 / Exercise 01 — Load/store-bus monitor (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Complete `mcpu_lsu_monitor`, a read-only monitor for the load/store bus. It publishes **one `mcpu_bus_txn` per completed access** on an analysis port.

## Setup / DUT assumptions

Use `mini_cpu_if`, `mcpu_bus_txn` and `mcpu_agent_cfg` from earlier modules (`module04/example01.sv`). Load/store bus protocol (the DUT is the master):

- A request is present in a clock cycle where `ls_req` is 1. In that cycle `ls_we`, `ls_addr` and `ls_wdata` are valid. `ls_req` **stays high until the response arrives** (it is not a pulse).
- The slave responds at least one cycle after the request with `ls_rvalid = 1` for one cycle. For a load, `ls_rdata` is valid in that cycle; for a store, `ls_rvalid` is the acknowledgement and `ls_rdata` is ignored.
- One access is outstanding at a time, but a new request may start in the cycle **right after** the response, **without `ls_req` ever dropping** (back-to-back accesses).
- "In a cycle" means: the values sampled at the rising clock edge. Reset is `rst_n` (active low); an access cannot span a reset.
- The published transaction: `addr` from the request; `is_write` from the request's `ls_we`; `data` = the request's `ls_wdata` for a store, or the response cycle's `ls_rdata` for a load.

## Skeleton

```systemverilog
class mcpu_lsu_monitor extends uvm_monitor;
  `uvm_component_utils(mcpu_lsu_monitor)
  uvm_analysis_port#(mcpu_bus_txn) ap;
  mcpu_agent_cfg      cfg;                 // assigned by the agent after create()
  virtual mini_cpu_if vif;

  function new(string name = "mcpu_lsu_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO 1: create the analysis port; obtain vif from cfg; stop with ID "NOCFG" if cfg is missing
    // YOUR CODE HERE
  endfunction

  task run_phase(uvm_phase phase);
    bit          pending = 1'b0;
    bit [31:0]   p_addr, p_wdata;
    bit          p_we;
    mcpu_bus_txn txn;

    forever begin
      // TODO 2: wait for the next sample point
      // YOUR CODE HERE

      if (!vif.rst_n) begin
        pending = 1'b0;
      end else if (vif.ls_req && !pending) begin
        // TODO 3: remember what the request looked like
        // YOUR CODE HERE
      end else if (vif.ls_rvalid && pending) begin
        // TODO 4: publish exactly one transaction for this completed access
        // YOUR CODE HERE
        pending = 1'b0;
      end
    end
  endtask
endclass
```

## A correct answer must achieve

1. With back-to-back accesses (`ls_req` high continuously across several accesses), **every** access is published, once.
2. The published data/address/direction match the rules above for both loads and stores.
3. Two consecutive transactions are distinct objects (a scoreboard holding both sees both values).
4. The monitor never drives any signal.
5. A missing `cfg` stops the simulation with `[NOCFG]`.

Compare against `solutions/module04/exercise01_solution.md`.
