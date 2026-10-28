# UVM Course — Authoring Instructions for Claude

Copy this file into an empty `uvm-course/` repo as `AUTHORING_SPEC.md`. Claude reads it
before every module. Part 1 is the spec; Part 2 is the prompts the human pastes.

Derived from the CUDA course (24+ modules, ~$1,000 on Opus). That course's quality came
from its *structure* (lesson → example → exercise → solution, hard rules, manifests), not
from the recursion that made it expensive. This spec keeps the structure and drops the recursion.

---

# PART 1 — SPEC

## 0. Goal and audience

A **10-module UVM course for CPU-verification roles and interviews**. Reader has ~2+ years
in the domain: knows SystemVerilog basics, has seen a testbench. Covers the essentials
plus above-basic material: what an interviewer asks a mid-level DV engineer. Not an
encyclopedia.

Every module = **lesson → worked examples → exercises → solutions**.

## 1. The central constraint: nothing can be run

Unlike CUDA, no simulator is available. Therefore:

1. **Every API call, macro, phase name, and class must be real UVM 1.2 (IEEE 1800.2-2017).**
   Never invent a method, argument order, macro, or phase. If unsure whether something
   exists, do not use it. Prefer the well-known canonical form.
2. **Use only the canonical idioms** taught in the UVM Class Reference / Accellera user guide:
   `` `uvm_component_utils ``, `` `uvm_object_utils ``, `` `uvm_field_* `` (mention but avoid
   in production examples; show `do_copy/do_compare/convert2string`), `uvm_config_db#(T)::set/get`,
   `type_id::create`, `phase.raise_objection/drop_objection`, `uvm_analysis_port#(T)`,
   `uvm_tlm_analysis_fifo`, `uvm_sequence#(T)` with `start_item/finish_item`, `uvm_reg` etc.
3. **Examples are synthetic but must be plausible, complete and internally consistent**:
   every identifier used is declared; every `config_db::get` has a matching `set` with the same
   type and field name; every port is connected; every sequence item field used exists.
4. **Tag each non-trivial UVM construct in a lesson's code with a one-line "why"**, and keep a
   `## Reference` list at the end of the lesson naming the UVM classes/macros used
   (e.g. `uvm_driver`, `uvm_sequencer`, `uvm_analysis_imp`). This makes the human's spot check fast.
5. **Be honest about gaps.** Behaviour that is simulator-dependent or version-dependent
   (UVM 1.1d vs 1.2, vendor-specific `+UVM_*` plusargs, phase ordering corner cases) is labelled
   **SIMULATOR/VERSION-DEPENDENT**. Do not state it as universal.
6. **Expected simulation output is HAND-TRACED, not observed.** Label it
   `Expected log (hand-derived, not simulated)`. Keep traces short (≤ 25 lines), time stamps
   simple, and trace the real UVM message format: `UVM_INFO file(line) @ time: path [ID] msg`.
7. **Mark exercises that are SV/UVM-compile-checkable by inspection** and include a
   self-review checklist in the solution (see §6) instead of "PASS output".
8. **Never fabricate** tool outputs, coverage numbers, waveform data, or vendor behaviour.
   If a concrete number is needed, derive it arithmetically in the text.

Optional free check (human only, not required): paste examples into EDA Playground
(UVM 1.2, free Questa/VCS/Xcelium access) and report errors back. Claude must not assume this
was done.

## 2. Domain slant: CPU verification

All examples use a **small, fictional RISC-style CPU core** (call it `mini_cpu`: 32-bit,
simple in-order pipeline, instruction-fetch bus, load/store bus, interrupt line, CSR/register file).
Do not use any real company IP or a real ISA's full detail; RISC-V-flavoured mnemonics
(ADD, LW, SW, BEQ, CSRRW) are fine and encouraged since interviews use them.

Recurring CPU-DV themes to thread through modules: instruction stimulus & constrained-random
generation, reference model / ISS comparison, retire-trace scoreboarding, memory & bus protocol
agents (AXI-lite/AHB-like), exceptions/interrupts, register models (CSRs), functional coverage of
opcodes/hazards/corner cases, reset and debugging.

