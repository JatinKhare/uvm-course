# Module 08 / Exercise 02 — Solution

## Full solution code (repaired covergroup)

```systemverilog
covergroup cg_fixed;
  option.per_instance = 1;
  cp_class: coverpoint cls {
    bins alu = {C_R, C_ADDI};
    bins mem = {C_LW, C_SW};
    bins ctl = {C_BEQ, C_CSR};
    ignore_bins other = {C_OTHER};
  }
  cp_dist: coverpoint dist {
    bins none = {D_NONE};
    bins d1   = {D1};
    bins d2   = {D2};
    bins d3   = {D3};                // explicit: every distance is a plan item
  }
  x_cd: cross cp_class, cp_dist;     // no blanket ignore
endgroup
```

## Why the original reports 100%

Counted bins and hits for the five samples `(R,none) (ADDI,D1) (BEQ,none) (CSR,D2) (SW,none)`:
- `cp_class`: bins `alu`, `mem`, `ctl` = 3. Hits: `alu` (R, ADDI), `ctl` (BEQ, CSR), `mem` (SW) → **3/3 = 100%**.
- `cp_dist`: `none`, `near` are counted; `far = default` is **not counted**. Hits: `none` (R, BEQ, SW), `near` (D1 from ADDI, D2 from CSR) → **2/2 = 100%**.
- `x_cd`: 3 × 2 = 6 cross bins, minus the ignored `mem × {none, near}` (2 bins) = **4** counted bins: `(alu,none)`←R, `(alu,near)`←ADDI/D1, `(ctl,none)`←BEQ, `(ctl,near)`←CSR/D2 → **4/4 = 100%**. The SW sample falls in an ignored bin.
- covergroup: (100 + 100 + 100)/3 = **100%**.

## The two defects

1. **`bins far = default;`** — the catch-all bin is excluded from the coverage calculation by the LRM. Distance 3 (and any other value) lands there, is never required, and the coverage point reads complete without having seen one hazard at distance 3. The plan item "hazard at distance 3" is not represented by any counted bin.
2. **`ignore_bins no_mem = binsof(cp_class.mem);`** inside the cross — removes *every* memory-class combination from the cross: load-use and store-data hazards at all distances become impossible to measure or require. It reads like a "cleanup" but it deletes the very scenarios (LW at distance 1) that hazard logic exists for.

## Numbers for the same five samples after the repair

- `cp_class`: 3/3 → **100.0**
- `cp_dist`: bins `none, d1, d2, d3`; hit `none` (R, BEQ, SW), `d1` (ADDI), `d2` (CSR) → 3/4 → **75.0** (`d3` is now a visible hole)
- `x_cd`: 3 × 4 = 12 bins; hit `(alu,none)`, `(alu,d1)`, `(ctl,none)`, `(ctl,d2)`, `(mem,none)` → 5/12 → **41.7**
- covergroup: (100 + 75 + 41.7)/3 = **72.2%**

The same samples now read 72%, with the uncovered distance and every unhit `mem` combination listed as holes: the report tells the truth.

## When an `ignore_bins` is justified

For a combination the architecture makes **impossible** — for example, if the specification inserts a mandatory bubble before any CSR instruction that follows a producer, then `(csr, d1)` cannot occur. Write beside it: `// ignore: spec section X.Y, CSRRW cannot issue 1 cycle after a producer; checked by assertion a_csr_bubble`, and back the claim with an assertion or a formal proof; use `illegal_bins` if a hit would be a design bug.

## Self-review checklist

- [x] No `default` bin among counted bins; every plan value has an explicit bin.
- [x] No blanket `ignore_bins`; the only ignored value (`C_OTHER`) is outside the model's scope.
- [x] Bin counts and hits derived for each item.
- [x] Same samples, repaired model → honest coverage (72.2%).

## Expected log

Not applicable (the symptom is the coverage report; derivations above).

## The result that matters

Coverage constructs that *remove* bins (`default`, `ignore_bins`) must be treated like waivers: each one needs a reason, and a reviewer should be able to see what it hides. Variation to try: re-add `ignore_bins no_mem` and compute the report with the repaired bins; then explain to a reviewer what it would hide.
