# Module 02 — Phases, Objections, Factory

> Prerequisites: Module 01 (components vs objects, `run_test`, first test, minimal objection).
> What this module gives you: a precise model of *when* each piece of a UVM testbench runs, how a test decides it is finished, and how the factory lets you swap classes without editing the testbench.

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Building a house has a natural order: **draw the plan → build the rooms → run the wiring → final checks → people move in and live → inspection → handover**. Nobody installs light switches before the walls exist. UVM gives every testbench the same order, with the same names:

| House | UVM phase | What it means for the testbench |
|---|---|---|
| Build the rooms | `build_phase` | create the components (test creates env, env creates agents …) |
| Run the wiring | `connect_phase` | connect the ports between components |
| Final walk-through | `end_of_elaboration` / `start_of_simulation` | last checks before time starts |
| **People live there** | **`run_phase`** | **the only phase where simulation time passes** — stimulus, monitoring |
| Inspection | `extract` / `check` / `report` | collect results, decide pass/fail, print the summary |

Two ideas fall out of this:
- **Nobody moves on until everyone is done** with the current step (all rooms are built before any wiring starts).
- **"How long do people live there?"** is decided by *objections* (next section) — "I'm still busy" signs.

**Worked mini-example (you can trace it in your head):** the test creates `env`; `env` creates `agent`. *Build* runs test → env → agent (parents first, because a parent must exist before it can create a child). *Connect* runs agent → env → test (children first). Then `run` starts for all three **at the same time**.


### Why phases

A testbench has an inherent order: build the objects, wire them, let time run, collect results. If each team coded that by hand, reusable components could not rely on anything. UVM fixes the order with **phases**: every component gets the same named callbacks, and the library guarantees that **no component enters phase N+1 until every component has finished phase N**. That barrier is what makes "my driver can assume its virtual interface was set in build" safe.


### The common phases (**PORTABLE UVM CONCEPT**)

| # | Phase | Kind | Traversal | Typical `mini_cpu` use |
|---|---|---|---|---|
| 1 | `build_phase` | function | top-down | create children, read config |
| 2 | `connect_phase` | function | bottom-up | connect TLM ports (Module 05) |
| 3 | `end_of_elaboration_phase` | function | bottom-up | print topology, check handles non-null |
| 4 | `start_of_simulation_phase` | function | bottom-up | last setup before time runs |
| 5 | `run_phase` | **task** | all components in parallel | reset, drive, monitor, check |
| 6 | `extract_phase` | function | bottom-up | pull final data out of components |
| 7 | `check_phase` | function | bottom-up | end-of-test checks (e.g. "scoreboard empty?") |
| 8 | `report_phase` | function | bottom-up | summaries |
| 9 | `final_phase` | function | top-down | close files, last cleanup |

Only `run_phase` can consume simulation time; the others are zero-time functions. **Top-down** means a parent's callback finishes before any child's starts (needed in `build`, because the parent creates the children). **Bottom-up** means children go first.


### Run-time sub-phases

Inside `run_phase`, UVM 1.2 also offers 12 schedule phases run in parallel with it: `pre_reset`, `reset`, `post_reset`, `pre_configure`, `configure`, `post_configure`, `pre_main`, `main`, `post_main`, `pre_shutdown`, `shutdown`, `post_shutdown` (each `*_phase` task). A CPU testbench could drive reset in `reset_phase` and stimulus in `main_phase`. Many teams ignore them and use `run_phase` alone because mixing both styles complicates objections and reuse. This course uses `run_phase`; reset handling inside it is Module 10.


### Objections: how a test says "I'm not done"

**In plain words:** picture a shop where anyone who is still working hangs a **"BUSY" sign** on the door. The shop closes when **every** sign has been taken down. `raise_objection` = hang up your sign; `drop_objection` = take it down. **Drain time** = "after the last sign comes down, stay open a few more minutes for the last customer to finish leaving". Forget to hang a sign and the shop closes immediately (time 0); forget to take it down and it never closes (a hang).


An **objection** is a counter attached to a phase. Components call `phase.raise_objection(this)` to say "don't end this phase yet" and `phase.drop_objection(this)` to release. Counts propagate **up the component tree** to `uvm_top`; when the *total* reaches zero, the phase begins to end. Normally only the test (and sometimes sequences) raises objections, not every driver; drivers and monitors loop forever and are simply killed at phase end.


### The factory: why not just `new`?