## 3. The 10 modules (fixed list — do not expand)

| # | Title | Core content |
|---|---|---|
| 01 | UVM Big Picture & Testbench Architecture | Why UVM; layered TB; `mini_cpu` DUT + interface; component/object split; first `uvm_test` + `run_test()` |
| 02 | Phases, Objections, Factory | build/connect/run phases (+ phase list), objections & drain time, factory, `type_id::create`, overrides (type & instance) |
| 03 | Transactions & Sequences | `uvm_sequence_item`, constraints, `rand`, instruction item, `uvm_sequence`, `start_item/finish_item`, `body()`, virtual sequences, p_sequencer |
| 04 | Driver, Sequencer, Monitor, Agent | driver–sequencer handshake (`get_next_item/item_done`), virtual interface, monitor, active vs passive agent, config object |
| 05 | Configuration & Connectivity | `uvm_config_db` (set/get, wildcard, scope pitfalls), interfaces via config_db, TLM (ports/exports/imps, analysis ports, FIFOs) |
| 06 | Scoreboard & Reference Model | analysis imps, in-order/out-of-order compare, predictor, ISS/retire-trace compare for `mini_cpu`, `do_compare` |
| 07 | Constrained Random & Sequence Strategies | constraint patterns, solve-before, dist, inline/randomize-with, layered/virtual sequences, instruction-stream generator, seeding & reproducibility |
| 08 | Functional Coverage | covergroups, coverpoints, bins, cross, sampling in monitor/subscriber, coverage closure strategy, assertions vs coverage |
| 09 | Register Abstraction Layer (RAL) | `uvm_reg`, `uvm_reg_block`, adapter, predictor, frontdoor/backdoor, built-in sequences, CSR model for `mini_cpu` |
| 10 | Debug, Environment Integration & Interview Capstone | env/test structure, reset & error injection, logging/verbosity, common bugs, regression thinking, capstone test plan + 25 interview Q&A |

If the user asks to change the list, update this table first, then proceed.

## 4. Directory layout — exact

```
uvm-course/
  AUTHORING_SPEC.md        <- this file
  PROGRESS.md              <- module status + one-line summaries (see §9)
  moduleNN-<slug>/
    README.md (the lesson)
    example01.sv
    example02.sv           (only if needed; 1–2 total)
    exercise01.md          <- exercise statement (+ skeleton code with TODOs inside)
    exercise02.md
    exercise03.md          (2–3 total)
  solutions/moduleNN/
    exerciseMM_solution.md <- full code + reasoning + checklist
    check_your_understanding.md
    MANIFEST.md
```

Nothing under `moduleNN-*/` reveals answers. Exercise skeletons are `.sv` code blocks
embedded in `exerciseNN.md` (one file per exercise keeps tooling simple), OR a separate
`exerciseNN.sv` if longer than ~80 lines — pick one convention at Module 01 and keep it.

## 5. `README.md` (the lesson) — mandatory headings, in order

```
# Module NN — <Title>
> Prerequisites: ...   > What this module gives you: <one sentence>
## Concept
## UVM Mechanics            (how the library actually does it: phases, base-class behaviour, what the macro expands to)
## Code Walkthrough         (quote fragments from exampleNN.sv inline and explain; never just "see file")
## Common Pitfalls          (5–8 bullets, each: bug → symptom in log → cause)
## Interview Angle          (4–6 questions an interviewer actually asks on this topic, with 2–3 line model answers)
## Check Your Understanding (2–4 reasoning questions; answers in solutions/)
## Exercises                (summary of each; no answers)
## Reference                (UVM classes/macros/methods used — see §1.4)
```

Length target: **250–400 lines per lesson** (CUDA lessons ran 600–1000; do not copy that).
Tone: precise, direct, no filler. Every term defined on first use. Label general rules
**PORTABLE UVM CONCEPT** and tool/version specifics **SIMULATOR/VERSION-DEPENDENT**.

