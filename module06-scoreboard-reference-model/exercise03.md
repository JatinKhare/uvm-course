# Module 06 / Exercise 03 — Whiteboard: scoreboard for an out-of-order, dual-retire CPU

**Type:** Interview write-up. No code to compile; deliverable is a diagram plus written answers, with short SV sketches where noted.

## Scenario

The interviewer says: *"Your `mini_cpu` has grown. The new core is out-of-order internally, can retire **two instructions per cycle** (in program order), takes exceptions, and its data memory returns **load responses out of order**. Describe the scoreboard(s) you would build."*

## Deliverables

1. **Block diagram** of the checking structure: monitors, the reference model, predictor/scoreboard split, and the streams between them. Say which streams are in-order and which are not.
2. **Retire-trace compare.** How does a monitor publish two retirements in one cycle? In which order? What are the fields of one retire entry now that exceptions exist? How does the reference model represent a trap in the expected stream?
3. **Memory-side compare.** How do you check load/store traffic when responses return out of order? Name the key, the data structure, and what you do with an unmatched response.
4. **Speculation.** Instructions fetched down a mispredicted path never retire. What does this do to a scoreboard that predicts from the *fetch* stream, and what would you feed the ISS from instead?
5. **End-of-test.** What exactly must be true for the test to be considered passed (list at least four conditions), and how do you handle in-flight instructions?
6. **Failure visibility.** The first mismatch should be the one reported and enough context should be printed to debug it: say what you would print and how you avoid an error flood afterwards.

## Constraints

- Use only concepts from Modules 01–06 plus forward references (name them).
- The reference model is an ISS that executes the architectural program; it knows nothing about the pipeline.
- Neither monitor may be slowed down by checking.

Compare against `solutions/module06/exercise03_solution.md` (one reference design).
