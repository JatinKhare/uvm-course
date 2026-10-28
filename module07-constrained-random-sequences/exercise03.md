# Module 07 / Exercise 03 — Design a hazard-heavy random instruction-stream generator

**Type:** Design / interview write-up. No code to compile; deliverable is a written design with short SV sketches where noted.

## Scenario

You must stress the `mini_cpu` pipeline's data-hazard and load-use handling with **constrained-random programs**. Every program must be legal, must terminate, must be reproducible, and must be self-checking through the ISS-based scoreboard (Module 06). You may use `cpu_instr_item`, sequences, virtual sequences, config objects and the factory.

## Deliverables

1. **Layer diagram.** Item → burst sequences → scenario sequence → test (and any virtual sequence). For each layer: its knobs (`rand` fields), and what it decides.
2. **Constraints.** Give the constraints (or sketches) for: (a) opcode mix with a rare-opcode guarantee (CSR, branch), (b) hazard-density control, (c) legal memory addresses, (d) forward-only branches. State the `solve before` ordering you need and why.
3. **Program structure.** What does the generated program look like from first to last instruction (setup, body, end marker)? How do you set up base registers and the data region so every LW/SW is legal?
4. **Termination.** Prove (in two sentences) that every generated program terminates.
5. **Reproducibility.** What do you log at time 0 and during generation, and how do you replay a failure if the generator code has since changed?
6. **Customising per test.** Show how a test (a) pins a knob, (b) changes the opcode mix without editing the generator, and (c) switches a legality constraint off for a negative test. Name the mechanism for each.
7. **Self-check.** One way to detect automatically that the generator is *not* producing what you think (distribution drift) without reading the log.

## Constraints

- No two bursts may differ only by random register numbers.
- Legality constraints in the item must never be weakened to make a scenario work.
- State clearly which behaviours are SystemVerilog randomisation features and which are UVM.

Compare against `solutions/module07/exercise03_solution.md` (one reference design).
