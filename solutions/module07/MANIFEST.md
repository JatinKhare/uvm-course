# Module 07 — MANIFEST

## Concepts taught
Constraint layers (legality / preference / distribution / scenario); `dist` (`:=` vs `:/`, weights renormalised over feasible
values); `solve before` (changes probability, not legality; worked counts 26,627 pairs); implication, `inside`, `unique`,
`foreach`, `randc`, `soft`, guard constraints; switches (`with`, `rand_mode`, `constraint_mode`, `local::`); layered sequences
(`start(sequencer, parent)`); generating legal, terminating, hazard-rich programs; random stability, `srandom`,
`$get_initial_random_seed()`, logging seed and stream for replay.

## UVM classes/macros introduced
No new UVM classes; `seq.start(sequencer, parent_sequence)`, `m_sequencer`. (Randomisation features are SystemVerilog.)

## Shared names defined (module07/example01.sv, example02.sv)
- `package mcpu_rand_pkg`, `package mcpu_stream_pkg`. Compile pattern: include M03 example01 with `MCPU_NO_TOP`.
- `class mcpu_mix_item extends cpu_instr_item` — opcode mix 40 (ALU R-type, 10 each) / 20 ADDI / 15 LW / 15 SW / 5 BEQ / 5 CSRRW via `dist`,
  `solve op before imm`. Intended to be installed by factory override of `cpu_instr_item`.
- Burst/scenario sequences (all `uvm_sequence#(cpu_instr_item)`): `mcpu_alu_burst_seq` (`rand int unsigned n` 1..6, `rand bit hazard`),
  `mcpu_sw_lw_burst_seq` (`rand bit [4:0] base_reg` 1..7, `rand bit [11:0] off` aligned), `mcpu_branch_seq` (forward BEQ, imm 2..16),
  `mcpu_stream_seq` (`rand int unsigned n_alu` 1..6, `rand bit hazard`; body runs ALU burst, SW/LW pair, branch as children).
- Teaching only: `mcpu_rec_driver` (records items in `seen[$]`), `mcpu_rand_test`, `mcpu_stream_test`, `mcpu_hazard_item` / `mcpu_bad_mix_item` (exercise-local).
- Conventions: generated programs use forward-only branches; every `randomize()` result is checked; seed and generated stream are logged at the start of a run.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | guard constraint for a null previous-item handle; `solve reuse_prev before rs1` |
| exercise02.md | debug | 2 bugs | `:=` on a range (total weight 220 vs 100); `solve imm before op` (83.5% ALU, LW/SW 1.7%, no CSRRW) |
| exercise03.md | design | n/a | rare-opcode guarantee via `solve before`; termination proof; replay from a logged stream |

## Forward references made
Functional coverage of opcodes, hazards and distances (M08); constrained CSR access via the register layer (M09);
seed logging, regression and failure replay, interrupt/exception stimulus (M10).
