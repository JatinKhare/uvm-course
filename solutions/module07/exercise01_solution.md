# Module 07 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_hazard_item extends cpu_instr_item;
  `uvm_object_utils(mcpu_hazard_item)

  cpu_instr_item prev;
  rand bit       reuse_prev;

  // TODO 1
  constraint c_reuse_dist { reuse_prev dist { 1 := 70, 0 := 30 }; }

  // TODO 2
  constraint c_reuse_none { (prev == null) -> (reuse_prev == 0); }
  constraint c_reuse_do   { (prev != null) -> ( reuse_prev -> ( (prev.rd != 0) && (rs1 == prev.rd) ) ); }

  // TODO 3
  constraint c_reuse_ord  { solve reuse_prev before rs1; }

  function new(string name = "mcpu_hazard_item");
    super.new(name);
  endfunction
endclass
```

## TODO 1 — `dist` on the knob

`1 := 70, 0 := 30`: single values, so `:=` and `:/` are identical here. Weights are relative: 70/(70+30) = 70%.

## TODO 2 — The subtle one: guard constraints for a possibly null handle

`prev` is `null` for the first instruction. A constraint that dereferences `prev.rd` with a null handle is not something the solver can evaluate: the unguarded `reuse_prev -> (rs1 == prev.rd)` makes the **first** `randomize()` fail or raise a tool error, even though the author "only wanted reuse sometimes". The fix is a **guard**: put the null test as the left operand of an implication, `(prev != null) -> ( ... prev.rd ... )`; SystemVerilog guard constraints let the solver evaluate the guard first and skip the guarded expression when it is false. The second constraint handles `prev == null` by forcing `reuse_prev == 0`.
Inside the guarded part, `reuse_prev -> (prev.rd != 0 && rs1 == prev.rd)` makes the knob legal only when the previous instruction wrote a register: if `prev.rd == 0`, the right-hand side is false, so the implication forces `reuse_prev = 0`, and `randomize()` still succeeds.
**Wrong answers and symptoms:**
- Unguarded dereference: failure (or a tool null-access error) on the first item only; later items work, which makes the bug look intermittent when `prev` is sometimes null.
- `reuse_prev -> rs1 == prev.rd` without the `prev.rd != 0` check: when the previous instruction wrote nothing (a store or branch, `rd == 0`), a "hazard" on `x0` is generated — a hazard that does not exist in hardware.
- Making `prev` `rand`: the solver then tries to randomise the object handle's contents; do not.

## TODO 3 — `solve reuse_prev before rs1`

Without it, the number of `rs1` values compatible with each choice (exactly one when `reuse_prev == 1`, up to seven in the register pool when `0`) skews how often each case is chosen, so the observed split is not 70/30. With the ordering, `reuse_prev` is picked first from its weights (among the feasible values), then `rs1` is solved for it.
**Wrong answers:** `solve rs1 before reuse_prev` (then `rs1` is chosen first and reuse happens only when it matches `prev.rd`: about 1 in 7 under the soft pool); no `solve` at all (probability follows solution counts instead of the weights).

## Self-review checklist

- [x] No UVM config or ports; this is an object class (`uvm_object_utils`, name-only constructor, `super.new(name)`).
- [x] Every `prev.<field>` in a constraint is inside the guard `(prev != null) -> ...`.
- [x] The subclass only adds constraints; base legality (`c_align`, `c_csr`, `c_unused_rd`) untouched.
- [x] `reuse_prev` and `rs1` are `rand`, as `solve before` requires.
- [x] `prev` is a plain handle set by the sequence before `randomize()`.

## Expected log (hand-derived, not simulated)

Not a logged exercise. Properties: first instruction → `randomize()` returns 1 and `reuse_prev == 0`; after an instruction with `rd != 0`, about 70% of items have `reuse_prev == 1` and `rs1 == prev.rd`; after a store or branch (`prev.rd == 0`), `reuse_prev == 0` always.

## The result that matters

Constraints that mention other objects need a *guard*, and a knob whose cases have different numbers of solutions needs `solve before` to keep its weights. Variation to try: add a second knob `reuse_rs2` and decide which of `reuse_prev`, `reuse_rs2` must be solved first if you want them independent.
