# Module 08 — Functional Coverage

> Prerequisites: Modules 01–07 (monitors and analysis ports from Modules 04–05, the retire stream from Module 06, the constrained-random generator from Module 07).
> What this module gives you: how to turn a verification plan into covergroups, where to sample, how coverage percentages are computed (so you can derive them by hand), how to drive a closure loop, and how assertions and coverage complement each other.

UVM 1.2 plus SystemVerilog covergroups and assertions. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Think of a **driving test checklist**: roundabout ✔, parallel parking ✔, hill start ✘ … **Functional coverage is that checklist for the chip**: a list of situations you promised to try, ticked off as they really happen. *Code coverage* is different — it only says which roads the car drove on (which lines of hardware ran).

Two warnings follow from the analogy:
- Ticking every box does **not** mean the driver drives well. A fully ticked checklist with a broken marking scheme (scoreboard) proves nothing.
- You must tick boxes for what **actually happened**, so you sample from the **monitor** (camera footage), not from the driver (your intentions).


### Two meanings of "coverage"

| Kind | Measures | Source | Answers |
|---|---|---|---|
| **Code coverage** (line, branch, toggle, FSM) | which RTL was executed | the simulator, automatically | "Did the stimulus reach this logic at all?" |
| **Functional coverage** | which *scenarios from the verification plan* happened | **you write** covergroups | "Did we exercise the situations the spec cares about?" |

Both are necessary and neither proves correctness. Coverage says *what happened*; checkers (scoreboard, assertions) say whether it was *right*. A test can reach 100% functional coverage with a broken scoreboard and report nothing.


### From plan to covergroup

Coverage is derived from the **verification plan**, not from the code. For a CPU, a plan item becomes one or more coverpoints:

| Plan item | Coverpoint / cross |
|---|---|
| "every instruction class executes" | opcode class bins |
| "data hazards at every producer–consumer distance" | RAW distance bins (none, 1, 2, 3) |
| "every instruction class meets every hazard distance" | cross (class × distance) |
| "loads and stores to every memory region, aligned and misaligned" | address region × alignment × direction |
| "interrupt arrives in every pipeline situation" | interrupt × instruction class at the boundary |
| "reset behaves correctly in every state" | reset-asserted × last instruction class |

Rule: **choose bins so each one corresponds to a statement you could write in the plan.** Auto-bins on a 32-bit field (default: at most 64 equal ranges) are almost never meaningful.


---

## UVM Mechanics

### Covergroup anatomy (SystemVerilog; used inside UVM classes)

```systemverilog
covergroup cg;
  option.per_instance = 1;
  cp_class: coverpoint cls { bins r = {C_R}; bins lw = {C_LW}; ignore_bins other = {C_OTHER}; }
  cp_dist : coverpoint dist { bins none = {D_NONE}; bins d1 = {D1}; }
  x_cd    : cross cp_class, cp_dist;
endgroup
```

| Element | Meaning |
|---|---|
| `coverpoint expr` | a value to track; its **bins** are the buckets that count |
| `bins name = {values/ranges}` | one bin per name (several values may share a bin) |
| `bins b[] = {[a:b]}` | one bin **per value** in the range (array bins) |
| `bins t = (a => b)` | **transition** bin: value `a` followed (at the next sample) by `b` |
| `wildcard bins` | bins with don't-care bits |
| `ignore_bins` | excluded from the coverage calculation (use for combinations that are impossible/irrelevant; document why) |
| `illegal_bins` | hitting one is a **run-time error** (a checker that is also excluded from the calculation) |
| `bins x = default` | catch-all; **never counts toward coverage** |
| `cross a, b` | all combinations of the coverpoints' bins; `binsof(cp.bin)` and `intersect` select subsets for `ignore_bins`/`illegal_bins` |
| `option.at_least` / `weight` / `goal` | hits needed per bin / relative weight / target percentage |

**Sampling.** A covergroup counts when it is *sampled*: by a clocking event in its header (`covergroup cg @(posedge clk)`) or by an explicit `cg.sample()` call. In UVM the explicit call, made from a subscriber's `write()` after the values are set, is the norm.

