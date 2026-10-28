# Module 01 — UVM Big Picture & Testbench Architecture

> Prerequisites: SystemVerilog classes, interfaces, `initial`/`always`, basic testbench experience.
> What this module gives you: a mental map of a layered UVM testbench for a CPU, the vocabulary to describe it, and a first running `uvm_test` built around `mini_cpu`.

All code is UVM 1.2 (IEEE 1800.2-2017). Nothing here was simulated; logs are hand-derived.
Labels used throughout: **PORTABLE UVM CONCEPT** (true for any compliant tool) and **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

Imagine you are testing a brand-new **calculator chip** (our `mini_cpu`). You cannot just stare at it. You build a **test robot** with four jobs:

| The robot's job | Everyday version | UVM name | Module |
|---|---|---|---|
| Press the buttons | type `5 + 7 =` | **driver** (fed by **sequences**) | 3–4 |
| Watch the display | read what the chip shows | **monitor** | 4 |
| Know the right answer | a trusted calculator next to it | **reference model** | 6 |
| Compare and complain | "chip says 13, trusted says 12!" | **scoreboard** | 6 |

Plus a **test** that decides *which* experiment to run today ("try 100 random sums"), and an **environment** that holds the robot's parts together.

**UVM is just an agreed blueprint for building that robot out of interchangeable parts**, so that every verification engineer in the world names and arranges the parts the same way. That is all. In this module we build only the *skeleton* (a test, wires to the chip, a start button) and watch it run.

**Why not just write one big `initial` block?** It works for a 10-line demo. But the moment you want to swap the stimulus, reuse the monitor on another chip, or run 1,000 different tests, one big block has to be rewritten. UVM's parts let you change one thing without touching the rest.


### Why UVM exists

A hand-written SV testbench works until the second project. UVM is a **class library** (package `uvm_pkg`, shipped with every simulator) that standardises the plumbing so that testbench parts become reusable and swappable:

| Problem in ad-hoc testbenches | UVM answer |
|---|---|
| Every team invents its own build/run/shutdown order | **Phases** (Module 02) |
| Changing a driver or sequence means editing the TB | **Factory** overrides (Module 02) |
| Parameters passed through long constructor chains | **`uvm_config_db`** (Module 05) |
| Stimulus welded to protocol pin-wiggling | **Sequences** separated from **drivers** (Modules 03–04) |
| Monitors hard-wired to checkers | **TLM analysis ports** (Modules 05–06) |
| Everyone logs differently | **Reporting** (`uvm_info` family) |

**PORTABLE UVM CONCEPT:** UVM is not a language feature and not a simulator feature. It is SystemVerilog source code. If you can read SV classes, you can read the library.


### The DUT used in this course: `mini_cpu`

A fictional 32-bit, single-issue, in-order RISC-style core with RISC-V-flavoured instructions (ADD, LW, SW, BEQ, CSRRW). Four things matter to the testbench:

