# Module 04 / Exercise 03 — Design the load/store memory-side agent

**Type:** Design / interview write-up. No code to compile; deliverable is a written design with short SV sketches where noted.

## Scenario

`mini_cpu` issues loads and stores on the load/store bus (protocol as in Exercise 01). You must build the agent that models the **data memory** behind that bus, to verify the CPU's behaviour under varying memory latency and error conditions. Requirements:

- Memory contents are visible to tests (preload, and read back for checking).
- Response latency is 1 to 4 cycles, selectable per access or fixed per test.
- A test can make a chosen access return an **error response** (the DUT is expected to raise an exception; Module 10).
- The agent must also be usable **passively** (a different memory model is in the system, and only observation is needed).

## Deliverables

1. **Components and classes.** List every class in the agent with its base class and role. Say which are components and which are objects.
2. **Items.** Define the items that flow from sequences to the driver (fields, which are `rand`, constraints). Say what the driver does with each field.
3. **Driver behaviour.** Describe the driver loop as a small state machine or pseudocode, including: how it models the memory array, how it applies latency, how it handles back-to-back requests, and where `get_next_item`/`item_done` (or `try_next_item`) are used — and why. State whether responses are driven *by items from sequences* or *by the driver autonomously*, and justify your choice.
4. **Monitor.** What it publishes and when (refer to Exercise 01's contract), and how it stays correct in passive mode.
5. **Config object.** Fields and their defaults (at least: `vif`, `is_active`, latency range, error-injection control, memory size/base).
6. **One race/ordering hazard** you would watch for and how your design avoids it.

## Constraints

- A test must be able to preload memory **before** the CPU starts fetching, without the CPU ever seeing uninitialised data.
- Latency and error injection must be controllable without editing the driver (state how: config, sequence items, or factory override).
- Reuse `mcpu_bus_txn` for the monitor and `mcpu_agent_cfg`'s style for configuration; do not change `mini_cpu_if`.

Compare against `solutions/module04/exercise03_solution.md` (one reference design, not the only valid one).