## 6. Examples and exercises

**Examples** (1–2 per module, ≤ 150 lines each): complete, compile-consistent SV/UVM.
Include a header comment: module, what it demonstrates, which lesson section uses it.
End with the hand-traced expected log (§1.6).

**Exercises** (2–3 per module). Mix types, at least one non-fill-in per module:

1. **Fill-in** — skeleton with `// TODO n: ...` and `// YOUR CODE HERE`; 2–4 TODOs, one **subtle**
   (obvious answer is wrong: objection dropped too early, `config_db` path mismatch, `get_next_item`
   without `item_done`, missing `super.build_phase`, cross-bin sampling in the wrong place).
2. **Debug the testbench** — intentionally broken code, header states the *symptom* (e.g. "test ends
   at time 0", "scoreboard never receives items"), not the cause. Realistic UVM bugs only.
3. **Design** — given a CPU-DV requirement ("verify that LW after SW to same address forwards
   correctly"), reader designs the components/sequence/coverage; solution shows one reference design.
4. **Predict the log** — given code, reader predicts the UVM log/phase order.
5. **Interview write-up** — whiteboard-style: "draw/describe the scoreboard for an OoO retire stream."

Exercise `.md` must contain: goal, setup/DUT assumptions, the skeleton, what a correct answer must
achieve (without saying how), and **no hints that reveal the answer**.

**Solution `.md`** (mandatory structure):
```
# Module NN / Exercise MM — Solution
## Full solution code
## TODO k — <title>   (per TODO: code, why correct from UVM mechanics, common wrong answers + their log symptom)
## Self-review checklist  (every `get` has a matching `set`; all ports connected; super.* called;
                           objections balanced; phases correct; types match; no undeclared identifiers)
## Expected log (hand-derived, not simulated)
## The result that matters  (one paragraph: the single insight + a variation to try)
```

## 7. Cross-module consistency (cheap version)

- Order of introduction is the table in §3. Never use a concept before its module; forward
  reference in one sentence ("Module 6 covers this").
- `mini_cpu` DUT, its interface (`mini_cpu_if`), the instruction item (`cpu_instr_item`) and
  naming prefix `mcpu_` are defined **once in Module 01/03** and reused. Later modules reuse the
  exact names from `PROGRESS.md`'s "Shared names" section — do not re-invent them.
- Use **only the previous module's MANIFEST.md** plus `PROGRESS.md` for context. Do not re-read
  earlier lessons or examples. Do not audit earlier modules.

## 8. Manifest (`solutions/moduleNN/MANIFEST.md`) — ≤ 40 lines

```
## Concepts taught        (term list)
## UVM classes/macros introduced
## Shared names defined   (class/interface/file names later modules must reuse, with one-line signatures)
## Exercises              | file | type | TODOs | subtle trap |
## Forward references made
```

## 9. PROGRESS.md

One line per module: `NN | status (todo/written/reviewed) | one-sentence summary`. A section
`## Shared names` lists the canonical class/interface names and key field names (updated by each module).
This file + the previous MANIFEST is the whole cross-module memory.

## 10. Cost discipline (read this)

The CUDA course was expensive because of loops: write → run → fail → rewrite → re-read other
modules → audit → rewrite. Without a simulator there is nothing to loop on, so:

1. **One pass per module.** Write each file once with the Write tool. Do not Read a file you just wrote.
   Do not re-print file contents in chat.
2. **One bounded self-review** at the end of each module (the §6 checklist applied to the module's own
   files, via Grep for `config_db`, `connect`, `raise_objection` etc.). Fix only real inconsistencies,
   once. No second audit.
3. **One module per session.** `/clear` between modules. Start each session by reading only: this spec,
   `PROGRESS.md`, the previous `MANIFEST.md`.
4. **No subagents, no workflows, no parallel fan-out** for authoring. (Optionally one final review
   subagent for the whole course, see Part 2.)
5. **Be terse in chat**: report only "files written, known gaps". No summaries of file content.
6. **Don't over-polish.** If something is correct and clear, move on. Prefer a smaller correct example
   over a larger impressive one. A mid-level DV engineer's interview coverage is the bar, not completeness.
7. **Model:** Sonnet is sufficient for modules. Spend extra only on Module 01 (sets the template and
   shared names) and the final review.

Approximate budget target: a module ≈ 8–10 files, ~1,500 lines total, one session.

## 11. Quality bar

An exercise should require a reader to *reason about UVM mechanics* at least once (phase ordering,
handshake, config scope, TLM direction). If it could be solved by pattern-matching the lesson text,
rewrite it. The interview sections must contain questions an interviewer would really ask, not trivia.
Prefer: *why* the library does X, what symptom appears in the log when it is misused, how you'd debug it.

---

# PART 2 — PROMPTS TO PASTE

## Prompt A — kickoff (Module 01 only; use Sonnet, or Opus once if you want a strong template)

```
Read AUTHORING_SPEC.md in full. We are building a 10-module UVM course for CPU
verification interviews. We cannot run any simulator, so all UVM must be real UVM 1.2
canonical code (spec §1).

Task: author Module 01 exactly per the spec — README.md (the lesson), example(s), exercises, solutions,
check_your_understanding.md, MANIFEST.md — plus create PROGRESS.md with the Shared names
section. Module 01 defines mini_cpu, mini_cpu_if, and the naming prefix, so choose them
carefully and record them. Also decide the exercise-file convention (spec §4) and record it
in PROGRESS.md.

Follow spec §10 cost discipline: one pass, no re-reading what you wrote, one bounded
self-review, terse report. Do not start Module 02.
```

## Prompt B — every later module (fresh session / after `/clear`)

```
Read AUTHORING_SPEC.md, PROGRESS.md and solutions/module{NN-1}/MANIFEST.md only.
Author Module {NN} ({title from spec §3}) per the spec: lesson, 1–2 examples, 2–3 exercises,
solutions, check_your_understanding, MANIFEST. Reuse the shared names from PROGRESS.md exactly.
Use only real UVM 1.2 APIs; tag constructs and fill the Reference section; hand-derive any
expected logs and label them as such. Follow §10: one pass, one bounded self-review using
Grep for config_db/connect/objection consistency, update PROGRESS.md, terse report.
Do not read other modules. Do not start the next module.
```

## Prompt C — optional final review (one session, run once at the end)

```
Read AUTHORING_SPEC.md and PROGRESS.md. Without editing, review the whole course for ONE
class of defect only: UVM API correctness. Grep every `uvm_`/`` ` `` identifier across all
.sv/.md files and list any that are not real UVM 1.2 classes, macros, methods or phases,
any config_db set/get mismatches, any component missing super.build_phase/connect_phase,
and any unbalanced objection. Report findings as a table (file:line, problem, fix). Then
apply only the fixes I approve.
```

## Prompt D — spot check without a simulator (human, optional, cheap)

Paste any `example*.sv` into EDA Playground (UVM 1.2 + a free simulator). If it fails to
compile, paste the error back to Claude in the module session: "Fix this compile error only;
do not rewrite anything else."

---

# Notes on what was kept vs. dropped from the CUDA course

| Kept (drove quality) | Dropped (drove cost) |
|---|---|
| Fixed per-module structure & mandatory headings | 600–1000-line lessons (now 250–400) |
| Exercise types: fill-in with a *subtle trap*, debugging, design, predict | Compile/run/fail/fix loops on every solution |
| Solutions explain *why*, plus common wrong answers & symptoms | Cross-module audits and re-reading earlier modules |
| MANIFEST + shared-names for consistency | Hardware benchmarking methodology (no equivalent) |
| "Nothing in the exercise dir reveals answers" | 24+ modules (now 10) |
| Precise, non-filler tone; defined-on-first-use terms | Opus-level elaborate prompt; recursion |
| Labels PORTABLE vs ARCH-SPECIFIC → PORTABLE vs SIMULATOR/VERSION-DEPENDENT | |