**In plain words:** `new` is **building the chair yourself**. The factory is **ordering "a chair" from a catalogue**. Because you ordered by name, the shop manager (the test) can quietly say "whenever someone orders *chair*, send the *deluxe chair* instead" — and the people placing orders never change a line of code. That is the entire point: swap a part without editing the code that uses it. (Ordering by name is why you write `X::type_id::create(...)` instead of `new(...)`.)


`new` hard-codes the class at the call site. The factory is a lookup table keyed by class name: `T::type_id::create("name", parent)` consults it, and the test can say "wherever the env creates a `mcpu_scoreboard`, give me a `mcpu_strict_scoreboard`" **without touching the env**. That is the mechanism behind swapping a bus-functional driver for an error-injecting one, or a simple memory model for a latency-modelling one.


---

## UVM Mechanics

### Phase execution

Each phase is an object (`uvm_phase`), organised in a schedule. For a function phase the library walks the component tree in the stated direction, calling the callback on each. For `run_phase`, it forks `run_phase(phase)` of **every** component at the same time and waits. Calling `super.build_phase(phase)` first runs the base-class work (for `uvm_component`, configuration application is **SIMULATOR/VERSION-DEPENDENT** in detail) — always do it.

Because `build_phase` is top-down, a parent that sets a field on a child right after `create` (for example `leaf_a.busy_ns = 10`) is safe: the child's own `build_phase` has not run yet and will see it. Conversely a child must never assume it can configure its parent.


### What ends the run phase

