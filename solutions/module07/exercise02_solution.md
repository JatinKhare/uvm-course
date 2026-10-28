# Module 07 / Exercise 02 — Solution

## Full solution code

```systemverilog
class mcpu_mix_item extends cpu_instr_item;
  `uvm_object_utils(mcpu_mix_item)
  constraint c_mix   { op dist { [OP_ADD:OP_OR] :/ 40, OP_ADDI := 20, OP_LW := 15,
                                 OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5 }; }     // Bug 1 fix: :/
  constraint c_order { solve op before imm; }                                     // Bug 2 fix: op first
  function new(string name = "mcpu_mix_item");
    super.new(name);
  endfunction
endclass
```

## Bug 1 — `:=` on a range

`[OP_ADD:OP_OR] := 40` gives **each** of ADD, SUB, AND, OR the weight 40: the range contributes 160, not 40. Total weight = 160 + 20 + 15 + 15 + 5 + 5 = **220**. With the correct solve order that alone would give: ALU 160/220 = **72.7%**, ADDI 20/220 = 9.1%, LW 15/220 = 6.8%, SW 6.8%, BEQ 5/220 = 2.3%, CSRRW 2.3%. Fix: `:/ 40` splits 40 over the four values (10 each), total 100.

## Bug 2 — `solve imm before op`

`imm` is chosen **first**, uniformly over 4096 values, then `op` among the opcodes legal for that `imm`, weighted by `dist` (weights renormalised over the feasible ones).
- 75% of immediates are unaligned (`imm[1:0] != 0`): LW and SW are illegal; legal opcodes (CSRRW excluded since only 3 of 4096 immediates allow it): ALU 160 + ADDI 20 + BEQ 5 = **185** (with the buggy weights).
- 25% are aligned: legal opcodes ALU 160 + ADDI 20 + LW 15 + SW 15 + BEQ 5 = **215**.
Combined with the Bug-1 weights (which are still in the code):
- P(ALU) = 0.75·160/185 + 0.25·160/215 = 0.6486 + 0.1860 ≈ **83.5%**
- P(ADDI) = 0.75·20/185 + 0.25·20/215 = 0.0811 + 0.0233 ≈ **10.4%**
- P(BEQ) = 0.75·5/185 + 0.25·5/215 = 0.0203 + 0.0058 ≈ **2.6%**
- P(LW) = P(SW) = 0.25·15/215 ≈ **1.7%**
These match the symptoms (and sum to 100%).
**CSRRW:** legal only for `imm` ∈ {0x300, 0x305, 0x341}: probability 3/4096 ≈ 0.073% that `imm` allows it, times its conditional weight (5/220 ≈ 2.3%, or slightly more when only a few opcodes are feasible, ~2.6%): about 1.8·10⁻⁵, i.e. roughly 1 in 54,000 items. In 10,000 items, zero is the expected outcome.
**Fix:** `solve op before imm`: `op` is picked from its weights over the *feasible* set (all six classes are feasible: each has at least one legal `imm`), then `imm` is solved for it.

## After both fixes

With `:/ 40` and `solve op before imm`, every class is chosen with exactly its weight: R-type ALU 40% (10% each of ADD, SUB, AND, OR), ADDI 20%, LW 15%, SW 15%, BEQ 5%, CSRRW 5%. "Exact" holds because every opcode is feasible for at least one `imm`; legality constraints decide which immediates are available *after* the opcode is chosen, not how often the opcode is chosen.

## Automatic detection

A test (or a coverage collector, Module 08) that counts opcode classes over N items and fails when a class share leaves a tolerance band around its weight (for example ±3 standard deviations of the binomial). Also assert that every opcode class occurs at least once.

## Self-review checklist

- [x] Weights sum to 100 after the fix (40 split + 20 + 15 + 15 + 5 + 5).
- [x] `solve` ordering references `rand` variables only.
- [x] The subclass adds distribution/ordering only; legality stays in the base item.
- [x] Probabilities are derived, not guessed, and consistent with the symptoms.

## Expected log

Not applicable (the symptoms are the tallies; derivations above).

## The result that matters

Two silent distribution bugs compound: a weights bug (`:=` vs `:/`) and an ordering bug (`imm` before `op`). Nothing fails; every item is legal. The only defence is *measuring* the distribution. Variation to try: fix only Bug 1 (correct weights, `solve imm before op` still there) and recompute: unaligned immediates (75%) allow weights 40+20+5 = 65, aligned (25%) allow 95, so P(ALU) = 0.75·40/65 + 0.25·40/95 ≈ 56.7% and P(LW) = 0.25·15/95 ≈ 3.9%. Then fix only Bug 2 (`:=` kept, `solve op before imm`) and you get the 72.7% / 9.1% / 6.8% figures above.
