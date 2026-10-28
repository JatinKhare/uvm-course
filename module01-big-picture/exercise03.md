# Module 01 / Exercise 03 — Whiteboard the `mini_cpu` testbench (design / interview write-up)

**Type:** Design + interview write-up. No code to compile; the deliverable is a diagram plus short written answers.

## Scenario

An interviewer says: *"Sketch the UVM testbench you would build to verify a small in-order CPU core, and walk me through how it is built and run."* The DUT is `mini_cpu` as described in Lesson 01: instruction-fetch bus, load/store bus, one interrupt line, and a retire trace. Reset is active-low `rst_n`.

## Deliverables

1. **Block diagram** (ASCII or hand-drawn description) showing every component, the interface, and the DUT. For each component give its UVM base class (e.g. `uvm_env`, `uvm_agent`).
2. **Component/object table.** List at least three things in your design that are `uvm_object`s rather than components, and what each is used for.
3. **Phase table.** For five different items in your design, say in which phase it is created, connected or used, and why that phase.
4. **Checking.** Where does the reference model (an instruction-set simulator, ISS, or a simple predictor) attach, what does it consume, and what does the scoreboard compare against what? Say why the checking is not done in the driver.
5. **Who decides what.** What is decided by the test, what by the env, and what by a sequence?
6. **One bring-up risk.** Name one thing that would cause "the test ends at time 0" or "nothing is checked" in this bench, and how you would detect it from the log.

## Constraints

- The bench must observe all four interface groups (fetch, load/store, interrupt, retire).
- The CPU is the master of both buses; decide what your bus-side agents therefore do.
- Only use concepts from Lesson 01 plus forward references (name the concept and say "covered later"); do not build the internals.

Compare against `solutions/module01/exercise03_solution.md` (one reference design, not the only valid one).
