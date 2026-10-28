# Module 08 — Check Your Understanding: Answers

## 1. Nearest-producer distances

| Instruction | Sources | Producers in the last three | Distance |
|---|---|---|---|
| `ADDI x1,x0,5` | x0 (ignored) | — | none |
| `ADDI x2,x0,7` | x0 (ignored) | — | none |
| `ADD x3,x1,x2` | x1, x2 | x2 written 1 back, x1 written 2 back | **1** (nearest) |
| `SW x3,0(x4)` | x4, x3 | x3 written 1 back; x4 never | **1** |
| `LW x5,0(x4)` | x4 | none (the SW wrote no register) | none |

The model records the **nearest** producer, i.e. the smallest distance at which *any* source register matches: the closest producer determines the worst-case forwarding/stall condition. The ADD also depends on `x1` at distance 2, but that dependency is already "covered" by the nearer one; the model counts one distance per instruction (a model that wants both would use two coverpoints, one per operand).

## 2. `cp_dist` with a default bin

Counted bins: `none`, `near`. Samples 0 → `none`, 1 and 2 → `near`, 3 → `far = default`. Coverage = 2/2 = **100%**. Distance 3 goes into the default bin, which is **not counted**: it contributes nothing to the percentage and is easy to overlook. The plan item "hazard at distance 3" is effectively unmeasured.

## 3. Cross with the CSR row ignored, after phase B

Cross bins counted: 5 classes (R, ADDI, LW, SW, BEQ) × 4 distances = **20** (the 4 `csr` combinations are removed). Hits after phase B (A: 4, B: +3, none of them CSR): **7**. Cross = 7/20 = **35.0%**. `cp_class` is unaffected by the cross's `ignore_bins` (still 5/6 = 83.3%) and `cp_dist` is 4/4 = 100%. Covergroup = (83.3 + 100 + 35.0)/3 = **72.8%** (versus 70.8% without the ignore). Removing bins raises the percentage without exercising anything new, which is exactly why every `ignore_bins` needs a reason.