An **embedded covergroup** (declared inside a class) must be constructed with `cg = new();` **in the class constructor**; calling `sample()` on a null covergroup handle is a run-time error.


### The numbers (so you can derive them)

**In plain words:** a coverpoint is a **row of boxes**; coverage is *boxes ticked ÷ boxes in the row*. A row of 6 boxes with 4 ticked = 66.7%. A cross is a **grid** (6 × 4 = 24 boxes). The whole group is the **average** of its rows and grids.

- **Coverpoint coverage** = bins hit / total bins (counted bins only: `ignore_bins`, `illegal_bins` and `default` are not in the count).
- **Cross coverage** = cross bins hit / (product of the coverpoints' counted bins, minus ignored cross bins).
- **Covergroup coverage** = weighted average of its coverpoints and crosses (default weight 1 each).
`cg.get_inst_coverage()` (with `option.per_instance = 1`) and `cp.get_inst_coverage()` return these as percentages.

Example: 6 class bins, 4 distance bins, one cross of 24 bins; samples hit 4, 2 and 4 of them → (4/6 + 2/4 + 4/24)/3 = (66.7 + 50 + 16.7)/3 = 44.4%.


### Where to sample

| Sample from | Measures | Verdict |
|---|---|---|
| **Monitor / subscriber** (retire stream, bus monitors) | what the DUT actually did | **correct** |
| Driver | what the testbench tried to do | misleading: stimulus that the DUT dropped or reordered is counted |
| Sequence / item randomisation | what was *generated* | useful as a **stimulus** report, never as closure evidence |

Sample once per transaction, after all fields are assigned. Sampling during reset or before data is valid inflates coverage.


### Coverage closure

1. **Plan** → coverpoints/crosses; **justify** each `ignore_bins`/`illegal_bins`.
2. **Run** a broad random regression (many seeds).
3. **Merge** coverage databases from **passing** runs only (a failing run's coverage cannot be trusted).
4. **Analyse holes**: which bins never hit, and is each *reachable*?
5. **Close**: bias constraints/`dist`/`solve before` (Module 07) toward the holes, or write directed tests; exclude only with a written reason.
6. **Sign off** with checkers passing and coverage at goal. 100% with a blind scoreboard is not sign-off.

Crosses are the hard part: the number of bins is the product, so a 6×4 cross has 24 holes to close while the one-dimensional coverpoints close almost immediately (`example02.sv`).


### Assertions versus coverage

| | Assertion (SVA `assert property`) | Functional coverage |
|---|---|---|
| Question | "is the rule always obeyed?" | "did the situation ever occur?" |
| Result | fails loudly when violated | silent; produces counts |
| Cycle-level timing | yes | at transaction level (or cycle level with `cover property`) |
| Pass means | rule held *in what was exercised* | nothing about correctness |

They need each other: an assertion with an antecedent that never fires **passes vacuously**. Pair each assertion with a `cover property` on its antecedent:

```systemverilog
a_rvalid_has_req : assert property (@(posedge clk) disable iff (!rst_n) if_rvalid |-> if_req);
c_rvalid_seen    : cover  property (@(posedge clk) disable iff (!rst_n) if_rvalid);
a_retire_known   : assert property (@(posedge clk) disable iff (!rst_n)
                                    retire_valid |-> !$isunknown({retire_pc, retire_instr}));
c_back_to_back   : cover  property (@(posedge clk) disable iff (!rst_n) retire_valid ##1 retire_valid);
```

Use assertions for low-level protocol/pipeline rules close to the RTL (and in formal tools); use the scoreboard for architectural results; use covergroups for scenario space.


---

## Code Walkthrough

**How to read the examples:** `example01.sv` = one covergroup fed with the Module 6 program; the numbers (66.7 / 50.0 / 16.7 → 44.4) are derived by hand at the bottom of the file — **derive them yourself first, then compare**. `example02.sv` = the closure loop: three programs, each written *after* looking at the holes left by the previous one.


### 1. A coverage model for the retire stream (`example01.sv`)

`mcpu_instr_cov` is a `uvm_subscriber#(mcpu_retire_txn)`: the retire monitor's analysis port feeds `write()` (Module 05). Per retired instruction it computes two values and samples once:

- `cls` — the instruction class decoded from `instr[6:0]` (R-type, ADDI, LW, SW, BEQ, CSRRW; anything else is `C_OTHER`, ignored);
- `dist` — the distance (1..3, or none) to the **nearest** earlier instruction that wrote a register this instruction reads (using a three-entry history of destination registers; `x0` is never a producer or a source).


### 2. The covergroup

```systemverilog
cp_class: coverpoint cls { bins r = {C_R}; bins addi = {C_ADDI}; bins lw = {C_LW};
                           bins sw = {C_SW}; bins beq = {C_BEQ}; bins csr = {C_CSR};
                           ignore_bins other = {C_OTHER}; }
cp_dist : coverpoint dist { bins none = {D_NONE}; bins d1 = {D1}; bins d2 = {D2}; bins d3 = {D3}; }
x_class_dist: cross cp_class, cp_dist;      // 24 bins
```

`cg = new();` is in the constructor; the test calls `cov.write(t)` to stand in for the monitor.


### 3. Derive the numbers

For the Module 06 program the samples are `(ADDI,none) (ADDI,none) (R,d1) (SW,d1) (LW,none)`. The ADD reads `x1` (two back) and `x2` (one back): the nearest producer is one back → `d1`. The SW reads `x3` (one back). The LW reads `x4`, never written. Bins hit: class 4/6, dist 2/4 (`none`, `d1`), cross 4/24 → **66.7 / 50.0 / 16.7**, covergroup **44.4%**.


### 4. A closure loop (`example02.sv`)

| After | class | dist | cross | total |
|---|---|---|---|---|
| A: the Module 06 program | 66.7 | 50.0 | 16.7 | 44.4 |
| B: + ADDI chain, ADD/BEQ at distance 2, LW at distance 3 | 83.3 | 100.0 | 29.2 | 70.8 |
| C: + CSRRW at distance 1 | 100.0 | 100.0 | 33.3 | 77.8 |

Each phase was written **after reading the holes** left by the previous one. One-dimensional coverage closes after three short programs; the cross sits at 8/24 and shows why closure needs weighted random plus targeted tests: of the remaining 16 combinations, some are reachable with the Module 07 generator (`hazard` knob, `mcpu_mix_item` weights) and some may be genuinely impossible (to be excluded **with a written reason**).


### 5. What this model does *not* tell you

100% here would still say nothing about whether results were right. That is the scoreboard's job (Module 06), and the two are only trustworthy together.


---

## Common Pitfalls

- **Covergroup never constructed** (`cg = new()` missing in the constructor) → run-time null-handle error at the first `sample()` (wording tool-specific) → construct embedded covergroups in `new`.
- **Sampling in the driver or from sequence items** → 100% coverage for scenarios the DUT never executed (dropped, reordered, or killed by reset) → sample from monitors.
- **Sampling before the fields are set** (or twice per transaction) → each bin is hit with the *previous* transaction's values, or transitions/crosses double-count → assign, then `sample()` exactly once.
- **`default` bin used as a safety net** → coverage reads 100% while the interesting values land in the uncounted default → name the interesting values; use `illegal_bins` for the forbidden ones.
- **Over-broad `ignore_bins`** (an entire class of crosses) → the hole is hidden and can never be closed → ignore only provably impossible combinations, with a comment.
- **Auto-bins on wide fields** → dozens of equal-range bins that mean nothing → explicit bins from the plan.
- **Cross explosion** → thousands of bins nobody can close → cross only coverpoints that interact, and cut the bins of each.
- **Merging coverage from failing tests** → closure claimed on behaviour that was not verified → merge passing runs only.
- **`per_instance` not set** → `get_inst_coverage()` reports a type-wide number across all instances (tool-specific detail) → set `option.per_instance = 1`.


---

## Interview Angle

**Q1. Code coverage versus functional coverage?**
Code coverage measures which RTL was executed, automatically; functional coverage measures which plan scenarios occurred and is written by hand. Code coverage can be 100% while key scenario combinations are missing, and vice versa.

**Q2. Explain coverpoint, bins, cross.**
A coverpoint tracks a value; bins are the buckets that count hits (explicit values, ranges, transitions); a cross tracks combinations of coverpoints' bins. Coverage is hit bins over total counted bins.

**Q3. What would you cover for a CPU pipeline?**
Instruction classes, hazard types and distances (RAW at 1/2/3, load-use), branch taken/not-taken and distance, memory access region/alignment/size, exception and interrupt cases against pipeline state, reset at different times, CSR access patterns; and crosses of the ones that interact.

**Q4. Where do you sample, and why not in the driver?**
In monitors/subscribers: coverage must reflect what the DUT did. A driver-based model counts stimulus that may never have been executed.

**Q5. `ignore_bins` versus `illegal_bins` versus `default`?**
`ignore_bins` removes values from the calculation (documented impossibilities); `illegal_bins` removes them and raises an error if hit; `default` is a catch-all that doesn't count towards coverage, so it can hide problems.

**Q6. Describe the closure loop.**
Plan, random regression, merge passing runs, analyse holes, bias constraints or write directed tests for reachable holes, justify and exclude unreachable ones, repeat until goal.

**Q7. How do assertions and coverage differ, and why pair them?**
Assertions check rules (fail on violation), coverage records occurrence. An assertion whose antecedent never happens passes vacuously; a `cover property` on the antecedent proves it was exercised.

**Q8. 100% functional coverage — are we done?**
No: coverage measures stimulus/scenario reach. We also need checkers that are proven able to fail, and review that the plan itself is complete.


---

## Recap in five lines

1. Functional coverage = a **checklist from the plan**; sample from **monitors**, once per observation.
2. Coverage % = **bins hit ÷ counted bins**; `default`, `ignore_bins`, `illegal_bins` are **not counted**.
3. One-dimensional coverage closes fast; **crosses** are the hard part (product of bins).
4. Close the loop: **plan → run → merge passing runs → analyse holes → target → repeat**.
5. Pair assertions with `cover property`; 100% coverage with a blind scoreboard is **not** sign-off.

**Questions beginners often ask**
- *"Why is my coverage 100% so early?"* — look for a `default` bin or a broad `ignore_bins`.
- *"Why sample in the monitor?"* — it records what the chip did, not what the testbench tried.
- *"Why did my embedded covergroup crash?"* — it must be built with `cg = new();` in the constructor.


---

## Check Your Understanding

1. In `example01.sv`, what are the nearest-producer distances for the five instructions, and why is the `ADD`'s distance 1 although it reads a register written two instructions earlier as well?
2. A covergroup has `cp_dist` with bins `none`, `near = {1,2}` and `far = default`. Samples contain distances 0, 1, 2 and 3. What is the coverage of `cp_dist`? Where does distance 3 go?
3. Derive the cross and covergroup coverage after phase B of `example02.sv` if `x_class_dist` had an additional `ignore_bins` removing the four `csr` combinations.

Answers: `solutions/module08/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Cover the load/store stream: direction, region, a transition bin, a cross. Traps: constructor, sampling order. |
| `exercise02.md` | Debug the testbench | A coverage model that reaches 100% on a handful of samples because of a `default` bin and an `ignore_bins`. |
| `exercise03.md` | Design | Write the coverage plan for CPU hazards and interrupts: bins, crosses, sampling points, closure strategy. |


---

## Reference

**Classes:** `uvm_subscriber#(T)`, `uvm_analysis_imp` (inside the subscriber), `uvm_component`, `uvm_object`.

**SystemVerilog coverage:** `covergroup`, `coverpoint`, `bins`, `ignore_bins`, `illegal_bins`, `default`, `wildcard bins`, transition bins `(a => b)`, `cross`, `binsof ... intersect`, `option.per_instance`, `option.goal`, `option.at_least`, `weight`, `sample()`, `get_inst_coverage()`, `get_coverage()`.

**SystemVerilog assertions:** `assert property`, `cover property`, `disable iff`, `|->`, `|=>`, `$past`, `$isunknown`.

**Forward references made:** register-field coverage (Module 09); coverage merge, regression, and sign-off criteria (Module 10).
