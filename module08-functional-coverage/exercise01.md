# Module 08 / Exercise 01 — Coverage for the load/store stream (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Complete `mcpu_lsu_cov`, a subscriber that measures the load/store traffic published by the load/store monitor (`mcpu_bus_txn`: `addr`, `data`, `is_write`). The model must record direction, address region, the "write immediately followed by read" pattern, and the cross of direction and region.

## Setup / DUT assumptions

- `mcpu_bus_txn` as in Module 04 (`bit is_write`, `bit [31:0] addr`).
- Regions: **low** = `0x000`–`0x0FF`, **mid** = `0x100`–`0x1FF`, **high** = `0x200` and above.
- `is_write == 1` means a store.
- Default weights, `option.per_instance = 1`.

## Skeleton

```systemverilog
class mcpu_lsu_cov extends uvm_subscriber#(mcpu_bus_txn);
  `uvm_component_utils(mcpu_lsu_cov)
  bit        is_wr;
  bit [31:0] addr;

  covergroup cg;
    option.per_instance = 1;
    cp_dir    : coverpoint is_wr { bins rd = {0}; bins wr = {1}; }
    cp_region : coverpoint addr  { bins low  = {[32'h000:32'h0FF]};
                                   bins mid  = {[32'h100:32'h1FF]};
                                   bins high = {[32'h200:32'hFFFF_FFFF]}; }
    // TODO 2: a separate coverpoint with ONE transition bin: a store immediately followed by a load
    // YOUR CODE HERE
    x_dir_region: cross cp_dir, cp_region;
  endgroup

  function new(string name = "mcpu_lsu_cov", uvm_component parent = null);
    super.new(name, parent);
    // TODO 1: make the covergroup usable
    // YOUR CODE HERE
  endfunction

  function void write(mcpu_bus_txn t);
    // TODO 3: record this transaction's direction and address, then sample once
    // YOUR CODE HERE
  endfunction
endclass
```

## A correct answer must achieve

1. No run-time error at the first transaction.
2. For the transaction sequence `(WR, 0x100)`, `(RD, 0x100)`, `(RD, 0x040)`, `(WR, 0x300)` delivered to `write()` in this order, the covergroup reports: `cp_dir` 100%, `cp_region` 100%, the transition coverpoint 100%, the cross 4 of 6 bins, and a **covergroup coverage of 91.7%**.
3. Each transaction is sampled exactly once, with its **own** fields.
4. The transition bin is hit by the first two transactions and by nothing else.

Compare against `solutions/module08/exercise01_solution.md`.
