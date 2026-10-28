# Module 10 — Debug, Environment Integration & Interview Capstone

> Prerequisites: Modules 01–09.
> What this module gives you: the integrated `mini_cpu` bench (executing DUT, fetch agent, retire monitor, scoreboard, coverage), how a base test owns configuration and timeout, how reset and error injection are handled, how to debug with logs and plusargs, how to think about regressions, a capstone test plan, and the 25 questions that tie the course together for interviews.

UVM 1.2 only. Logs are hand-derived. This lesson runs longer than the others (about 450 lines) because it carries the capstone Q&A. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Every actor has rehearsed alone (driver, monitor, scoreboard, coverage, register model). **This module is the dress rehearsal with the whole cast.** Things that never failed alone now fail: a missing wire between two actors, a prop (config) not handed over, someone leaving the stage (reset) while the prompter keeps reading the old script.

Three questions run the whole module: **Does it run? Can it fail? Can I repeat it?** Everything below — base test, reset handling, bug injection, regression — answers one of those.


### What integration adds

Individually correct components still fail together. Integration asks three questions:

1. **Does it run?** (bring-up: connections, configuration, timeouts, reset)
2. **Does it check?** (can the bench actually fail? — proven by *negative* tests)
3. **Can I trust and repeat it?** (regressions: seeds, pass criteria, triage, coverage merge)


### The integrated bench

```
 tb_top: clk/rst_n, mini_cpu_if, mcpu_rst_ctl_if, mini_cpu_core (DUT), run_test()
   |
 mcpu_env_base_test  (cfg object, vif, factory override, timeout)  ->  mcpu_smoke_test / mcpu_reset_test
   |
   mcpu_env
     ifetch_agent  (seqr -> driver -> pins, monitor)  --ap--> sb.fetch_imp   (predictor: ISS)
     retire_mon                                       --ap--> sb.retire_imp  (compare)
                                                      --ap--> cov            (Module 08 subscriber)
```


### Gaps from earlier modules, and how this module settles them

| Gap recorded earlier | Decision here |
|---|---|
| The Module 01 stub DUT never executed instructions (retired `rd=0, data=0`) | `mini_cpu_core` (`example01.sv`) executes ADD/SUB/AND/OR/ADDI/LW/SW/BEQ/CSRRW and retires real `rd`/`data` — the scoreboard now compares real results |
| No error-response signal (`ls_err`) in `mini_cpu_if` | **Not added.** The core has an internal data memory; error responses, traps and interrupts are **not modelled** here. Error injection is done as DUT *mutation* (below). The interface stays fixed. |
| CSR register port vs. the architectural CSR path | The register port of Module 09 is a separate interface not wired into this core; the plan (Exercise 03) shows how the two paths would be unified |


---

## UVM Mechanics

### Base test, env and test variants

- The **env** is structure: components, connections, wiring of configuration. It decides nothing about stimulus.
- The **base test** owns everything common: it gets the virtual interface, builds the config object, `set`s it for the env, registers factory overrides *before creating the env*, sets the phase timeout (`uvm_top.set_timeout`), and logs what it is running. Concrete tests extend it and only override `run_phase` (sequences, objections, drain time).
- Tests are selected at run time: `run_test()` with an empty name reads `+UVM_TESTNAME=<class>` (a missing plusarg gives a fatal naming the problem). Plusargs such as `+MCPU_BUG_ADD` are read by the DUT or the test with `$test$plusargs`/`$value$plusargs`.


### Reset

**In plain words:** pressing reset is **rebooting the chip** — and the testbench must "forget" too, or it will keep marking the new run against the old answer key. The safe order is a four-beat routine: **let current work finish → press reset → wait until the chip is awake → clear the testbench's memory → start again.** Skip beat one and you silently lose a check (Exercise 02).

Reset is a **test-level event that every stateful part must honour**. In this bench, parts with state across a reset are: the DUT, the scoreboard (ISS and queues), the coverage history, any outstanding sequence/driver activity, and (in a bench with registers) the register-model mirror.

