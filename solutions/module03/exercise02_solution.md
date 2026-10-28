# Module 03 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// cpu_instr_item: Bug B fix
rand bit [11:0] imm;

// mcpu_bad_seq.body: Bug A fix (and the result is now checked)
task body();
  cpu_instr_item it;
  repeat (3) begin
    it = cpu_instr_item::type_id::create("it");
    start_item(it);
    if (!it.randomize() with { op == OP_LW; imm == 12'h040; })
      `uvm_error("RAND", "randomize failed for LW")
    finish_item(it);
  end
endtask
```

## Bug A — contradictory inline constraint, hidden by `void'`

Two things make `randomize()` fail in the code as given:
1. `imm` is not `rand`, so it is a constant 0 during solving. `imm[1:0] == 2'b01` is then a constant-false constraint.
2. Even with `imm` made `rand`, `op == OP_LW` triggers the item's own `c_align` (`imm[1:0] == 2'b00`), which contradicts `imm[1:0] == 2'b01`. A LW offset must be word-aligned by legality, so the inline constraint asks for something the item forbids.

`randomize()` returns 0, **the item keeps its current values** (defaults: `OP_ADD`, all zeros) and `void'(...)` throws the result away, so the sequence happily sends the same all-zero ADD three times. The only evidence is the simulator's solver message.
**Fix:** ask for a legal value (`imm == 12'h040`, aligned) and check the return value. **Wrong fix:** deleting `c_align` — that removes a legality constraint to make a bad test pass.

## Bug B — `imm` is not declared `rand`

`imm` is a constant 0. In `c_csr`, `(op == OP_CSRRW) -> imm inside {0x300, 0x305, 0x341}` therefore evaluates to `(op == OP_CSRRW) -> 0`, i.e. `op != OP_CSRRW`: the constant silently prunes the opcode, so CSR instructions are never produced. All other items show `imm=0x000` because nothing randomises it. No failure message appears because the solver found valid solutions: a non-`rand` variable in a constraint is legal, merely not solved.
**Fix:** `rand bit [11:0] imm;`. **Proof:** the 200-item log contains `OP_CSRRW` with `imm` in `{0x300, 0x305, 0x341}`, and non-zero immediates elsewhere.
**Common wrong fix:** removing `c_csr` (hides the symptom of the missing `rand`, loses legality).

## Self-review checklist

- [x] No `config_db`; no ports.
- [x] `super.new` present in the (unchanged) constructors.
- [x] `start_item`/`finish_item` paired.
- [x] `randomize()` results checked (the `void'` cast removed).
- [x] No name clashes in `with` (`op`, `imm` are the item's own fields, intentionally).
- [x] All fields used in constraints that should vary are `rand`.

## Expected log (hand-derived, not simulated)

For `mcpu_bad_seq` after both fixes, three lines 10 ns apart. Registers vary by seed; `op` and `imm` are fixed:

```
@ t    [DRV] got OP_LW rd=x<1..7> rs1=x<1..7> rs2=x<1..7> imm=0x040 enc=0x04<...>
@ t+10 [DRV] got OP_LW ...                                  imm=0x040 enc=0x04<...>
@ t+20 [DRV] got OP_LW ...                                  imm=0x040 enc=0x04<...>
```

(`enc` begins `0x040` because the `imm` field occupies bits [31:20]; the low bits depend on `rs1` and `rd`, and the opcode field is `0000011`.) `rs2` is printed but unused by LW.

## The result that matters

A variable that is not `rand` is not "unconstrained", it is **fixed**, and it constrains everything it appears in. Always grep a new item's fields for missing `rand`, and never discard the result of `randomize()`. Variation to try: make `rs1` non-`rand` and predict which hazard scenarios disappear.