1. Components raise/drop objections; each call updates counts for the component and all its ancestors.
2. When the total reaches zero, UVM waits the **drain time** (default 0; set per component with `phase.phase_done.set_drain_time(obj, time)`), so late activity (a monitor catching the last response) can finish.
3. `phase_ready_to_end(uvm_phase phase)` callbacks give components a last chance to re-raise an objection (rare).
4. If the count is still zero, the phase ends: every still-running `run_phase` process (drivers' `forever` loops, etc.) is **killed**, and the next phase begins.

If nothing ever raises an objection the run phase ends at time 0 (Module 01's pitfall). If an objection is never dropped the phase never ends; the global timeout `uvm_top.set_timeout(time, overridable)` is a backstop. The default timeout is a very large value (macro `UVM_DEFAULT_TIMEOUT`; exact default and the fatal ID, `PH_TIMEOUT`, are **SIMULATOR/VERSION-DEPENDENT**) so a hung test normally looks like a hang, not a clean failure. Set a realistic timeout in your base test.


### Factory registration and lookup

`` `uvm_component_utils(T) `` registers `T` in the factory under the string `"T"` and defines `T::type_id`. `T::type_id::create(name, parent)` asks the factory for the class that should replace `T` at that hierarchical position, builds it, and returns it **cast back to `T`** — which is why an override type must be a subclass of `T`.

| Override kind | Call (on `T::type_id`) | Effect |
|---|---|---|
| Type override | `set_type_override(Sub::get_type())` | every `create` of `T` anywhere produces `Sub` |
| Instance override | `set_inst_override(Sub::get_type(), "full.path")` | only a `create` whose full name matches the path |

Rules (**PORTABLE UVM CONCEPT**):
- **Instance overrides beat type overrides.**
- An override must be registered **before** the `create` it should affect; `build_phase` is top-down, so the test (top) registers overrides before the env is created.
- Only `create` is affected. `new()` bypasses the factory.
- A second type override for the same type replaces the first (`replace` defaults to 1).
- The factory has by-name variants (`set_type_override_by_name`, `set_inst_override_by_name`) for use from the command line or strings; prefer the typed forms in code because the compiler checks them.

Debugging: `uvm_factory::get().print()` (UVM 1.2; **SIMULATOR/VERSION-DEPENDENT** for older libraries) lists registered types and active overrides. Printing `get_type_name()` in `build_phase` (as in `example02.sv`) is the quickest check.


---

## Code Walkthrough

**A picture before the code — the timeline of `example01.sv`** (time in ns; each `|` is a "BUSY sign" held):

```
 time   0        5       10  12       24  25        36        45
 test   |--------X                                               (holds sign 0..5)
 leaf_a |----------------X                                        (0..10)
 leaf_b |-------------------------------X                         (0..25)
 mid    heartbeat:          *           *            *    (kill)  (no sign; just a loop)
                                          last sign down at 25 --> +20 ns drain --> phase ends at 45
```

Questions to ask while reading the code: *Who holds a sign, and until when? When does the LAST one come down? What happens to the loop that never ends?* (Answers: test/leaf_a/leaf_b hold signs; the last drops at 25; the endless heartbeat is simply stopped when the phase ends.)


### 1. Build top-down, connect bottom-up (`example01.sv`)

Each probe logs in `build_phase` and `connect_phase`. Expected order (hand-derived):

```
build   : test -> mid -> leaf_a -> leaf_b
connect : leaf_a -> leaf_b -> mid -> test
```

Why this matters in practice: the parent's `build_phase` creates `leaf_a`/`leaf_b` and then assigns `busy_ns` — a configuration hand-off that only works because the children's `build_phase` comes later.


### 2. Objections across a hierarchy

```systemverilog
task run_phase(uvm_phase phase);      // in mcpu_probe_leaf
  phase.raise_objection(this, "leaf busy");
  #(busy_ns * 1ns);
  `uvm_info("PH", "run work done", UVM_LOW)
  phase.drop_objection(this, "leaf done");
endtask
```

Three components raise at time 0 (test, `leaf_a`, `leaf_b`); `mid` raises none. Test drops at 5, `leaf_a` at 10, `leaf_b` at 25. The total reaches zero only at 25, so the run phase cannot end earlier even though the test finished at 5. **The phase lasts as long as the slowest objector.**


### 3. Drain time and the killed `run_phase`

```systemverilog
phase.phase_done.set_drain_time(this, 20ns);
```

At 25 all objections are down; the 20 ns drain keeps the phase open until 45. `mid`'s `forever` heartbeat prints at 12, 24, 36 — the one at 36 falls inside the drain window. At 45 the phase ends and `mid`'s task is killed, so the heartbeat at 48 never prints. `report_phase` then runs at 45 ns. Moral: infinite loops in drivers/monitors are fine, because phase end kills them; but anything that must finish (flushing the last scoreboard check) needs either an objection or drain time.


### 4. `type_id::create` and overrides (`example02.sv`)

```systemverilog
mcpu_scoreboard::type_id::set_type_override(mcpu_verbose_scoreboard::get_type());
mcpu_scoreboard::type_id::set_inst_override(mcpu_strict_scoreboard::get_type(), "uvm_test_top.env.sb_b");
env = mcpu_ovr_env::type_id::create("env", this);
```

Both overrides come **before** `env` is created. Env then creates `sb_a` and `sb_b` through the factory and `sb_c` with `new`.


### 5. Reading the result

| Instance | Created by | Result | Reason |
|---|---|---|---|
| `sb_a` | `type_id::create` | `mcpu_verbose_scoreboard` | type override applies |
| `sb_b` | `type_id::create` | `mcpu_strict_scoreboard` | instance override beats type override |
| `sb_c` | `new` | `mcpu_scoreboard` | factory not consulted |


---

## Common Pitfalls

- **Override registered after the `create`** → log shows the original class (`I am mcpu_scoreboard`) and no error → the factory consults overrides only at `create` time; move the override earlier (usually into the test's `build_phase`, before the env is created).
- **`new()` instead of `type_id::create`** → override silently ignored for that one instance → `new` never calls the factory. Search for `= new(` in components during review.
- **Instance override path typo or missing `uvm_test_top.` prefix** → override has no effect, no message → paths are full hierarchical names; print `get_full_name()` to see the real string.
- **Override class not derived from the original** → compile error on the typed form, or a fatal when the factory casts back by-name (message library-specific) → `create` returns a handle of the original type.
- **Objection never dropped (early `return`, `disable`, error path)** → simulation keeps running; periodic messages continue; no end → the count never reaches zero; use a single drop point, or `fork ... join` structure that cannot skip it.
- **Objection raised after the first delay** → test ends at time 0 (Module 01) → raise at the top of `run_phase`.
- **Work that must finish runs in a component with no objection and no drain time** → last scoreboard check or log line missing from the end of the log → phase end kills the task; add an objection in that component or set drain time.
- **Forgetting `super.<phase>_phase(phase)`** → typically silent; configuration/automation from the base class missing (**SIMULATOR/VERSION-DEPENDENT**) → call it first in every phase override.


---

## Interview Angle

**Q1. Why is `build_phase` top-down and `connect_phase` bottom-up?**
A parent creates its children in `build`, so it must run first. `connect` runs after the whole tree exists; bottom-up lets a parent assume its children's own internal connections are already done before it wires them together.

**Q2. How does a test decide when simulation ends?**
By objections: it raises one at the start of `run_phase` and drops it when its stimulus is done. The phase ends when all objections (propagated up the hierarchy) are zero, after any drain time; then all `run_phase` tasks are killed.

**Q3. What is drain time and when do you need it?**
Extra time the phase stays open after the last objection drops, so in-flight activity (monitors, scoreboard, DUT latency) completes. Needed when the DUT still has outputs to produce after the last stimulus, e.g. a CPU pipeline draining retire trace after the last instruction is fetched.

**Q4. Type override vs instance override — which wins, and what is the use case for each?**
Instance wins. Type override swaps every instance (e.g. use an error-injecting driver everywhere); instance override swaps one place (e.g. a strict scoreboard only on the LSU path).

**Q5. My override isn't taking effect. Walk me through debugging.**
Check it is set before the create; check the object is created with `type_id::create`, not `new`; check the path string against `get_full_name()`; check the replacement class is registered and derived from the original; print `get_type_name()` or the factory contents.

**Q6. Test hangs forever. What do you check?**
An objection raised but never dropped (look at every exit path), a sequence that never finishes (blocked on a handshake), and whether a timeout is set so it fails cleanly.


---

## Recap in five lines

1. Phases are the **fixed order** of a testbench's life; only `run_phase` consumes time.
2. **Build** goes parents-first, **connect** goes children-first; nobody advances until all are done.
3. **Objections** are "BUSY" signs: the run phase ends when the last one drops (plus drain time).
4. The **factory** lets a test swap a class **by name**; `new` skips the factory, so overrides don't reach it.
5. Overrides must be registered **before** the `create` they should affect; **instance beats type**.

**Questions beginners often ask**
- *"Why did my override do nothing?"* — print `get_type_name()`; usual causes: `new` was used, the override came after the create, or the path string is wrong.
- *"Why does my endless `forever` loop not hang the simulation?"* — it is stopped when the run phase ends; only an *undropped objection* keeps the phase alive.
- *"Why is the run phase longer than my test's own delay?"* — it lasts until the **slowest** sign holder drops, plus drain time.


---

## Check Your Understanding

1. In `example01.sv`, suppose `set_drain_time` is deleted. At what time does `report_phase` run, and does the 36 ns heartbeat still print?
2. A teammate registers a type override from inside the **env's** `connect_phase`, then wonders why nothing changes. Explain precisely.
3. In `example02.sv`, change the instance override path to `"env.sb_b"` (no `uvm_test_top.`). Predict the three `[SB]` lines and explain.

Answers: `solutions/module02/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Complete a test that registers an instance override and keeps late activity alive with drain time. Includes a subtle trap. |
| `exercise02.md` | Debug the testbench | Two symptoms: an override that "does nothing" and a simulation that never ends. |
| `exercise03.md` | Predict the log | A three-level hierarchy with mixed objections; predict phase order, times, and which messages never appear. |


---

## Reference

**Classes:** `uvm_phase`, `uvm_objection` (via `phase.phase_done`), `uvm_factory`, `uvm_component_registry`, `uvm_object_wrapper`, `uvm_root` (`uvm_top`), `uvm_scoreboard`, `uvm_env`, `uvm_test`.

**Phase callbacks:** `build_phase`, `connect_phase`, `end_of_elaboration_phase`, `start_of_simulation_phase`, `run_phase`, `extract_phase`, `check_phase`, `report_phase`, `final_phase`; run-time: `reset_phase`, `main_phase`, etc.; `phase_ready_to_end`.

**Methods:** `phase.raise_objection(obj, desc, count)`, `phase.drop_objection(obj, desc, count)`, `phase.phase_done.set_drain_time(obj, time)`, `uvm_top.set_timeout(time, overridable)`, `T::type_id::create(name, parent)`, `T::type_id::set_type_override(wrapper)`, `T::type_id::set_inst_override(wrapper, path)`, `T::get_type()`, `get_type_name()`, `get_full_name()`, `uvm_factory::get().print()`.

**Macros:** `` `uvm_component_utils ``, `` `uvm_info ``.

**Forward references made:** TLM connections in `connect_phase` (Module 05); sequences started from `run_phase` (Module 03); reset in `run_phase` and timeout policy (Module 10).
