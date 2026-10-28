# Module 03 / Exercise 03 — Design the stimulus for "LW after SW to the same address"

**Type:** Design. No code to compile; deliverable is a written design plus short pseudocode or SV sketches.

## Scenario

You must verify that `mini_cpu` returns the **just-stored** value when a `LW` reads an address that a preceding `SW` wrote, for every pipeline distance between them (store-to-load forwarding or whichever mechanism the design uses). You have the course's `cpu_instr_item`, a fetch-side sequencer and a load/store-side sequencer with `mcpu_mem_item` (preload words).

## Deliverables

1. **Scenario list.** Enumerate the distinct situations to cover (at least 5), including at least one *negative* case where the load must **not** see the store.
2. **Sequence structure.** Which sequences do you write (names and one line each), what parameters/`rand` knobs do they have, and which are virtual sequences?
3. **Constraints.** For the key sequence, write the constraints/inline `with {}` needed so that the store and the load really target the same address, including how you guarantee that the **base register** holds an aligned value.
4. **Data choices.** How do you pick data and memory preload so that a wrong result is distinguishable from the right one?
5. **Expected result.** What exactly should be true when the load retires, and where in the testbench is that checked (name the component, even though its body is a later module)?
6. **Reproducibility.** One sentence: how would you make a failing instance replayable?

## Constraints

- No two scenarios may differ only by random register numbers.
- State which parts need a virtual sequence and why.
- Mention (do not build) what coverage you would collect to prove the distances were exercised.

Compare against `solutions/module03/exercise03_solution.md` (one reference design).
