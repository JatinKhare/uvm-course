# Module 07 — Constrained Random & Sequence Strategies

> Prerequisites: Modules 01–06 (items and sequences from Module 03, the ISS-based scoreboard from Module 06 that makes random programs self-checking).
> What this module gives you: the constraint patterns that matter for CPU stimulus, how `dist` and `solve before` really change what you get, how to layer sequences into an instruction-stream generator that produces legal, terminating, hazard-rich programs, and how to make random runs reproducible.

UVM 1.2 only; the randomisation rules are SystemVerilog (IEEE 1800). Random values cannot be hand-traced, so the examples check **properties** and the arithmetic is done in the text. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Writing every test program by hand is like writing every possible sentence by hand. Instead, build a **random sentence generator that obeys grammar**:

| Generator | CPU testing |
|---|---|
| **Grammar** (no nonsense sentences) | **legality constraints** — aligned loads, valid CSR numbers |
| **Topic** ("write about hazards today") | **scenario constraints** — this test wants back-to-back dependent instructions |
| **How often each word appears** | **distribution** — more ADDs than branches |
| **A teacher who marks the result** | the **ISS scoreboard** from Module 6 — so we never need to know the answer in advance |

Because the marker works out the right answer itself, the generator is free to produce *any legal* program. The craft of this module is steering the dice: making rare things (CSR instructions) show up **often enough**, making programs **end**, and being able to **replay** a failing program.


### Why constrained random for a CPU

A CPU's state space (instruction mix × register choices × hazards × memory addresses × interrupt timing) is far larger than any directed list. With the ISS-based scoreboard of Module 06 the expected result of **any** legal program is computed automatically, so random programs are free to generate. The engineering problem moves to the constraints: they must make the program **legal** (the DUT must be allowed to run it), **terminating**, and **interesting** (hit hazards and corners often enough).


### Constraint layers (recap and extension of Module 03)

| Layer | Purpose | Where | CPU example |
|---|---|---|---|
| Legality | the DUT is only specified for legal input | item (hard) | LW/SW offset aligned; CSR address in the valid set |
| Preference | sensible default, overridable | item, `soft` | registers x1..x7 (small pool = frequent reuse = hazards) |
| Distribution | how often each case is chosen | item or config-driven | opcode mix 40/20/15/15/5/5 |
| Scenario | the situation this test wants | sequence / inline `with` | "SW then LW to the same address" |

Rule of thumb: **never weaken a legality constraint to make a scenario work**; switch it off explicitly (`constraint_mode(0)`) only for deliberate negative tests (misaligned access that should trap).


---

## UVM Mechanics

### `dist`: weights, and `:=` versus `:/`

**In plain words:** you are handing out servings. `:=` gives **every guest in the group a full serving**; `:/` gives the **group one serving to share**. A group of 4 with weight 40: `:=` → 160 in total, `:/` → 40 in total. One character, a very different party.

`x dist { v := w, [a:b] := w, [a:b] :/ w }`. For a **range**, `:=` gives *each* value the weight `w`; `:/` divides `w` **among** the values of the range. Toy example `x dist { 1 := 10, [2:4] := 10 }`: total weight 10 + 3·10 = 40, so P(1) = 25% and each of 2, 3, 4 also 25%. With `:/` for the range: total 10 + 10 = 20, P(1) = 50% and each of 2, 3, 4 is 50%/3 ≈ 16.7%.

The opcode mix in `example01.sv` uses `[OP_ADD:OP_OR] :/ 40` so the four R-type ALU opcodes share 40%. Writing `:= 40` would give each of them weight 40: total weight 160 + 20 + 15 + 15 + 5 + 5 = 220, so ALU R-type would be 160/220 = **72.7%**, ADDI 9.1%, LW and SW 6.8% each, BEQ and CSRRW 2.3% each. One character changes the whole test.

`dist` is a *weight*, not a guarantee: other constraints can make a value impossible, and then the remaining weights are renormalised among feasible values.


### `solve ... before`

**In plain words:** choosing a dish and a plate. If you **pick the plate first** and rare dishes fit very few plates, rare dishes almost never get picked. If you **pick the dish first**, every dish gets its fair turn, then you find a plate that fits. `solve op before imm` means "choose the opcode first". It never changes *which* meals are possible — only how often each appears.