Two approaches:
1. **Reset only at the start** (the course default): every component is created, reset is released at 42 ns, nothing changes after.
2. **Mid-run reset**: the test requests reset (here via `mcpu_rst_ctl_if.req`, which `tb_top` turns into a two-clock pulse), and then follows an **ordering rule**: **settle → reset → wait for release → flush the models → restart stimulus**.

The ordering is where the bugs are (Exercise 02):
- **settle first**: let the last retirement of the previous program be observed and compared; resetting early drops it silently;
- **flush after release**: restarting the ISS before the DUT is out of reset can make new fetches meet the old model, and doing it before the previous program is fully compared discards pending expectations;
- the flush keeps the **counters** (they describe the whole run) and clears queues and the ISS.

Production benches add a **reset watcher** (a component that samples `rst_n`) that flushes checkers automatically; the course uses an explicit `flush()` call so the ordering is visible. UVM also has run-time reset phases (`reset_phase`, `post_reset_phase`) for the *initial* reset sequence; mid-run reset with phase jumping is outside this course.


### Error injection — three kinds, and what each is for

| Kind | What you do | Proves |
|---|---|---|
| **DUT mutation** (`+MCPU_BUG_ADD`) | change the DUT's behaviour (in the model, or a seeded RTL bug) | the **checker can fail**: the scoreboard reports the first affected retirement |
| **Stimulus fault** (corrupt an instruction word, a data word) | change what the testbench delivers | the DUT's reaction (trap, ignore) — needs a DUT that has one |
| **Protocol fault** (error response, dropped response) | change handshake behaviour | the DUT's recovery — needs the protocol to carry it |

Only the first is available on this DUT. A bit flip in the instruction word served by the fetch agent is **not** detected by this scoreboard: the predictor is fed from the **fetch stream**, so it sees the flipped word too and predicts consistently (Module 06 lesson: feeding from the *program image* would catch it). Each limitation is a design statement, not a bug.

**Negative tests.** A negative test expects the error. The mechanism is `uvm_report_catcher` (a callback on reports): a catcher can downgrade a known error to an info and count it; the test then passes only if the expected number occurred (Exercise 01). Without this, a mutation run would "fail" the regression for the right reason.


### Logging and verbosity

| Control | Effect |
|---|---|
| Severity | `UVM_INFO`, `UVM_WARNING`, `UVM_ERROR` (counted), `UVM_FATAL` (ends the run) |
| Verbosity | `UVM_NONE`…`UVM_DEBUG`; default threshold `UVM_MEDIUM`; `+UVM_VERBOSITY=UVM_HIGH` raises it globally |
| Per-ID / per-component | `set_report_verbosity_level_hier(...)`, `set_report_id_verbosity_hier("ID", ...)` on a component and its subtree |
| Message hygiene | stable IDs (`RETIRE_MISMATCH`), the hierarchical path (automatic), **both sides of a comparison**, simulation time; one idea per message |
| Abort control | `+UVM_MAX_QUIT_COUNT=N` stops after N errors; `+UVM_TIMEOUT=<time>` adjusts the global timeout |
| Tracing plusargs | `+UVM_PHASE_TRACE` (phase transitions), `+UVM_OBJECTION_TRACE` (every raise/drop), `+UVM_CONFIG_DB_TRACE` (every `set`/`get`) — output formats are **SIMULATOR/VERSION-DEPENDENT** |

A pass verdict is a **conjunction**: zero `UVM_ERROR`/`UVM_FATAL`, a "test finished" marker the test itself prints, a sane end time, comparison counts greater than zero and equal to the expected number, and (for sign-off) coverage at goal.


### Debugging workflow

**In plain words:** be a detective, not a gambler. Find the **first** thing that went wrong, make the case **smaller**, make the testbench **talk**, check the **bench before blaming the chip**, and only then open the waveform.

