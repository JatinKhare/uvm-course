# Module 07 — Check Your Understanding: Answers

## 1. The `:=` mix

Total weight = 4·40 + 20 + 15 + 15 + 5 + 5 = **220** (the range gives each of four opcodes 40).
- R-type ALU: 160/220 = **72.7%**
- ADDI: 20/220 = **9.1%**
- LW: 15/220 = **6.8%** (SW the same)
- CSRRW: 5/220 = **2.3%** (BEQ the same)
(These are the probabilities with `op` solved first. With a different solve order they shift further; see Exercise 02.) To get 40/20/15/15/5/5 change the range to `:/ 40` (the four ALU opcodes share 40, ten each); total becomes 100. (The question's "40/20/15/5" lists ALU, ADDI, LW and CSRRW.)

## 2. P(SW) with and without `solve op before imm`

Counting `(op, imm)` pairs: 6 opcodes × 4096 + 2 × 1024 + 3 = 24,576 + 2,048 + 3 = 26,627.
- No `dist`, no `solve before`: uniform over solutions → P(SW) = 1,024 / 26,627 ≈ **3.85%**.
- With `solve op before imm` and a uniform `op` over the 9 opcodes: P(SW) = 1/9 ≈ **11.1%**.
The set of legal `(op, imm)` pairs is identical in both cases; only the probabilities change.

## 3. The stream in `example02.sv`

Length 4 + 2 + 1 = **7**:
- items 0–3: `ADD/SUB/AND/OR` with `rd != 0`; for i = 1..3, `rs1(i) == rd(i−1)` (hazard chain, because `hazard == 1`);
- item 4: `SW`; item 5: `LW`, with the same `rs1` (`base_reg`) and the same `imm` (`off`);
- item 6: `BEQ` with `imm` in 2..16 (a forward branch of 4–32 bytes).
Inside `it.randomize() with { ... }`, identifiers are looked up first among the fields of `it` (`cpu_instr_item`: `op`, `rd`, `rs1`, `rs2`, `imm`, ...). `prev_rd`, `idx` and `hazard` are not item fields, so they resolve to the enclosing scope (the burst sequence's local variable and field). `local::` is only needed when an item field has the same name — as in the scenario sequence, where `alu` (a sequence, not an item) has its own `hazard` field and the parent's must be written `local::hazard`.