`solve a before b;` does **not** change which solutions are legal; it changes their **probabilities**: `a` is picked first (using its own weights and ignoring how many `b` values each choice leaves), then `b` is solved given `a`. Counting only the `(op, imm)` pairs of `cpu_instr_item`: ADD, SUB, AND, OR, ADDI and BEQ allow all 4096 immediates (6 × 4096 = 24,576 pairs); LW and SW allow only 1024 aligned ones each (2,048); CSRRW allows 3. Total 26,627.

| | P(CSRRW) | P(LW) | P(ADD) |
|---|---|---|---|
| No `solve before`, uniform over legal pairs | 3 / 26,627 ≈ **0.011%** | 1,024 / 26,627 ≈ 3.8% | 4,096 / 26,627 ≈ 15.4% |
| `solve op before imm`, op uniform over 9 | **11.1%** | 11.1% | 11.1% |

The same effect explains why CSR instructions "never appear" in random tests: the solver is not biased against them, they simply own almost no solutions. `solve before` is how you give each *case* a fair share. The reverse (`solve imm before op`) makes `imm` uniform first, so LW/SW appear only when the picked `imm` happens to be aligned (25%) and CSRRW only when it hits one of three values.


### Other patterns

- **Implication** `a -> b` and `if/else` constraints: scenario-dependent legality (`op == OP_LW -> imm[1:0] == 0`).
- **`inside`** for sets and ranges; `!inside` for exclusions.
- **`unique {a, b, c}`** forces different values (e.g. three distinct source registers).
- **`foreach` over arrays** for constraints over a block of instructions.
- **`randc`**: cyclic (permutation) randomisation; use only on small fields (a 5-bit `randc` cycles through 32 values before repeating).
- **Guard constraints** (SystemVerilog 2012): a handle in a constraint must not be null; write `(h != null) -> (...)` / `(h == null) -> ...` so the solver evaluates the guard first. Needed when a constraint refers to the *previous* item in a stream.
- **`soft`**: dropped when it conflicts with a hard constraint.


### Switches

| Switch | Effect | Use |
|---|---|---|
| `obj.randomize() with { ... }` | adds constraints for this call | per-instruction scenario |
| `obj.field.rand_mode(0)` | field becomes a constant (not solved) | pin a field; **also silently constrains others** (Module 03 pitfall) |
| `obj.constraint_name.constraint_mode(0)` | switch one constraint off | negative tests |
| `local::name` | refer to the enclosing scope inside `with` | when item and sequence share a field name |


### Layered sequences

`seq.start(sequencer, parent_sequence)` runs a **child** sequence on the same sequencer inside the parent's `body()`. Layering: *item* (one instruction) → *burst sequence* (a pattern: ALU chain, SW/LW pair, branch) → *scenario sequence* (a mix of bursts) → *test* (picks and pins the scenario). Knobs are `rand` fields of the sequences; tests pin them with inline constraints (`seq.randomize() with { n_alu == 4; }`); `local::` resolves name clashes when a parent forwards its knob to a child. Virtual sequences (Module 03) add multiple interfaces on top.


### Generating legal, terminating, interesting programs

| Concern | Technique |
|---|---|
| Termination | branches only **forward** (positive offsets); no unbounded loops; a fixed-length stream with an end marker |
| Memory legality | base register set once by an `ADDI`, offsets aligned, addresses inside the preloaded region |
| Hazard density | small register pool; a knob (`hazard`) that makes an instruction read the previous destination |
| Writes to `x0` | avoid in producers (`rd != 0`) so a hazard is real |
| Self-checking | the ISS (Module 06) predicts the results; no hand-written expectations |
| Rare opcodes (CSR, branch) | `dist` weights and `solve before`, not luck |


### Seeding and reproducibility (**SIMULATOR/VERSION-DEPENDENT** in the command line)

SystemVerilog has **random stability**: each thread and each class object has its own random number generator, seeded from its creator; adding a `randomize()` call in one place does not (normally) disturb the stream elsewhere. The *initial* seed comes from the simulator (each tool has its own option). `obj.srandom(seed)` re-seeds one object; the system function `$get_initial_random_seed()` returns the run's seed so you can log it. Reproducing a failure needs: the same seed, the same code, and the same tool version. Robust practice: **log the seed at time 0** and **log the generated stream** (or save it to a file) so a failing program can be replayed as a directed test even if code changes alter the random sequence.


---

## Code Walkthrough

