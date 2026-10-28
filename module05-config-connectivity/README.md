# Module 05 — Configuration & Connectivity

> Prerequisites: Modules 01–04 (phases, factory, config object and `config_db` use in Module 04, analysis port and `uvm_subscriber`).
> What this module gives you: a precise model of how `uvm_config_db` resolves a `set`/`get` pair (and why it silently fails), and how TLM connects components: ports, exports, imps, analysis ports and FIFOs.

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

The testbench's parts need to **find each other** and **pass things along**. UVM gives two systems:

- **`config_db` = a noticeboard.** Someone pins a note ("to: `env.ifetch_agent`, field `cfg`, here is the config object"). Later the addressee looks for notes addressed to it. A note with a typo in the address is **not rejected — it just sits there unread**, and the addressee quietly falls back to its defaults.
- **TLM = pipes between rooms.** A monitor drops what it saw into a pipe; whoever is connected to the other end receives it. One pipe (the *analysis port*) can have many taps. A pipe with **no taps** doesn't complain either.

Both systems fail **silently**, which is why this module teaches you to print what you received and to count what arrived.


### Two kinds of plumbing

| Plumbing | Carries | Mechanism | Fails how |
|---|---|---|---|
| Configuration | settings, handles (vif, config objects) | `uvm_config_db` | silently: `get` returns 0 and your default stays |
| Connectivity | transactions between components | TLM ports/exports/imps | some mistakes are errors at end of elaboration; **analysis ports unconnected is not an error** |

Both are set up before time 0, both are matched by *names* (paths, field names, types), and both reward the same habit: **check the result and print what you got**.


### `uvm_config_db` in one paragraph

A global database of typed entries. `set(cntxt, inst_name, field_name, value)` stores a value that components matching a path may later `get`. A match needs **all four** of: the type `T` in `uvm_config_db#(T)`, the field name, the path (computed from context + `inst_name`), and the entry existing *at the time of the `get`*. Any mismatch → `get` returns 0 and leaves the variable untouched.


---

## UVM Mechanics

### Path resolution (**PORTABLE UVM CONCEPT**)

`set(cntxt, inst_name, field_name, value)` — the **scope** being addressed is:

