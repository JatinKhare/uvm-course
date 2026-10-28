# Module 10 / Exercise 03 — The capstone: verification plan for `mini_cpu`

**Type:** Design / interview write-up (capstone). No code to compile; deliverable is a written plan, with short SV sketches where noted.

## Scenario

A manager says: *"You own verification of `mini_cpu` for tape-out. Show me your test plan: what you verify, how you check it, how you know you covered it, how you run the regression, and what you are not verifying."* You may use everything built in Modules 01–10: the layered UVM bench, the ISS-based scoreboard, constrained-random sequences, functional coverage, the CSR register model, and the integrated bench with reset and mutation support.

## Deliverables

1. **Feature list** (at least ten items) covering the ISA subset, hazards, memory, branches, CSRs, reset, and the items the current DUT/bench does not model (state them).
2. **Test table**: for each feature, one or more tests — name, type (directed / constrained-random / negative / reset / register), stimulus mechanism (which sequence/knob), and the checker that judges it.
3. **Checking architecture**: scoreboard (what it compares, what feeds the ISS), assertions (two examples), register checks; say which checker covers which failure class.
4. **Coverage plan**: the covergroups and crosses (with bin counts), where they sample, and the closure loop.
5. **Mutation suite**: at least four seeded DUT bugs (like `+MCPU_BUG_ADD`) and which checker must catch each; the rule for failing the regression if a mutation survives.
6. **Regression plan**: test × seed counts, pass/fail definition, timeouts, how failures are triaged, how coverage is merged, how flaky tests are handled.
7. **Exit criteria** for tape-out (measurable).
8. **Risk register**: at least five risks, including everything *not modelled* (traps, interrupts, error responses, external memory, multi-issue), each with a mitigation or an explicit acceptance.
9. **Resources and schedule sketch** (rough effort split between bench, tests, closure).

## Constraints

- Every plan item must trace to a test, a checker, and a coverage item (give the trace in a small table).
- Distinguish what is **proven** by the existing bench from what is **planned**.
- Name each known gap from the course (`ls_err`, internal data memory, predictor fed by fetches, CSR port separate from the CPU path) and state its consequence.

Compare against `solutions/module10/exercise03_solution.md` (one reference plan).