1. **Read the first error**, not the last; later ones are usually consequences.
2. **Classify the symptom** with the catalog below (ends at time 0; hangs; silent pass; error flood; X).
3. **Shrink**: smallest test, one seed, one program.
4. **Make the bench talk**: raise verbosity on the suspect subtree; `+UVM_OBJECTION_TRACE` for hangs; `+UVM_CONFIG_DB_TRACE` for silent configuration; `uvm_top.print_topology()` to confirm the structure.
5. **Check the bench before the DUT**: connections, configuration, ordering, objection balance, reset sequencing.
6. Only then open the waveform; look at the interface, not the internals.


### Regression thinking

A regression is **many tests × many seeds**, run for pass/fail and for coverage:
- **Pass/fail** per run = the conjunction above, computed by script from the log, not by eyeballing.
- **Seeds**: log them; reproduce any failure with `test + seed`; a failure that does not reproduce with the same seed and code is a **race** in the bench or a tool difference.
- **Triage**: group failures by first-error signature (ID + short message); each signature is a bug (RTL or TB) or noise. Flaky = not reproducible with a fixed seed.
- **Coverage**: merge from passing runs only; track the open holes per run; add directed tests or constraint bias for reachable holes (Modules 07–08).
- **Time**: put a timeout on every test so a hung run is a clean failure, not a stuck job.
- **Exit criteria**: all tests passing at the target seed count, coverage goals met, no unexplained waivers, assertions and scoreboard proven able to fail (mutation suite).


---

## Code Walkthrough

**How to read the examples:** `example01.sv` = the **chip** (executes instructions, plus a switchable bug). `example02.sv` = the **whole bench** and three ways to run it, chosen on the command line with `+UVM_TESTNAME=...`: *smoke* (ends at 235 ns), *smoke + `+MCPU_BUG_ADD`* (errors at 135 and 195 ns), *reset test* (ends at 455 ns). Each run's log is derived at the end of the file — **predict it first, then check.**


### 1. The executing DUT (`example01.sv`)

`mini_cpu_core` raises `if_req`, waits for the agent's one-cycle `if_rvalid` pulse, **executes at the edge where it samples it**, and presents one `retire_*` record the next cycle. By the Module 04 fetch protocol and this FSM, one instruction takes 30 ns: executions at 65, 95, 125, 155, 185 ns, retire records observed at 75, 105, 135, 165, 195 ns. Hand-derived retire records for the Module 06 program: `(pc 0, x1, 5) (4, x2, 7) (8, x3, 12) (12, rd 0, 0) (16, x5, 12)`. `+MCPU_BUG_ADD` makes ADD return `a+b+1`.


### 2. The env (`example02.sv`)