| `cntxt` | scope = |
|---|---|
| a component (`this`) | `cntxt.get_full_name()` + `"."` + `inst_name` (just `cntxt`'s name if `inst_name` is `""`) |
| `null` | `inst_name` taken as an **absolute** path from the root (e.g. `"uvm_test_top.env.agent_a"`) |

`get(cntxt, inst_name, field_name, value)` builds a scope the same way, normally `get(this, "", "field", var)`: "values addressed to me".

The classic error: `set(this, "uvm_test_top.env.agent_a", ...)` from the test. With a component context the string is *appended* to the test's name, producing `uvm_test_top.uvm_test_top.env.agent_a`, which matches nothing. Use a relative path with `this`, or an absolute path with `null`.

**Wildcards.** `inst_name` is a glob: `*` matches any run of characters (including dots), `?` one character. `"env.*"` addresses everything below `env`; `"*"` addresses everything under the context; `"*.vif"`-style fragments are easy to over-match. Broad wildcards are convenient and the leading cause of "who changed my setting?".


### Precedence

**In plain words:** if two notes for the same field are on the board, **the note from the higher boss wins** (the test outranks the env). If two notes come from the same person, the later one wins. It is a chain of command, not a vote.

When several `set` entries match one `get` (**PORTABLE UVM CONCEPT**, with equal-level tie-breaking as the corner case):
1. A `set` made from a context **higher in the hierarchy wins** over one from a lower context (the test overrides the env). This is deliberate: the test is the top-level authority.
2. For sets from the **same** context to the same field, the **last one wins**.
3. Wildcard versus exact path does **not** by itself raise precedence; depth of the *context* does.

Tie-breaking beyond that (same depth, different contexts) is **SIMULATOR/VERSION-DEPENDENT**; do not design for it.


### Timing and order

`build_phase` is top-down. A `set` is visible to a `get` only if it has executed first. `type_id::create` only *constructs* the child; the child's own `build_phase` runs later, after the parent's `build_phase` has returned. So the real deadline for a `set` is "before the **target's** `build_phase` starts": any position inside an ancestor's `build_phase` works, including after the `create` call, but a `set` made in a later phase (`connect_phase`, `end_of_elaboration_phase`, `run_phase`) is too late for anything read in `build_phase`. The robust habit, used throughout this course: **make every `set` before the matching `create`** and only in `build_phase`, so no reader has to reason about the deadline.


### Types

`uvm_config_db#(int)` and `uvm_config_db#(int unsigned)` are different classes with different pools. A value set as `int` is invisible to a `get` of `int unsigned`, `bit [31:0]` or `longint`. For handles the type must match exactly: `uvm_config_db#(mcpu_agent_cfg)` is not `uvm_config_db#(uvm_object)`. Virtual interfaces are stored as `uvm_config_db#(virtual mini_cpu_if)`.


### What to store

| Value | Pattern |
|---|---|
| Virtual interface | set once from `tb_top` (context `null`, absolute path `"uvm_test_top"`), get in the test, pass on inside a config object |
| Several related settings | one **config object** (Module 04's `mcpu_agent_cfg`), one `set`, one `get` |
| Single scalar knob | `uvm_config_db#(int)`, `#(string)`, … |

Avoid broadcasting `vif` with `"*"`: every component then depends on a global.


### Debugging config_db

`+UVM_CONFIG_DB_TRACE` prints every `set`/`get` with scope, field and whether it matched. `print_config(1)` on a component lists the settings visible to it (`print_config_matches` and `print_config` details are **SIMULATOR/VERSION-DEPENDENT**). The cheapest tool: print what `get` returned, and whether it found anything.


### TLM: ports, exports, imps

**In plain words:** a **port** is a *mouth* (it speaks), an **imp** is an *ear* (it is where the message finally arrives and gets handled), an **export** is a *hole in a wall* that lets the message pass through a room's boundary. An **analysis port** is a *loudspeaker*: it broadcasts and does not care how many (or whether any) are listening.

TLM (transaction-level modelling) connects components by interface rather than by signals. Three roles:

| Role | Class examples | Meaning |
|---|---|---|
| **Port** | `uvm_analysis_port`, `uvm_blocking_put_port` | the *initiator*: calls the interface method |
| **Export** | `uvm_analysis_export`, `uvm_put_export` | pass-through: forwards a connection up/down the hierarchy |
| **Imp** | `uvm_analysis_imp`, `uvm_blocking_put_imp` | the *terminator*: implements the method in its host class |

Connection direction: `initiator.connect(target)`: port → (export →)* imp. A port may connect to a parent's port or export for hierarchical wiring. All `connect` calls belong in `connect_phase` (after every `build_phase` finished, so both ends exist).

**Analysis port** (`uvm_analysis_port#(T)`): one-to-many broadcast, `write(t)` is a **function** (never blocks, no return value, no back-pressure). It may have **zero** subscribers without error — silence, not failure. `uvm_analysis_imp#(T, IMP)` calls `IMP::write(T t)` of the host class. For a class with several analysis inputs (a scoreboard with two streams) the macro `` `uvm_analysis_imp_decl(_suffix) `` declares `uvm_analysis_imp_suffix#(T, IMP)` whose host method is `write_suffix(T t)` (Module 06).

**Subscribers vs FIFOs.** `write()` of an imp runs **immediately, in the producer's thread** — your code must be quick and non-blocking. If the consumer needs time or wants its own pacing, put a `uvm_tlm_analysis_fifo#(T)` in front: its `analysis_export` takes the `write`, it stores the handle in an unbounded queue, and the consumer's own thread calls `fifo.get(t)` (blocking), `try_get`, `peek`, `used()`, `is_empty()`. The producer is never slowed down.

**Blocking put/get** (e.g. `uvm_blocking_put_port` → `uvm_tlm_fifo#(T)::put_export`) apply back-pressure on a bounded FIFO; the CPU testbench mostly uses analysis ports and analysis FIFOs, so put/get appear only briefly here.


### Connection checking

At the end of elaboration UVM resolves connections. A required connection count not met (e.g. a `uvm_seq_item_pull_port` with no target, or a put port with no imp) is reported as an error whose text is **SIMULATOR/VERSION-DEPENDENT** (commonly mentioning a connection count). Because analysis ports require zero connections, forgetting to connect one produces **no message at all**.


---

## Code Walkthrough

**How to read the two examples:** `example01.sv` has no DUT — it is a **notice-board experiment** (three agents-worth of `get`s print what they found). `example02.sv` is a **pipe experiment** (one producer, two receivers: a fast ear and a slow queue). Look at the expected-log table first, then find the line of code that explains each row.


### 1. Exact path, wildcard, precedence (`example01.sv`)

The test makes three sets before creating `env`:

```systemverilog
uvm_config_db#(int)::set(this, "env.*", "delay", 10);
uvm_config_db#(string)::set(this, "env.agent_b", "mode", "fast");
uvm_config_db#(int)::set(this, "env.agent_a", "retries", 3);
```

and the env makes one lower-level set for `agent_a`: `delay = 99`. Both agents run the same four `get` calls. Hand-derived result:

| | `delay` | `mode` | `retries` as `int` | `retries` as `int unsigned` |
|---|---|---|---|---|
| `agent_a` | **10** (test, higher level, beats env's 99) | slow (default) | 3 (set) | 7 (default; wrong type) |
| `agent_b` | 10 (wildcard) | fast (exact) | 5 (default) | 7 (default) |


### 2. The same program as a checklist

For any `get` that returns nothing, test in this order: (1) was the `set` executed before this `get`? (2) type identical? (3) field name identical (case-sensitive)? (4) path: context + `inst_name` equals the target's full name, or does a glob match it? (5) did a higher-level `set` of the same field override yours? Section 1 shows items 2, 4 and 5.


### 3. TLM wiring (`example02.sv`)

```systemverilog
prod.ap.connect(ap);                    // in mcpu_prod_box: child port -> box's port
box.ap.connect(a.imp);                  // in mcpu_tlm_env: box port -> imp in consumer A
box.ap.connect(b.fifo.analysis_export); // same port -> FIFO in consumer B
```

The env never mentions `prod`: the box's port is the boundary. That's the pattern behind `agent.ap` in Module 04.


### 4. Timing: imp versus FIFO

The producer writes at 0, 10, 20 ns. Consumer A's `write` runs inside each `write` call, so it logs at 0, 10, 20. Consumer B: the first `get` returns at 0, then `#25ns`, so its first "done" is at 25; two items are queued by then (written at 10 and 20), so `used()` is 2. It immediately gets the second, done at 50 with `used=1`, then the third, done at 75 with `used=0`. The producer was never delayed: that is what the FIFO buys. The test holds its objection for 100 ns so the slow consumer can finish.


---

## Common Pitfalls

- **`set` made too late — in `connect_phase`, `end_of_elaboration_phase` or `run_phase`** → the target's `get` in `build_phase` finds nothing; component runs with defaults; no message → the target's `build_phase` already ran; do the sets in the test's/parent's `build_phase`, before the `create`.
- **Absolute path with a component context** (`set(this, "uvm_test_top.env.x", ...)`) → silent miss → the path is appended to `this`'s name; use relative path with `this` or absolute with `null`.
- **Type mismatch** (`int` vs `int unsigned`, `bit [31:0]`) → `get` returns 0 → one pool per type; match exactly.
- **Unchecked `get`** → null `vif` or zeroed knob detected far from the cause → always check the return value and use `uvm_fatal` for must-have items, defaults for optional ones.
- **Over-broad wildcard** (`"*"` with a common field name such as `mode`) → an unrelated component changes behaviour → scope sets as narrowly as practical.
- **Surprise precedence** (an env's own `set` ignored because the test already set the field) → the lower-level setting never takes effect → debug with `+UVM_CONFIG_DB_TRACE`; remember higher-in-hierarchy wins.
- **Typo in a phase method name** (`conect_phase`) → compiles, never called; no connections made; analysis ports stay silent → use the exact `<name>_phase(uvm_phase phase)` signature; consider `` `uvm_info `` in `connect_phase` while debugging.
- **Blocking code in an imp's `write`** → compile error (blocking in a function) or, via workarounds, a stalled producer → decouple with a `uvm_tlm_analysis_fifo` and a consumer thread.


---

## Interview Angle

**Q1. How does `uvm_config_db::get` find a value, and why does it fail silently?**
It matches type, field name and a scope built from context and instance path, among entries that exist at call time. There is no "expected" entry registered, so absence is not an error; `get` returns 0.

**Q2. What is the precedence when two components set the same field?**
The set made from higher in the hierarchy wins; for the same context, the last write wins. So a test can override an env's setting, which is the intent.

**Q3. Why pass a config object instead of many `config_db` fields?**
One `set`/`get`, typed fields, easy to extend, can hold handles (vif) and behaviour knobs together, and avoids a long list of independent name/path/type matches that can each fail silently.

**Q4. Explain port, export and imp.**
A port initiates the call, an export forwards a connection through hierarchy, an imp terminates it by implementing the method. Connections go port → export(s) → imp, made in `connect_phase`.

**Q5. Analysis port vs `uvm_tlm_analysis_fifo`: when each?**
Imp (`write`) for quick, non-blocking consumers that act immediately (coverage sample, queue push). FIFO when the consumer needs its own thread or pacing (a comparator that blocks on two streams). Analysis `write` never blocks the producer either way.

**Q6. My scoreboard receives nothing and there are no errors. What do you check?**
That `connect` is actually executed (exact `connect_phase` signature), that the right ports are connected, that the monitor really calls `write`, and whether an analysis port with zero connections is silently legal here.

**Q7. How do you debug a `config_db` mismatch?**
`+UVM_CONFIG_DB_TRACE`, print the `get` result and value, compare type, field, and path strings against `get_full_name()`, check set-before-get ordering and higher-level overrides.


---

## Recap in five lines

1. `config_db` is a **noticeboard**: type + field name + address must all match, and the note must be pinned *before* it is read.
2. A **higher-level** `set` wins; a miss returns 0 and **keeps the default** — silently.
3. With a component context the path is **relative** to it; with `null` it is **absolute**.
4. **Port → export → imp** is the TLM chain; an **analysis port** broadcasts and may have zero listeners.
5. Use an **imp** for quick listeners and a **FIFO** for a listener that needs its own pace.

**Questions beginners often ask**
- *"My knob has its default value."* — print what `get` returned; check set-before-get, type, field name and path.
- *"My scoreboard hears nothing and there is no error."* — an analysis port with no subscriber is legal; check the `connect` call (and its spelling).
- *"Imp or FIFO?"* — imp runs immediately in the sender's time (keep it short); FIFO lets the receiver take its time.


---

## Check Your Understanding

1. In `example01.sv`, `agent_a` ends with `delay=10`. The env set it to 99 for exactly that instance. Explain. What would change if the env's `set` used `cntxt = null`?
2. From the test, a `set(this, "uvm_test_top.env.agent_b", "mode", "fast")` is written. What scope does it address, and what does `agent_b` see?
3. Derive the log times and `used()` values of consumer B in `example02.sv` if the consumer delay were 5 ns instead of 25 ns.

Answers: `solutions/module05/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Deliver a config object to only one of two agents, with a fallback default for the other. Subtle path trap. |
| `exercise02.md` | Debug the testbench | A monitor that produces one item instead of three, and a scoreboard that never hears anything — both silent. |
| `exercise03.md` | Design / interview write-up | Design the TLM connectivity of the `mini_cpu` env: which streams, which consumers, imps vs FIFOs. |


---

## Reference

**Classes:** `uvm_config_db#(T)`, `uvm_analysis_port#(T)`, `uvm_analysis_imp#(T,IMP)`, `uvm_analysis_export#(T)`, `uvm_tlm_analysis_fifo#(T)`, `uvm_tlm_fifo#(T)`, `uvm_blocking_put_port#(T)` (mentioned), `uvm_subscriber#(T)`.

**Macros:** `` `uvm_analysis_imp_decl(_suffix) `` (introduced, used in Module 06), `` `uvm_component_utils ``, `` `uvm_info ``.

**Methods:** `uvm_config_db#(T)::set(cntxt, inst_name, field_name, value)`, `::get(cntxt, inst_name, field_name, inout value)`, `port.connect(target)`, `ap.write(t)`, `fifo.get(t)`, `fifo.try_get(t)`, `fifo.peek(t)`, `fifo.used()`, `fifo.is_empty()`, `print_config()`.

**Plusargs:** `+UVM_CONFIG_DB_TRACE` (output format **SIMULATOR/VERSION-DEPENDENT**).

**Forward references made:** two-input scoreboard with `uvm_analysis_imp_decl` and the retire-trace compare (Module 06); coverage subscribers (Module 08); full env integration and debug plusargs (Module 10).
