# Module 05 / Exercise 03 — Design the TLM connectivity of the `mini_cpu` env

**Type:** Design / interview write-up. No code to compile; deliverable is a diagram and short written answers, with at most a few SV lines for the connections.

## Scenario

The env contains: the fetch agent (monitor publishes `mcpu_bus_txn` for each instruction word delivered), the load/store agent (monitor publishes `mcpu_bus_txn` per completed access), a **retire monitor** (publishes one retire entry per retired instruction: `pc`, `instr`, `rd`, `data`), a **scoreboard** (with reference model, Module 06), and a **coverage collector** that needs the instruction stream and the load/store accesses.

You will be asked: *"Show how the data gets from the monitors to the checkers and to coverage, and defend your choices."*

## Deliverables

1. **Connectivity diagram.** Every producer port, every consumer, and every connection. Mark where you use `uvm_analysis_imp`, where `uvm_analysis_imp_decl` is needed, where a `uvm_tlm_analysis_fifo` is better, and where you rely on port-to-port promotion through the agent boundary.
2. **Justification table.** For each consumer: imp or FIFO, and the one-sentence reason (timing, blocking, multiple inputs).
3. **Ordering and timing.** The fetch monitor and retire monitor publish at different times, and two subscribers of one port are called in unspecified order. State what that means for the scoreboard (what it must not assume) and for the coverage collector.
4. **Connect-phase code.** The connection statements of `mcpu_env.connect_phase` (a few lines).
5. **Failure modes.** Three ways this connectivity could break silently, and a check you would add (in code or in the log) to make each failure visible.

## Constraints

- A new consumer (e.g. a trace logger) must be addable with **no change** to any monitor or agent.
- Neither monitor may ever be slowed down by a consumer.
- Use only the TLM facilities covered in the lesson.

Compare against `solutions/module05/exercise03_solution.md` (one reference design).
