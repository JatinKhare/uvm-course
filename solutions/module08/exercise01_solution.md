# Module 08 / Exercise 01 — Solution

## Full solution code

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
    // TODO 2
    cp_trans  : coverpoint is_wr { bins wr_rd = (1 => 0); }
    x_dir_region: cross cp_dir, cp_region;
  endgroup

  function new(string name = "mcpu_lsu_cov", uvm_component parent = null);
    super.new(name, parent);
    // TODO 1
    cg = new();
  endfunction

  function void write(mcpu_bus_txn t);
    // TODO 3
    is_wr = t.is_write;
    addr  = t.addr;
    cg.sample();
  endfunction
endclass
```

## TODO 1 — Construct the embedded covergroup in `new`

An embedded covergroup is an object that must be created: `cg = new();` inside the class constructor (after `super.new`). Without it, `cg` is null and the first `cg.sample()` fails at run time (message tool-specific) — at the first transaction, which makes the bug easy to miss if the first test never sends one.

## TODO 2 — A separate coverpoint for the transition

`bins wr_rd = (1 => 0)` means "value 1 at one sample, value 0 at the **next** sample". It goes in its own coverpoint rather than inside `cp_dir` so that the cross `x_dir_region` keeps using the plain `rd`/`wr` bins; keeping transition bins out of crosses avoids relying on how a given tool crosses transition bins.
**Wrong answer:** `(0 => 1)` (a read followed by a write): hit by nothing in the given sequence; the transition coverpoint would stay at 0% and the total drops to 66.7%. **Wrong answer:** adding the transition bin inside `cp_dir` and then crossing `cp_dir`: cross bin counts become tool-dependent.

## TODO 3 — The subtle one: set the fields, then sample, once

The covergroup samples the **member variables** `is_wr` and `addr`. They must hold this transaction's values at the moment of `sample()`.
**Wrong answers and symptoms:**
- `cg.sample()` before the assignments: each sample sees the previous transaction's fields (and the first sees zeros): the bins hit are shifted by one transaction; with the given sequence the first sample is `(RD, 0x000)`: `cp_dir.rd` and `low` get hit by a transaction that never occurred, the real last transaction `(WR, 0x300)` is never sampled, and the transition coverage is wrong.
- Calling `sample()` twice per transaction (e.g. in `write` and again in a `report` hook): transition bins see `1 => 1` and `0 => 0` pairs; the `wr_rd` bin is hit only if the second call happens to be skipped; counts of every bin double.

## Self-review checklist

- [x] Covergroup constructed in the constructor, after `super.new`.
- [x] `super.new(name, parent)` called; `write` has the signature required by `uvm_subscriber#(mcpu_bus_txn)`.
- [x] One sample per transaction, after the fields are assigned.
- [x] Region bins are disjoint and cover the 32-bit space; the transition lives in its own coverpoint.
- [x] No undeclared identifiers.

## Expected log (hand-derived, not simulated)

For the sequence `(WR,0x100) (RD,0x100) (RD,0x040) (WR,0x300)` delivered to `write()`:
- `cp_dir`: `wr` hit (1st, 4th), `rd` hit (2nd, 3rd) → 2/2 = **100.0**
- `cp_region`: `mid` (1st, 2nd), `low` (3rd), `high` (4th) → 3/3 = **100.0**
- `cp_trans`: `wr_rd` hit at the 2nd sample (previous 1, now 0) → 1/1 = **100.0**
- `x_dir_region`: 2 × 3 = 6 bins; hit `(wr,mid)`, `(rd,mid)`, `(rd,low)`, `(wr,high)` → 4/6 = **66.7**
- covergroup: (100 + 100 + 100 + 66.7) / 4 = **91.7%**

## The result that matters

A covergroup is only as honest as its *sampling discipline*: constructed once, fed correct values, sampled exactly once per observation. Variation to try: make the first transaction `(RD, 0x100)` and predict which bins stay open, and whether the transition bin can still be hit by a later pair.