`mcpu_env` gets `cfg` (the test's `set`), passes it down by `set` for the agent and by direct assignment for the retire monitor, creates the scoreboard through the **factory** (so the base test can substitute the reset-capable variant), and connects fetch → `sb.fetch_imp`, retire → `sb.retire_imp` and `cov.analysis_export`. Connection checklist (Module 05): every producer port has a consumer; imps match `write_*` names.


### 3. The base test

```systemverilog
mcpu_scoreboard::type_id::set_type_override(mcpu_rst_scoreboard::get_type());   // BEFORE the env exists
uvm_top.set_timeout(10us, 0);                                                    // hang -> clean fatal
env = mcpu_env::type_id::create("env", this);
```


### 4. Smoke run, derived

`+UVM_TESTNAME=mcpu_smoke_test`: the program's last item completes at 185 ns (the fifth execution); the test drops its objection then; the 50 ns drain time lets the retire monitor sample the last record at 195 and the scoreboard compare it; the run phase ends at **235 ns**: `[SB] fetched=5 compared=5 mismatched=0` and coverage `class=66.7 dist=50.0 cross=16.7 total=44.4` (the Module 08 numbers for this program).


### 5. Mutation run, derived

With `+MCPU_BUG_ADD`: `x3` becomes 13. Retirement #3 (the ADD) is observed at 135 ns with `data=0x0d` against the expected `0x0c`: **`RETIRE_MISMATCH` at 135 ns**. The SW retires with `rd=0, data=0` and matches. The wrong `x3` is stored and loaded back, so the LW (#5) retires `data=0x0d` at 195 ns: a **second** mismatch. Final: `mismatched=2`, two `UVM_ERROR`s. The first error is the root cause; the second is its consequence — the first-error rule from the debugging workflow.


### 6. Reset run, derived

`+UVM_TESTNAME=mcpu_reset_test`: program 1 ends at 185; `#52ns` → 237 ns (deliberately not an edge time: edges are at 5, 15, …, 235, 245); `rst_n` drops at 237, the DUT sees it at 245 and 255, release at the 260 negedge; the test then flushes the scoreboard and starts program 2. The DUT restarted from pc 0 with cleared registers and memory, so program 2 executes at 285, 315, 345, 375, 405 ns; drain → **455 ns**; `fetched=10 compared=10 mismatched=0`. (Coverage numbers are unchanged: program 2 produces the same samples.)


---

## Common Pitfalls

- **Test ends at time 0** → nothing but the build lines in the log; no errors → no objection raised (or raised after a delay); `+UVM_OBJECTION_TRACE`.
- **Hang, time advances** → periodic monitor messages continue → an objection never dropped (early `return` on an error path) or a sequence blocked in `finish_item` because `item_done` is missing; the timeout turns it into a fatal.
- **Silent pass** → green run, `compared=0` or counts far below expectation → a connection not made, a monitor sampling the wrong thing, or a checker flushed/reset too early; the scoreboard's `check_phase` guards (`SB_EMPTY`).
- **Error flood after one real error** → hundreds of mismatches → streams slipped (popped only on match) or the model lost sync (reset without flush); read the first error only.
- **Mismatch at the first instruction after a mid-run reset** → the model was not flushed, or was flushed before the previous program was fully compared.
- **X in a comparison** → `==` instead of `===`, or an uninitialised signal at time 0 (driver idle values set in `run_phase`).
- **Configuration silently defaulted** → a knob has its default (config set too late, wrong path/type) → print what `get` returned; `+UVM_CONFIG_DB_TRACE`.
- **Mutation not caught** → a seeded bug passes → the checker has a blind spot (field missing from `do_compare`, model bits not described, predictor fed from the same corrupted source).


### Symptom → first suspect (catalog)

| Symptom | First suspect | Module |
|---|---|---|
| `INVTST` fatal at time 0 | test class not registered / wrong name | 01, 02 |
| Overrides ignored | `new` instead of `create`; override after create; wrong path | 02 |
| Run ends at 0, no errors | missing objection | 01, 02 |
| `NOVIF`/`NOCFG` fatal | `config_db` path/type/field mismatch or set too late | 05 |
| Driver never gets items / test hangs | missing `item_done`; seq-driver not connected | 03, 04 |
| Directed instruction random | name clash in `with{}` | 03 |
| Rare opcode never generated | `solve before` / `dist` | 07 |
| Scoreboard silent | typo'd `connect_phase`; unconnected analysis port | 05, 06 |
| Mismatch shifted by one | pop only on match; reset without flush | 06, 10 |
| Coverage 100% too early | `default`/`ignore_bins`, sampling in the driver | 08 |
| Register mirror mismatch on a correct DUT | model field position/policy | 09 |
| Register access hangs | `provides_responses` vs driver | 09 |


---

## Interview Angle — the 25 questions

*(Each answer is the two-to-three-line version you would say aloud. Module numbers show where it is taught.)*

**Q1 (01). Why UVM instead of a hand-written testbench?**
A standard library for structure and reuse: phases fix the order, the factory and `config_db` let tests vary the bench without editing it, sequences separate stimulus from protocol, TLM plumbs monitors to checkers. Components from different projects plug together.

**Q2 (01). Component versus object?**
Components form the static hierarchy, are built before time 0 and have phases; objects are lightweight dynamic data (items, sequences, configs) without parent or phases.

**Q3 (02). Order of the phases and why build is top-down?**
build (top-down), connect, end_of_elaboration, start_of_simulation, run (parallel tasks), extract, check, report, final. Parents create children in build, so they must run first; every component finishes a phase before any begins the next.

**Q4 (02). How does the test end?**
When all objections raised in `run_phase` are dropped, after any drain time; then every remaining `run_phase` task is killed. No objection → ends at time 0; an undropped one → hang (guard with a timeout).

**Q5 (02). What does the factory give you?**
`type_id::create` lets a test substitute a subclass by type or by instance path without changing the code that creates it; instance overrides beat type overrides; `new` bypasses it; overrides must exist before the `create`.

**Q6 (03). Item versus sequence; what do `start_item`/`finish_item` do?**
The item is one transaction; the sequence generates a stream. `start_item` waits for the sequencer's grant, the item is randomised, `finish_item` delivers it and blocks until the driver's `item_done`.

**Q7 (03). What is a virtual sequence?**
A sequence that orchestrates real sequences on several sequencers through a virtual sequencer (handles assigned in connect). Example: preload memory, then run the program.

**Q8 (04). Describe the driver–sequencer handshake.**
Pull model: the driver calls `get_next_item`, drives the interface, and calls `item_done` — exactly one per item. `item_done` releases the sequence's `finish_item`.

**Q9 (04). Active versus passive agent; why a separate monitor?**
Active has sequencer+driver+monitor, passive only the monitor (guarded by a config flag). The monitor observes what the DUT did, independent of who drove it, so it feeds checking and coverage in every configuration.

**Q10 (05). How does `config_db` resolve, and how do you debug a miss?**
Type, field name, and scope (context + path) must match an entry set earlier; higher-level sets win. Debug by printing `get` results, `+UVM_CONFIG_DB_TRACE`, checking relative versus absolute paths and set timing.

**Q11 (05). Analysis imp or FIFO?**
Imp for quick, non-blocking consumers (runs in the producer's thread); `uvm_tlm_analysis_fifo` when the consumer needs its own thread or pacing. Analysis ports never block the producer and may have zero subscribers (silently).

**Q12 (06). Describe the checking for a CPU.**
A retire monitor and an ISS fed with the fetched instructions; a two-queue scoreboard compares `pc, instr, rd, data` in order with `===`; `check_phase` verifies something was compared and nothing is left over.

**Q13 (06). What should feed the ISS?**
The fetched instruction stream (also checks the fetch address and next-PC) or the program image (independent of fetch bugs, needed to catch corrupted fetch data, and robust to speculation). State which and what it can't catch.

**Q14 (06). Out-of-order results?**
Give transactions an ID and keep expected ones in an associative array; match on arrival, delete; leftovers and unmatched arrivals are errors. Architectural retirement is still in order.

**Q15 (07). `solve before` and `dist`?**
`solve before` changes probabilities, not legality (choose the opcode before the immediate so CSR instructions aren't starved); `:=` gives each value in a range the weight, `:/` splits it.

**Q16 (07). Reproduce a random failure?**
Same seed, same code and tool; log the seed and the generated stream at the start so it can be replayed as a directed test even after code changes.

**Q17 (08). How do you plan and close functional coverage?**
Plan items → coverpoints/crosses sampled from monitors; regression; merge passing runs; analyse holes; bias constraints or write directed tests; waive only impossible bins with reasons.

**Q18 (08). Assertions versus coverage?**
Assertions check rules; coverage records occurrence. Pair each assertion with a `cover property` so a vacuous pass is visible.

**Q19 (09). Mirror, predictor, auto-predict?**
The mirror is the model's view of the DUT. Auto-predict updates it for accesses made through the model; a predictor watching a bus monitor sees all traffic (other masters, instructions, hardware updates).

**Q20 (09). Frontdoor versus backdoor?**
Frontdoor goes through the bus (time, decode, side effects); backdoor reads/writes storage by hierarchical path via DPI in zero time. Use both: frontdoor for the path, backdoor for speed and independent cross-checks.

**Q21 (10). How do you handle reset in a testbench?**
Everything with state must honour it: settle, apply reset, wait for release, flush models and queues (keep totals), restart stimulus; the register mirror is reset too. A watcher can automate the flush; mistakes show as a mismatch at the first instruction after reset.

**Q22 (10). How do you know your checker can fail?**
Mutation/negative tests: inject a DUT bug (a plusarg-selected mutation), expect exactly the predicted errors (catch and count them with a report catcher), and fail the regression if the bug is *not* caught.

**Q23 (10). A test ends at time 0 / hangs / passes with nothing checked — what do you do?**
Time 0: objections (`+UVM_OBJECTION_TRACE`). Hang: undropped objection, missing `item_done`, timeout. Silent pass: connections, comparison counts, `SB_EMPTY`; check the first error, shrink the test, raise verbosity on the suspect subtree.

**Q24 (10). What defines pass in a regression, and how do you handle flaky tests?**
Zero errors/fatals, a test-finished marker, expected counts, sane end time, coverage merged from passing runs only. A flaky test is one that does not reproduce with a fixed seed: look for races, uninitialised state, tool-dependent ordering.

**Q25 (10). How do you decide you are done verifying a new CPU feature?**
Plan items implemented and each traced to a test, checker and coverage bin; scoreboard and assertions proven by mutation; regression at the target seed count passing; coverage at goal with documented waivers; open risks (here: traps/interrupts not modelled) listed explicitly.


---

## Recap in five lines

1. Integration asks: **does it run, can it fail, can I repeat it?**
2. The **base test** owns configuration, factory overrides and the **timeout**; tests only add stimulus.
3. **Reset routine:** settle → reset → wait for release → flush models → restart.
4. **Mutation (a seeded bug)** proves the checker can fail; a **negative test** expects the error and counts it.
5. **Pass** = zero errors + finish marker + right counts + sane end time; a **flaky** test is one that doesn't reproduce with a fixed seed.

**How to use the 25 questions:** read one, *say the answer aloud in your own words*, then compare; if you stumble, jump to the module number shown and re-read its recap.


---

## Check Your Understanding

1. In `mcpu_smoke_test`, why does the `[SB]` summary print at **235 ns** and not at 185 ns?
2. With `+MCPU_BUG_ADD`, give the number of errors, their times, and explain why the SW's retirement does not produce one.
3. In `mcpu_reset_test`, suppose `rsb.flush()` is deleted. Predict the first error message, its time, and the total number of errors for the whole run.

Answers: `solutions/module10/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | A negative test: catch and count the expected mismatches with a `uvm_report_catcher`; pass only if exactly two occurred. |
| `exercise02.md` | Debug the testbench | A reset test that dies on a timeout and, once fixed, silently skips a comparison. |
| `exercise03.md` | Design / capstone | The full verification plan for `mini_cpu`: features, tests, checkers, coverage, regression and exit criteria. |


---

## Reference

**Classes:** `uvm_test`, `uvm_env`, `uvm_root` (`uvm_top`), `uvm_report_catcher`, `uvm_report_cb`, `uvm_report_server` (counts), `uvm_phase`, `uvm_factory` (override calls via `type_id`), `uvm_config_db#(T)`.

**Methods/tasks:** `run_test()` (name from `+UVM_TESTNAME`), `uvm_top.set_timeout(time, overridable)`, `uvm_top.print_topology()`, `set_report_verbosity_level_hier`, `set_report_id_verbosity_hier`, `phase.phase_done.set_drain_time`, `$cast`, `$test$plusargs`, `$value$plusargs`, catcher `catch()`, `get_severity/set_severity/get_id`.

**Plusargs:** `+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+UVM_MAX_QUIT_COUNT`, `+UVM_TIMEOUT`, `+UVM_PHASE_TRACE`, `+UVM_OBJECTION_TRACE`, `+UVM_CONFIG_DB_TRACE` (formats **SIMULATOR/VERSION-DEPENDENT**); course-specific `+MCPU_BUG_ADD`.

**Forward references made:** none — this closes the course. Not modelled: traps, interrupts, error responses, an external data memory, multi-issue/out-of-order cores; each appears in the Exercise 03 plan as a stated risk.
