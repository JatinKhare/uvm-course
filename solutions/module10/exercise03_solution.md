# Module 10 / Exercise 03 — Solution (one reference plan)

## 1. Feature list

| ID | Feature |
|---|---|
| F1 | ALU register-register: ADD, SUB, AND, OR |
| F2 | ADDI with sign-extended immediates; `x0` never written |
| F3 | LW/SW: addresses, alignment, store-then-load forwarding |
| F4 | BEQ: taken / not taken, forward offsets, next-PC |
| F5 | CSRRW: read-old/write-new (instruction path) |
| F6 | RAW hazards at distance 1, 2, 3 (all classes) |
| F7 | Reset at start and mid-run: state cleared, restart from pc 0 |
| F8 | Fetch protocol: stalls, back-to-back, reset during fetch |
| F9 | CSR register port: reset values, access policies, field behaviour |
| F10 | X-freedom on the retire trace |
| N1 (not modelled) | Traps/exceptions, interrupts (`irq`), error responses (`ls_err`), external data memory, multi-issue/out-of-order |

## 2. Test table and traceability

| Feature | Test | Type | Stimulus | Checker | Coverage item |
|---|---|---|---|---|---|
| F1,F2 | `t_alu_directed`, `t_alu_random` | directed + random | `send_instr` lists; `mcpu_alu_burst_seq` | scoreboard | `cp_class` |
| F3 | `t_sw_lw` | directed + random | `mcpu_sw_lw_burst_seq` (vseq with memory preload where external memory exists) | scoreboard | memory region × dir |
| F4 | `t_branch` | random (forward only) | `mcpu_branch_seq` | scoreboard + `PC_MISMATCH` | taken/not-taken |
| F5 | `t_csr_instr` | directed | CSRRW sequences | scoreboard (ISS CSR array) | `cp_class.csr` |
| F6 | `t_hazard_rand` | constrained-random | `mcpu_stream_seq` (`hazard` knob), `mcpu_mix_item` weights | scoreboard | `x_class_dist` (24 bins) |
| F7 | `t_reset_mid` | reset | `mcpu_reset_test` (settle → reset → flush → rerun) | scoreboard counts tie out | reset × last class |
| F8 | assertions + `t_fetch_stall` (agent latency knob) | random | agent config | assertions | `cover property` |
| F9 | `t_csr_reset`, `t_csr_bitbash`, `t_csr_access` | register | built-in sequences on the CSR bench | mirror checks | field coverage |
| F10 | all runs | — | — | `!$isunknown` assertion; `===` compares | — |
| mutations | `t_mut_*` | negative | `+MCPU_BUG_*` | catcher + counts | — |

## 3. Checking architecture

- **Scoreboard** (Module 06): retire monitor → compare `pc, instr, rd, data` against the ISS, in order, with `===`; ISS fed from the fetch stream, plus fetch-address check. Failure classes: wrong result, wrong next pc, lost/extra instruction.
- **Assertions** (examples): `retire_valid |-> !$isunknown({retire_pc, retire_instr})`; `if_rvalid |-> if_req` (no response without a request).
- **Register checks** (Module 09): `uvm_reg_hw_reset_seq`, bit-bash, `mirror(UVM_CHECK)`; failure class: register port decode/policy/reset.
- **Gap:** a *corrupted instruction word* delivered by the testbench is predicted consistently (fetch-fed ISS) → not caught; mitigation: a second check that compares the fetched word against the program image at that address.

## 4. Coverage plan

`cp_class` (6) , `cp_dist` (4), `x_class_dist` (24); memory: direction × region (6) × alignment (2); branch: taken/not × forward distance bins; reset: last retired class (6); registers: per-field written 0/1 and access path. Sampled from the retire/bus/CSR-port monitors. Closure loop as in Module 08 (merge passing runs, analyse holes, bias or direct, waive with reasons).

## 5. Mutation suite

| Mutation | Must be caught by | Expected signature |
|---|---|---|
| ADD returns a+b+1 (`+MCPU_BUG_ADD`) | scoreboard | `RETIRE_MISMATCH` at the ADD and at dependent loads |
| SUB operands swapped | scoreboard | `RETIRE_MISMATCH` on every SUB with a ≠ b |
| BEQ taken condition inverted | scoreboard | `PC_MISMATCH` on the fetch after the branch |
| LW address off by one word | scoreboard | `RETIRE_MISMATCH` on the load data |
| Retire data X after reset | `===` compare + assertion | mismatch with X visible; `$isunknown` assertion |
| Reset leaves data memory uncleared | `t_reset_mid` | mismatch in the second program only |
| mepc bit 0 stuck | register mirror check | `UVM_ERROR` on the RO `zero` field (Module 09) |
**Rule:** a regression fails if any mutation run produces *fewer* errors than its recorded signature (the catcher count of Exercise 01).

## 6. Regression plan

- **Per commit:** smoke (1 seed) + all mutation runs (1 seed each).
- **Nightly:** `t_hazard_rand` and `t_alu_random` × 200 seeds, `t_reset_mid` × 50, register tests × 10.
- **Weekly:** coverage merge from passing runs, hole report, directed tests for reachable holes, waiver review.
- **Pass/fail** per run = zero `UVM_ERROR`/`UVM_FATAL`, finish marker, `compared == fetched`, expected end-time bounds; computed by script.
- **Timeouts:** per-test, 20× expected duration.
- **Triage:** group by first-error signature; reproduce with `test + seed`; non-reproducible = race/tool issue until proven otherwise; log seeds and the generated stream.

## 7. Exit criteria

(1) 100% of non-waived functional coverage bins; (2) all regression tests pass at the target seed counts for N consecutive nightly runs; (3) every mutation caught with its signature; (4) zero open waivers without review sign-off; (5) assertions: all `cover property` hit, no failures; (6) open-risk list signed off.

## 8. Risk register

| Risk | Impact | Mitigation / acceptance |
|---|---|---|
| Traps, interrupts, error responses not modelled | exception paths unverified (high) | extend DUT/bench before tape-out; **not acceptable** to waive |
| Internal data memory (no external LSU protocol verified) | protocol bugs on the real memory interface | add the LSU agent of Module 04 Exercise 03; verify latency/error cases |
| ISS written by the same team (common-mode errors) | wrong spec reading mirrored in model and RTL | independent review; cross-check with a third-party ISS on shared programs |
| Fetch-fed predictor | corrupted-instruction faults not detected | image-based check (section 3) |
| CSR port separate from the CPU CSR path | the two views could diverge | unified predictor (Module 09 Exercise 03) |
| Single-issue in-order only | multi-issue effects unverified | scope statement; separate plan if the design grows |
| Coverage from weak sampling or wrong history | false closure | unit-test coverage models on hand-derived programs |

## 9. Effort split (sketch)

Bench and infrastructure 20%; test and sequence development 30%; coverage closure and waiver review 35%; regression infrastructure and triage 15%.

## Self-review checklist

- [x] ≥ 10 features including not-modelled items.
- [x] Every plan item traces to test, checker and coverage item.
- [x] Four or more mutations with detectors and signatures.
- [x] Regression, pass/fail definition and exit criteria measurable.
- [x] Known gaps named with consequences; proven versus planned stated.

## Expected log

Not applicable (design exercise).

## The result that matters

The plan is an argument that the bench would **notice** if the design were wrong: stimulus that reaches the scenarios, checkers that can fail (proven by mutation), coverage that shows the scenarios occurred, and a regression discipline that makes failures reproducible. State what you do *not* verify as clearly as what you do. Variation to try: choose the three highest-risk items in your register and say which test you would build first, and what number you would watch to know it is working.