**How to read the two examples:** random values can't be predicted, so both tests check **properties that must always hold** ("no illegal item in 500 tries", "stream length is 7"). `example01.sv` = the *switches* (dist, solve, rand_mode, constraint_mode, seed). `example02.sv` = a *generator built in layers* (item → burst → scenario). Read the "Expected log" comment at the bottom of each file first.


### 1. Mix item and solve order (`example01.sv`)

```systemverilog
class mcpu_mix_item extends cpu_instr_item;
  constraint c_mix   { op dist { [OP_ADD:OP_OR] :/ 40, OP_ADDI := 20, OP_LW := 15, OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5 }; }
  constraint c_order { solve op before imm; }
```

Derived from the Module 03 item, so every legality constraint (`c_align`, `c_csr`, `c_unused_rd`) still applies; the subclass only adds *distribution* and *ordering*. Tests obtain it via a factory override (Module 02) without touching sequences.


### 2. Property checks instead of values

The test cannot print random values and expect them, so it checks properties: 500 mix items → `illegal_items=0`; 200 items with `with { op inside {OP_LW, OP_SW}; }` → none outside LW/SW; the output lines are listed at the end of the example file.


### 3. Switches in action

- `base.imm.rand_mode(0); base.imm = 12'h123;` — `imm` becomes the constant `0x123` (low bits `11`), so `c_align` makes LW/SW unsatisfiable and `c_csr` makes CSRRW unsatisfiable; the generated opcodes are only ADD, SUB, AND, OR, ADDI, BEQ: the **constant pruned the opcode space**.
- `a.c_align.constraint_mode(0)` — switching one legality constraint off allows `LW` with `imm = 1` (a deliberately misaligned load, useful for an exception test); the first `randomize()` with the constraint on returns 0, the second returns 1.
- `srandom(1234)` on two objects → identical items (`compare()` returns 1).


### 4. Layered stream generator (`example02.sv`)

`mcpu_stream_seq` (scenario) runs three bursts as children:

```systemverilog
alu.randomize() with { n == local::n_alu; hazard == local::hazard; };
alu.start(m_sequencer, this);                 // ALU burst, with optional hazard chain
mem.start(m_sequencer, this);                 // SW then LW to the same address
br.start(m_sequencer, this);                  // one forward BEQ
```

`alu` has its own field called `hazard`, so the parent's knob is written `local::hazard`. Inside the ALU burst, `if (idx > 0 && hazard) { rs1 == prev_rd; }` is a constraint that reads the *previous* item's destination from a local variable: this is the way to build dependent streams without a handle in the item.


### 5. What the test checks

With `n_alu` pinned to 4 and `hazard` to 1: stream length 7; items 0–3 ALU ops with `rd != 0` and `rs1(i) == rd(i−1)`; item 4 is SW, item 5 LW with identical `rs1` and `imm`; item 6 is a forward BEQ (`imm` in 2..16, i.e. 4–32 bytes ahead). Two `mcpu_stream_seq` objects seeded with 42 choose identical knobs.


---

## Common Pitfalls

- **`:=` on a range when `:/` was meant** → class shares come out wrong (ALU R-type 72.7% instead of 40%) while every item is legal → each value of a `:=` range gets the full weight; use `:/` to split.
- **`solve ... before` in the wrong direction, or missing** → a rare opcode (CSRRW) practically never generated; coverage hole that no amount of simulation fills → probability follows solution counts; choose the *case* first (`solve op before imm`).
- **Non-`rand` field in a constraint** → it acts as a constant and prunes other variables (CSR opcodes disappear) with no message → mark every field that must vary `rand`.
- **Name clash inside `with { }`** (`hazard == hazard`) → constraint is trivially true; "pinned" knob stays random → use `local::` or distinct names.
- **Randomisation failure ignored** → stale or default items flow through (identical NOP-like instructions) → check every `randomize()` and `uvm_error` on 0.
- **Backward or unbounded branches** → generated program loops forever or leaves the program image → forward-only offsets and a fixed-length stream.
- **Stream constraint refers to a null previous item** → randomisation failure or tool error on the first item → guard (`prev != null`) or use a local variable as in the example.
- **Seed not logged** → an intermittent failure cannot be reproduced → log `$get_initial_random_seed()` and the generated stream at the start of every run.


---

## Interview Angle