| Interface group | Signals (in `mini_cpu_if`) | Direction (DUT's view) |
|---|---|---|
| Instruction fetch bus | `if_req`, `if_addr`, `if_rvalid`, `if_rdata` | req/addr out; rvalid/rdata in |
| Load/store bus | `ls_req`, `ls_we`, `ls_addr`, `ls_wdata`, `ls_rvalid`, `ls_rdata` | req/we/addr/wdata out; rvalid/rdata in |
| Interrupt | `irq` | in |
| Retire trace | `retire_valid`, `retire_pc`, `retire_instr`, `retire_rd`, `retire_data` | out |

plus `clk` and active-low `rst_n`. The **retire trace** is the key to CPU verification: it reports, per retired instruction, what architecturally happened. Comparing it with a reference model is the core checking strategy of Module 06. (CSRs and their register model come in Module 09.)


### The layered testbench

```
                       +-------------------------- mcpu_base_test (uvm_test) ---------------------------+
                       |   chooses env config + which sequences run                                      |
                       |  +------------------------------ mcpu_env (uvm_env) ------------------------+  |
                       |  |                                                                           |  |
                       |  |  mcpu_ifetch_agent        mcpu_lsu_agent          mcpu_scoreboard         |  |
                       |  |  (memory-side:            (memory-side:           + reference model       |  |
                       |  |   answers fetches)         answers load/store)    + coverage subscribers  |  |
                       |  |   sequencer-driver-monitor  sequencer-driver-monitor                      |  |
                       |  |        |    ^                    |    ^        retire monitor --> compare  |  |
                       |  +--------|----|--------------------|----|---------------------|-------------+  |
                       +-----------|----|--------------------|----|---------------------|----------------+
                                   v    |                    v    |                     |
                             +----------------------- mini_cpu_if (virtual interface) ---------------+
                             +----------------------------- mini_cpu (DUT) --------------------------+
```

Read it bottom-up: pins ⇄ driver/monitor (signal level) ⇄ sequencer/sequence (transaction level) ⇄ test (intent level). Note that for a CPU, the "stimulus" at the pins is mostly the *memory system answering the CPU*: the program is delivered as data on the fetch bus. Module 03 and 07 cover how instruction streams are generated.


### Components vs. objects — the split everything else hangs on

**In plain words:** think of a lab. **Components** are the *furniture and staff*: they are there from opening time to closing time, and each has a fixed place on the org chart (the test sits above the environment, which sits above the agents). **Objects** are the *paper forms* the staff pass around — one form per job, thrown away afterwards (one per instruction, one per sequence). A quick tell: if its constructor needs a **parent**, it is a component; if it only needs a name, it is an object.

| | `uvm_component` | `uvm_object` |
|---|---|---|
| Lifetime | Whole simulation; created in `build_phase` | Created and discarded dynamically |
| Position | Has a **parent**; forms a static tree | None |
| Constructor | `new(string name, uvm_component parent)` | `new(string name = "")` |
| Phases | Yes (`build_phase`, `run_phase`, ...) | No |
| Examples | test, env, agent, driver, monitor, scoreboard | sequence item, sequence, config object, register model |

Class lineage (**PORTABLE UVM CONCEPT**): `uvm_void` → `uvm_object` → `uvm_report_object` → `uvm_component` → {`uvm_test`, `uvm_env`, `uvm_agent`, `uvm_driver`, `uvm_monitor`, `uvm_scoreboard`, ...}. `uvm_sequence_item` descends from `uvm_object` (via `uvm_transaction`).

Rule of thumb: *if it must exist before time starts and receives phase callbacks, it is a component; if you make one per instruction, it is an object.*


### Two worlds and the bridge between them

**In plain words:** the chip and its wires live in one room (hardware: modules and interfaces). The test robot lives in another room (software: classes). A class cannot reach through the wall and touch a wire. The **virtual interface** is like a **remote control** that `tb_top` hands to the robot: pressing buttons on the remote moves the real wires. No remote, no control — which is why a missing `vif` is the first thing to check when a test "does nothing".

SystemVerilog has a **static world** (modules, interfaces, clocks, the DUT) and a **dynamic world** (classes). Classes cannot instantiate modules or reference them by hierarchical path portably. The bridge is the **virtual interface**: a handle to an interface instance, passed into the class world (we use `uvm_config_db`, detailed in Module 05). `tb_top` lives in the static world: it makes the clock, the DUT and the interface, stores the handle, and calls `run_test()`.


---

## UVM Mechanics

### What `run_test()` does

**In plain words:** `run_test()` is the **Start button**. `tb_top` first sets up the lab (clock, chip, remote control), then presses Start; UVM then builds the test robot, lets it run, tidies up, and switches the lights off (`$finish`). You never call `run_phase` yourself — UVM calls it for you.

`run_test` is a task in `uvm_pkg`, called from the static world (usually an `initial` in `tb_top`). Its job, in order:

1. Get the test class name — from the argument, or from the `+UVM_TESTNAME=<name>` plusarg (**SIMULATOR/VERSION-DEPENDENT**: which wins when both are given differs between library versions; do not rely on it — pass `""` to `run_test()` and use only the plusarg, or vice versa).
2. Ask the **factory** to create that class with instance name **`uvm_test_top`** and parent `uvm_top` (the singleton `uvm_root`, the invisible root of every hierarchy).
3. Execute the phase schedule (list below) across the whole tree.
4. When the run phase ends, execute the cleanup phases, print the report summary, and call `$finish`.

If the name is not registered with the factory you get a `UVM_FATAL` with ID `INVTST` and nothing else runs.


### What `` `uvm_component_utils(T) `` does

It expands (approximately — exact text is library source) into: a `typedef uvm_component_registry#(T,"T") type_id;`, a static `get_type()`, and virtual `get_type_name()` / `get_object_type()` methods. The `type_id` typedef is what lets you write `T::type_id::create(...)`, and the registration is a static initialisation that adds `T` to the factory's name table before simulation time 0. `` `uvm_object_utils `` does the same with `uvm_object_registry`. Without the macro the class cannot be created by name or overridden.


### The phase schedule (preview — Module 02 is the deep dive)

| Phase | Kind | Direction | Typical use |
|---|---|---|---|
| `build_phase` | function | top-down | create children, get config |
| `connect_phase` | function | bottom-up | connect TLM ports |
| `end_of_elaboration_phase` | function | bottom-up | print topology, final tweaks |
| `start_of_simulation_phase` | function | bottom-up | last pre-run setup |
| `run_phase` | **task** | parallel | stimulus, monitoring, checking |
| `extract_phase` / `check_phase` | function | bottom-up | gather results, final checks |
| `report_phase` / `final_phase` | function | `report`: bottom-up; `final`: top-down | summaries |

Only `run_phase` consumes simulation time. All `run_phase` tasks of all components start together at the same time.

**Objections (minimal version):** the run phase ends when *no component is objecting*. A test therefore wraps its time-consuming work in `phase.raise_objection(this)` … `phase.drop_objection(this)`. If nobody ever raises one, the run phase ends at time 0. Module 02 covers drain time and best practice.


### Reporting

**How to read one log line** — every message you will meet in the course has the same five parts:

```
UVM_INFO example01.sv(106) @ 0: uvm_test_top [RUN] waiting for reset release
^^^^^^^^ ^^^^^^^^^^^^^^^^^   ^   ^^^^^^^^^^^^ ^^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^
severity  file and line      time who said it  tag   the message text
```

"Who said it" is the component's hierarchical name — it tells you *where in the tree* to look. The **tag** (ID) is what you search for. Learn to read these five parts in this order and debugging gets much easier.


`` `uvm_info(ID, MSG, VERBOSITY) `` prints only if the message verbosity ≤ the component's verbosity threshold (default `UVM_MEDIUM`; `UVM_LOW` prints, `UVM_HIGH` does not). Format:

```
UVM_INFO <file>(<line>) @ <time>: <hierarchical path> [<ID>] <message>
```

Companions: `` `uvm_warning ``, `` `uvm_error `` (counts toward the error total; whether the sim stops is configurable), `` `uvm_fatal `` (ends the simulation). The `+UVM_VERBOSITY=UVM_HIGH` plusarg raises verbosity globally.


### Construction and the hierarchy

`super.new(name, parent)` registers the child in the parent's table; the **full name** is `parent.get_full_name() + "." + name`. This path string is what appears in the log, what `uvm_config_db` matches against, and what instance-specific factory overrides use. Get names right from day one.


---

## Code Walkthrough

**How to read `example01.sv` — five blocks, top to bottom:**

1. `interface mini_cpu_if` — the **bundle of wires** (think: the chip's socket).
2. `module mini_cpu` — a **fake chip** that only exists so there is something to watch.
3. `package mcpu_pkg` / `class mcpu_base_test` — the **test robot** (class world).
4. `module tb_top` — the **lab**: makes the clock and reset, plugs the chip in, hands over the remote control, presses Start.
5. The comment block at the end — the **log you should see**, derived by hand.

Read blocks 4 → 3 → 1 first; block 2 is just scenery.


### 1. The interface and the static side (`example01.sv`)

`mini_cpu_if` gathers every DUT-facing signal; the DUT takes it through the `dut` modport, so the compiler checks directions. `tb_top` owns time-0 things:

```systemverilog
mini_cpu_if vif (.clk(clk), .rst_n(rst_n));
mini_cpu    dut (.bus(vif));
```

The `always @(posedge clk)` responder in `tb_top` is a stand-in for the fetch-side memory; in a real TB that behaviour belongs to a UVM agent (Module 04), not to `tb_top`.


### 2. The hand-off to UVM

```systemverilog
uvm_config_db#(virtual mini_cpu_if)::set(null, "uvm_test_top", "vif", vif);
run_test("mcpu_base_test");
```

Why this order: `set` must happen before the test's `build_phase` runs its `get`; `run_test` starts the build phase. `null` as the context means "the `inst_name` argument is an absolute path from the root"; `"uvm_test_top"` is the instance name from step 2 above; `"vif"` is the field name. All three, plus the type parameter, must match the `get` for it to succeed (Module 05).


### 3. The test class

```systemverilog
class mcpu_base_test extends uvm_test;
  `uvm_component_utils(mcpu_base_test)
  virtual mini_cpu_if vif;
  function new(string name = "mcpu_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
```

Every component repeats this pattern: macro, handle declarations, constructor that only calls `super.new`. No other work belongs in the constructor — children are created in `build_phase`, because the library controls when that happens.

```systemverilog
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(virtual mini_cpu_if)::get(this, "", "vif", vif))
    `uvm_fatal("NOVIF", "virtual interface 'vif' not found in config_db")
```

`get` returns a bit: 1 if found. Ignoring it means a null `vif` and a confusing null-dereference later. A fatal with a clear ID at the point of failure is the standard habit.


### 4. The run phase

```systemverilog
phase.raise_objection(this, "mcpu_base_test running");
@(posedge vif.rst_n);
repeat (5) begin
  @(posedge vif.clk);
  while (!vif.retire_valid) @(posedge vif.clk);
  `uvm_info("RUN", $sformatf("retire pc=0x%08h instr=0x%08h", vif.retire_pc, vif.retire_instr), UVM_LOW)
end
phase.drop_objection(this, "observed 5 retires");
```

The objection is raised **before** the first delay. If it were raised after `@(posedge vif.rst_n)`, the run phase could already have ended at time 0. The test reads signals directly only for demonstration; observing the DUT is a **monitor's** job (Module 04).

The hand-derived timing (see the end of `example01.sv`): reset releases at 42 ns, first retire is sampled at 75 ns, then one per 10 ns, so the fifth is at 115 ns and the run phase ends there.


### 5. Hierarchy and objects (`example02.sv`)

```systemverilog
env  = mcpu_env::type_id::create("env", this);          // component: name + parent
info = mcpu_run_info::type_id::create("info");          // object: name only
```

`this.print()` shows `env`, its three children, and **not** `info`: only components are in the tree. `uvm_test_top` has one child, `env`, and `env` has `ifetch_agent`, `lsu_agent`, `scoreboard`. Those instance names are reused for the rest of the course; Module 02 shows why `type_id::create` rather than `new`.


---

## Common Pitfalls

- **Forgot `` `uvm_component_utils `` on the test** → `UVM_FATAL [INVTST]` at time 0, no phases run → the class was never registered, so the factory cannot find it by name.
- **No objection raised in the test** → simulation "passes" at time 0; your `run_phase` messages after the first delay never appear → the run phase ends as soon as every `run_phase` has no objection, regardless of what tasks are still running.
- **Objection raised after a delay or event** → intermittent early end, or end at time 0 → the phase can end before the raise executes. Raise first, then wait.
- **`get` result unchecked and `set` path or field name mismatched** → no message at `build`, later a null-handle error at the first `vif` use (wording is simulator-dependent) → `config_db` silently returns 0 on a miss.
- **Missing `super.build_phase(phase)`** → usually silent in small examples; later, configuration applied by automation (e.g. `uvm_field_*` configuration) may not appear in the component (**SIMULATOR/VERSION-DEPENDENT**) → the base-class method does that work. Always call `super.*_phase` first.
- **Component constructor with the wrong signature** (e.g. `new(string name)`) → compile error, or factory `create` fails to compile against the registry → components must be `new(string name, uvm_component parent)`.
- **Missing `` `include "uvm_macros.svh" ``** (or `import uvm_pkg::*`) → compile errors on `` `uvm_info `` and `uvm_component` → macros are preprocessor text; the package import does not provide them.
- **Class code reaches the DUT with a hierarchical path** (`tb_top.dut.pc`) → works once, breaks when the DUT instance is renamed or the env is reused; races with the clock appear → the virtual interface exists to prevent exactly this.


---

## Interview Angle

**Q1. Why does UVM separate `uvm_component` from `uvm_object`?**
Components form a static hierarchy built before the run and receive phase callbacks; objects are lightweight data created dynamically (items, sequences, configs) with no parent or phases. The split gives you a stable structure to configure and override, and cheap transient data.

**Q2. Walk me through what happens from `run_test()` to the end of simulation.**
The factory creates the test as `uvm_test_top`; `build_phase` runs top-down creating the tree; `connect`, `end_of_elaboration`, `start_of_simulation` follow; `run_phase` of all components starts in parallel at time 0 and continues until all objections drop; then `extract`, `check`, `report`, `final`, and `$finish`.

**Q3. How does a class-based testbench talk to pins?**
Through a virtual interface handle, set by the top module into `uvm_config_db` and retrieved in the component's `build_phase`. Drivers drive and monitors sample through it. No hierarchical paths into the DUT.

**Q4. My test finishes at time 0 with no errors. What do you check first?**
Whether any component raised an objection in `run_phase`, and whether it was raised before any delay. Then check the log for `INVTST` or a silent `get` failure.

**Q5. Where would you put the reference model and checking in a CPU testbench, and why not in the driver?**
In the scoreboard side, fed by monitors (retire trace and bus monitors) via analysis ports. The driver only knows what it sent; checking from the monitor's observation is independent of stimulus, so it keeps working when stimulus is random, directed or replaced.

**Q6. What is the difference between a UVM test and an environment?**
The env is the reusable testbench structure; the test chooses configuration, overrides and which stimulus runs. Many tests, one env.


---

## Recap in five lines

1. UVM is a **blueprint for a test robot**: drive, watch, know the answer, compare.
2. **Components** = staff with a place in the tree; **objects** = paper forms passed around.
3. `tb_top` builds the *hardware* side and hands a **virtual interface** (remote control) to the test.
4. `run_test()` is the **Start button**; the test must **raise an objection** or the run ends at time 0.
5. A **log line** = severity, file, time, *who*, tag, message — read it left to right.

**Questions beginners often ask**
- *"Why isn't the test just written in `tb_top`?"* — `tb_top` is hardware; classes (the test) give you phases, the factory and reuse.
- *"Why can't I call `new` on the test myself?"* — then UVM would not know about it: no phases, no place in the tree. `run_test` creates it for you.
- *"Why did my test finish at time 0 with no error?"* — nobody raised an objection, so UVM saw nothing left to wait for.


---

## Check Your Understanding

1. In `example01.sv`, at what simulation time does the third `retire` message print, and which instruction address does it show? Derive it; do not just read the trace.
2. If you delete both `phase.raise_objection` and `phase.drop_objection` from `mcpu_base_test`, which lines of the expected log still appear, and at what times? Do the `extract`/`check`/`report` phases still run?
3. A teammate proposes making `cpu_instr_item` (one per instruction) a `uvm_component` "so it shows up in the topology". Give two concrete reasons this is wrong.

Answers: `solutions/module01/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Complete `mcpu_smoke_test`: registration, constructor, config retrieval, and objection placement. Includes a subtle trap. |
| `exercise02.md` | Debug the testbench | Two symptoms from one testbench: a fatal at time 0, then a test that ends at time 0 after the first fix. |
| `exercise03.md` | Design / interview write-up | Whiteboard the `mini_cpu` UVM testbench: components, objects, phases, and where the reference model attaches. |


---

## Reference

**Classes:** `uvm_pkg`, `uvm_test`, `uvm_env`, `uvm_agent`, `uvm_scoreboard`, `uvm_component`, `uvm_object`, `uvm_phase`, `uvm_root` (`uvm_top`), `uvm_config_db#(T)`, `uvm_component_registry` / `uvm_object_registry` (via macros).

**Macros:** `` `uvm_component_utils ``, `` `uvm_object_utils ``, `` `uvm_info ``, `` `uvm_fatal ``, and the `` `include "uvm_macros.svh" `` file.

**Methods / tasks:** `run_test()`, `type_id::create(name, parent)`, `uvm_config_db#(T)::set(cntxt, inst_name, field_name, value)`, `uvm_config_db#(T)::get(cntxt, inst_name, field_name, variable)`, `build_phase`, `end_of_elaboration_phase`, `run_phase`, `report_phase`, `phase.raise_objection(obj, description)`, `phase.drop_objection(obj, description)`, `uvm_object::print()`, `uvm_object::convert2string()`, `super.new(name, parent)`.

**Plusargs:** `+UVM_TESTNAME`, `+UVM_VERBOSITY` (behaviour on conflicts: **SIMULATOR/VERSION-DEPENDENT**).

**Forward references made:** phases, objections, factory overrides (Module 02); `cpu_instr_item`, sequences (Module 03); driver/monitor/agent bodies (Module 04); `uvm_config_db` details, TLM (Module 05); scoreboard and reference model (Module 06); CSRs (Module 09).
