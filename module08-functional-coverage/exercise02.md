# Module 08 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

A coverage model reports **100%** after only five samples, none of which exercise a load-use hazard, a memory instruction at distance 1 or 2, or any hazard at distance 3. Find why, with the arithmetic, and repair the model so the report is honest.

## Setup / DUT assumptions

Classes and distances are as in `module08/example01.sv`, with the enumerations `mcpu_cls_e` (`C_R, C_ADDI, C_LW, C_SW, C_BEQ, C_CSR, C_OTHER`) and `mcpu_dist_e` (`D_NONE, D1, D2, D3`). Default weights, `option.per_instance = 1`.

## Code

```systemverilog
covergroup cg_bad;
  option.per_instance = 1;
  cp_class: coverpoint cls {
    bins alu = {C_R, C_ADDI};
    bins mem = {C_LW, C_SW};
    bins ctl = {C_BEQ, C_CSR};
  }
  cp_dist: coverpoint dist {
    bins none = {D_NONE};
    bins near = {D1, D2};
    bins far  = default;
  }
  x_cd: cross cp_class, cp_dist {
    ignore_bins no_mem = binsof(cp_class.mem);
  }
endgroup
```

## Symptoms

The five samples `(cls, dist)` delivered are:
`(C_R, D_NONE)`, `(C_ADDI, D1)`, `(C_BEQ, D_NONE)`, `(C_CSR, D2)`, `(C_SW, D_NONE)`.
The coverage report says: `cp_class 100.0`, `cp_dist 100.0`, `x_cd 100.0`, **covergroup 100.0**.
A reviewer points out that no memory instruction at distance 1 or 2 and no instruction at distance 3 was ever generated.

## A correct answer must achieve

- The exact bin counts for each item that give 100%, derived by hand (which bins exist, which are counted, which samples hit them).
- Both defects identified by name and line, and what each hides.
- A repaired covergroup (explicit bins for every hazard distance and class, no `default`, no blanket `ignore_bins`), and the coverage numbers it reports for the **same five samples** (derive them).
- One sentence on when an `ignore_bins` in this cross *would* be justified, and what you would write next to it.

Compare against `solutions/module08/exercise02_solution.md`.