**Q1. What does `solve before` do and why would you use it?**
It orders the solving, changing the probability distribution but not the set of legal solutions. Use it when one variable's number of legal completions skews another's frequency — e.g. choose the opcode first so CSR instructions, which have only a handful of legal immediates, are not starved.

**Q2. `:=` versus `:/` in `dist`?**
For a range, `:=` gives each value the stated weight, `:/` splits the weight across the range. With `:=` a four-opcode range of weight 40 totals 160, not 40.

**Q3. How do you generate random programs that are legal and terminate?**
Legality constraints in the item (alignment, valid CSRs, base register setup), forward-only branches, fixed length plus an end marker, addresses inside the preloaded region; the ISS-based scoreboard supplies the expected results so no hand-written expectations are needed.

**Q4. How do you increase the chance of hazards?**
Small register pool, a `hazard` knob making an instruction reuse the previous destination, back-to-back dependent patterns (producer/consumer pairs, SW then LW to the same address), and weights favouring ALU/load/store.

**Q5. A random test failed once in a regression. How do you reproduce it?**
Re-run with the logged seed, same tool and code; if code changed, replay the logged instruction stream as a directed program. This is why the seed and the stream are logged at the start.

**Q6. What is random stability?**
Each thread and object has an independent RNG seeded from its parent, so adding or removing a `randomize()` call elsewhere does not change an unrelated stream. It is what makes `srandom` and seed-based reproduction work.

**Q7. How do tests customise the generator without editing it?**
Inline `randomize() with` on sequence knobs, config objects, and factory overrides (an item subclass with a different distribution), while legality constraints stay untouched in the base item.


---

## Recap in five lines

1. **Legality** in the item, **scenario** in the sequence, **intent** pinned by the test.
2. `:=` per value, `:/` shared across a range — check the **total weight**.
3. `solve A before B` changes **probabilities**, not what is legal; use it to give rare cases a fair share.
4. Programs must be **legal, terminating (forward branches), and replayable** (log the seed and the stream).
5. Always check `randomize()`; a non-`rand` field is a **constant** that silently prunes the rest.

**Questions beginners often ask**
- *"Why never see CSR instructions?"* — they own very few legal solutions; choose the opcode first (`solve before`).
- *"Why are my percentages wrong?"* — total the weights; look for `:=` where you meant `:/`.
- *"How do I reproduce a failure?"* — same seed, same code, same tool; and keep the logged instruction stream to replay directly.


---

## Check Your Understanding

1. The opcode distribution is written `[OP_ADD:OP_OR] := 40, OP_ADDI := 20, OP_LW := 15, OP_SW := 15, OP_BEQ := 5, OP_CSRRW := 5`. What are the actual probabilities of R-type ALU, ADDI, LW and CSRRW? What do you change to get 40/20/15/5?
2. Without any `dist` and without `solve before`, and counting only `(op, imm)` pairs as in the lesson, what is P(SW)? What is it with `solve op before imm`?
3. In `example02.sv` the test pins `n_alu == 4` and `hazard == 1`. Give the stream length, the position and opcode of each item, and explain why the inner constraint can read `prev_rd` and `hazard` without `local::`.

Answers: `solutions/module07/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | An item with a "reuse the previous destination" knob: `dist`, a null-guarded constraint, and `solve before`. Subtle null-handle trap on the first instruction. |
| `exercise02.md` | Debug the testbench | A mix that comes out 73% ALU, and CSRRW instructions that never appear. |
| `exercise03.md` | Design | Design a hazard-heavy random instruction-stream generator: layers, knobs, termination, memory legality, reproducibility. |


---

## Reference

**Classes:** `uvm_sequence#(REQ)`, `uvm_sequence_item`, `uvm_sequencer#(REQ)`, `uvm_driver#(REQ)`, `uvm_object` (`compare`).

**SystemVerilog randomisation:** `rand`, `randc`, `constraint`, `dist` (`:=`, `:/`), `solve ... before`, `soft`, `unique`, `foreach`, `inside`, implication, `if/else` constraints, `randomize() with {}`, `local::`, `rand_mode()`, `constraint_mode()`, `srandom()`, `$get_initial_random_seed()`, guard constraints.

**UVM methods:** `seq.start(sequencer, parent_sequence)`, `m_sequencer`, `start_item`, `finish_item`, `type_id::create`.

**Forward references made:** functional coverage of the generated opcodes, hazards and distances (Module 08); constrained CSR writes through the register layer (Module 09); seed logging, regression and failure replay (Module 10).
