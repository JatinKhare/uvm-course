# Module 04 — Driver, Sequencer, Monitor, Agent

> Prerequisites: Modules 01–03 (phases, factory, `cpu_instr_item`, sequences, `start_item`/`finish_item`).
> What this module gives you: the pin-level half of the testbench — how a driver turns transactions into signal activity, how a monitor turns signal activity back into transactions, and how an agent packages them (active or passive) with a configuration object.

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

In Module 3 the order slips went to a pretend cook that only *read them aloud*. Now we build the **real service counter** for one interface (the instruction-fetch bus). A counter (**agent**) has three staff:

| Staff member | UVM name | Job |
|---|---|---|
| Ticket-rail clerk | **sequencer** | passes one slip at a time |
| Cook | **driver** | turns the slip into real wire activity |
| Security camera | **monitor** | silently records what actually happened on the wires |

One twist that surprises people: **the CPU is the customer, not us.** It rings a bell (`if_req`) saying "give me the next instruction"; our driver answers by placing the instruction word on the wires. So in this testbench the "stimulus" is really *answers to the CPU's questions* — we play the **instruction memory**.


### The agent

An **agent** bundles everything needed to talk to one interface:

```
              +------------------- mcpu_ifetch_agent (uvm_agent) --------------------+
 sequences -->| mcpu_ifetch_seqr --> mcpu_ifetch_driver --> mini_cpu_if (pins)        |
              |                                                   |                   |
              |                      mcpu_ifetch_monitor <--------+  (samples pins)   |
              |                              |                                        |
              |                           ap (analysis port) --> scoreboard, coverage |
              +-----------------------------------------------------------------------+
```

| Component | Base class | Job | Touches pins? |
|---|---|---|---|
| Sequencer | `uvm_sequencer#(T)` | arbitrates sequences, hands items to the driver | no |
| Driver | `uvm_driver#(T)` | transaction → signal activity | drives (and may sample) |
| Monitor | `uvm_monitor` | signal activity → transaction, broadcast | samples only, never drives |
| Agent | `uvm_agent` | creates and connects the above | no |


### A CPU is the master — so the agent is the *memory side*

For `mini_cpu`, the CPU initiates fetches and data accesses. The agents on those buses are therefore **responders**: the fetch agent supplies instruction words when the CPU asks; the load/store agent (Exercise 03) supplies data and acknowledges stores. This surprises people used to master-side agents: here the "stimulus" the sequence generates (instructions) becomes *response data* on the bus. Module 07 adds smarter memory behaviour; here we serve instructions in sequence order and merely **observe** `if_addr`.


### Active vs. passive

**In plain words:** an *active* counter has cook + clerk + camera. A *passive* one has **only the camera** — useful when somebody else is doing the cooking (for example, in a bigger chip where a real memory feeds the CPU) and you just want to watch and check.

An **active** agent has sequencer, driver and monitor. A **passive** agent has only the monitor. Passive mode is what you use when something else drives the interface (at SoC level, a real memory model feeds the CPU) and you only want checking and coverage. The mode is a **configuration** choice, not a code fork: the same agent class, `is_active == UVM_PASSIVE`, builds only the monitor.


### The configuration object

An agent needs several settings (virtual interface, active/passive, later latency knobs). Passing them as a single `uvm_object` (`mcpu_agent_cfg`) is cleaner than many separate `config_db` entries: one `set`, one `get`, one place to add fields. The test creates it, fills it, stores it in `uvm_config_db`; the agent retrieves it and hands it down to its children by direct assignment after `create`. (`uvm_config_db` is explored fully in Module 05.)


---

## UVM Mechanics

### The driver–sequencer handshake (**PORTABLE UVM CONCEPT**)

`uvm_driver#(REQ,RSP)` has a `seq_item_port` (a pull port) and a `req` handle. The sequencer exposes `seq_item_export`. The driver **pulls**:

```
sequence                    sequencer                     driver
start_item(it) ------------> grant
randomize / fill it
finish_item(it) ------------> item waiting  <---------- get_next_item(req)   (returns it)
   ... blocked ...                                      drive the bus
   ... unblocked <----------------------------------- item_done()
```

Rules:
1. `get_next_item(req)` blocks until an item is available.
2. **Every `get_next_item` must be followed by exactly one `item_done`** before the next `get_next_item`. A second `get_next_item` with no `item_done` between is reported by the sequencer as an error (message text is **SIMULATOR/VERSION-DEPENDENT**) and the sequence, still blocked in `finish_item`, never continues.
3. `item_done()` is what releases the sequence's `finish_item`. The time between the two is how long the driver took to execute the item.
4. Variants: `try_next_item(req)` returns immediately with `req == null` if nothing is ready (lets a driver drive idle cycles); `get(req)` fetches and completes the handshake automatically (no `item_done`); `item_done(rsp)`/`put_response` return a response item to the sequence.

Why **pull**: the driver owns the timing of the pins. It asks for the next item only when the bus is ready for it, so sequences never need to know protocol timing.


### Driving and sampling: races

**In plain words:** two people pass a ball on every **clap** (the clock edge). If you throw *exactly* on the clap, the catcher can't tell whether you threw before or after it. The safe habit: **throw just after the clap** (drive with `<=`), and **look at the ball on the clap** (sample at the edge) — then both sides agree which round the ball belongs to.

The DUT samples at the clock edge. If the driver changes a signal with a blocking assignment at the same edge, the DUT may see old or new value depending on process ordering. **Convention used here:** drive with non-blocking assignments after the edge (`vif.if_rvalid <= 1'b1`), sample at the edge (`@(posedge vif.clk)` then read) — the sampled value is the pre-edge (previous-cycle) value, matching what the DUT sees. An alternative is a `clocking` block in the interface, which many teams prefer; it needs changes to `mini_cpu_if`, which this course keeps fixed to preserve shared names. Neither choice is a UVM feature; both are SystemVerilog scheduling idioms (**PORTABLE**).


### Virtual interface

The driver and monitor hold `virtual mini_cpu_if vif`, a class-world handle to the static interface. They get it from the agent's `cfg` object, which the test populated. Never reach into the DUT by hierarchical path.


### The monitor and the analysis port

`uvm_analysis_port#(T)` broadcasts transactions from a monitor to **any number** of connected subscribers (scoreboard, coverage, logger). `ap.write(t)` is a **function**: non-blocking, so a slow subscriber can never stall the monitor, and it calls every subscriber's `write` in the same time step. Because subscribers keep the handle, the monitor must create a **new transaction per observation**; reusing one object makes every earlier handle show the latest data. Analysis ports are created with `new("ap", this)`, not through the factory. Details of TLM are Module 05; `uvm_subscriber#(T)` (used for the logger) is the standard base for a pure consumer: it provides `analysis_export` and requires you to implement `write(T t)`.


### Agent build and connect

`build_phase`: get `cfg`; always create the monitor; create sequencer and driver only if `cfg.is_active == UVM_ACTIVE`. `connect_phase`: connect `seq_item_port` to `seq_item_export` **only if active**; connect the monitor's port to the agent's port (port-to-port promotion, so the env connects to `agent.ap` without knowing about the monitor inside). UVM also has a built-in `is_active` member in `uvm_agent` that can be set via `config_db`; this course drives the choice from the config object.


---

## Code Walkthrough

**A timeline to keep in mind while reading the driver** (clock edges at 5, 15, 25 …; reset released at 42 ns):

```
 45 ns  CPU raises if_req ("next instruction please")
 55 ns  driver SEES if_req  -> puts the word on if_rdata, raises if_rvalid
 65 ns  CPU and monitor SEE if_rvalid -> CPU takes the word, monitor records it;
        driver drops if_rvalid and calls item_done  -> the sequence can send the next slip
```

**Reading order for the files:** `example01.sv` is a *package of parts* (config, transaction, driver, monitor, agent) — read agent → driver → monitor. `example02.sv` is the *assembly* (env, test, top) — read it first if you like to see the whole before the parts.


### 1. Transaction and config (`example01.sv`)

```systemverilog
class mcpu_bus_txn extends uvm_sequence_item;        // what a monitor reports
  bit [31:0] addr, data;
  bit        is_write;
class mcpu_agent_cfg extends uvm_object;             // settings, not behaviour
  virtual mini_cpu_if     vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
```

`mcpu_bus_txn` is deliberately generic (address, data, direction) and is reused by the load/store side. It is *not* `cpu_instr_item`: an item describes an instruction to deliver; a bus txn describes what actually appeared on a bus.


### 2. The driver

```systemverilog
seq_item_port.get_next_item(req);
do @(posedge vif.clk); while (!(vif.rst_n && vif.if_req));
vif.if_rdata  <= req.encode();
vif.if_rvalid <= 1'b1;
@(posedge vif.clk);
vif.if_rvalid <= 1'b0;
seq_item_port.item_done();
```

It holds the item, waits until the DUT is actually requesting (after reset), drives `if_rdata`/`if_rvalid` for exactly one cycle, then releases the item. `if_rvalid` is also cleared before the first item (idle), so the DUT never sees X. Note the structure: **one `item_done` per `get_next_item`, on the only path through the loop body**.


### 3. The monitor

```systemverilog
@(posedge vif.clk);
if (vif.rst_n && vif.if_rvalid) begin
  txn = mcpu_bus_txn::type_id::create("txn");
  txn.addr = vif.if_addr;  txn.data = vif.if_rdata;  txn.is_write = 1'b0;
  ap.write(txn);
end
```

It samples at every edge and publishes whenever the bus completes an access. It runs independently of the driver, which is why the same monitor works in passive mode and when someone else drives the bus.


### 4. The agent

Build: `cfg` from `config_db`, monitor always, driver+sequencer when active. Connect: `drv.seq_item_port.connect(seqr.seq_item_export)` inside the same `is_active` guard as the creation. The guard must be mirrored: creating conditionally but connecting unconditionally dereferences a null `drv` in passive mode.


### 5. Putting it together (`example02.sv`)

The test creates `ifetch_cfg`, sets `vif` and `is_active`, and publishes it:

```systemverilog
uvm_config_db#(mcpu_agent_cfg)::set(this, "env.ifetch_agent", "cfg", ifetch_cfg);
```

It then starts `mcpu_directed_seq` on `env.ifetch_agent.seqr`. Per the hand trace, with `mini_cpu`'s stub: the driver drives instruction 1 at 55 ns, the monitor/DUT see it at 65 ns (the first `[FETCH]` line, `addr=0x00000000`), and each further instruction takes 20 ns (a fresh request must be seen before each drive). The fourth `[FETCH]` is at 125 ns. A drain time of 20 ns lets the logger catch the last observation. The per-instruction cost of 20 ns is a property of *this driver and this stub DUT*, not of UVM; improving it (back-to-back drive) is a good Exercise 03 discussion topic.


---

## Common Pitfalls

- **`get_next_item` with no matching `item_done`** → sequencer error mentioning `get_next_item` called twice (text library-specific), DUT stops receiving instructions, simulation never ends → `finish_item` in the sequence stays blocked, so the test's objection is never dropped.
- **`item_done` called without a preceding `get_next_item`** (or twice) → error from the sequencer, or a hang → the handshake is strictly pair-wise.
- **Driver changes signals with blocking assignments at the clock edge** → intermittent behaviour that changes with simulator or optimisation level; waveform looks right → race with the DUT's sampling; drive with `<=` after the edge or through a clocking block.
- **Monitor reuses one transaction object** → the scoreboard sees the same (latest) data for several observations; mismatches that "fix themselves" when printing → subscribers store handles, not copies; `create` a new txn each time.
- **Monitor drives or modifies signals** (e.g. clears a valid) → active-passive behaviour differs, results change when the agent is made passive → a monitor must be read-only.
- **Agent creates driver conditionally but connects unconditionally** → null-handle error during `connect_phase` in passive runs (wording tool-specific), nothing runs → mirror the `is_active` guard in both phases.
- **`cfg` not set, or `config_db` path/field mismatch** → `UVM_FATAL [NOCFG]` from the agent's build, time 0 → `get` returns 0; set must use the agent's full path and the same type/field (Module 05).
- **Sequencer–driver connection missing** → driver blocks forever in `get_next_item`; sequence blocked in `finish_item`; also usually an elaboration-time connection error (text library-specific) → connect `seq_item_port` to `seq_item_export` in `connect_phase`.


---

## Interview Angle

**Q1. Describe the driver–sequencer handshake step by step.**
The sequence calls `start_item` (waits for a grant), fills the item, `finish_item` (sends it, blocks). The driver calls `get_next_item` to obtain it, drives the interface, and calls `item_done`, which unblocks `finish_item`. One `item_done` per `get_next_item`.

**Q2. Why does the driver pull items rather than the sequence pushing them?**
The driver knows when the interface can accept another transaction. Pulling keeps protocol timing inside the driver, so the same sequences work across different protocols and speeds.

**Q3. What is the difference between `get_next_item` and `get`, and when do you use `try_next_item`?**
`get_next_item` needs a following `item_done`; `get` completes automatically. `try_next_item` returns null when no item is ready so the driver can drive idle values — needed when the bus must keep moving (clocked protocols with idle states).

**Q4. Why are the monitor and driver separate classes?**
Different responsibilities and reuse: the monitor must work when something else drives the interface (passive mode) and is the independent source of truth for checking and coverage. A driver-embedded monitor would observe what it *intended*, not what happened.

**Q5. What are active and passive agents, and how do you switch?**
Active drives (sequencer + driver + monitor); passive only observes (monitor). A config setting (`is_active`) chooses; build and connect guard the driver/sequencer on it. Passive is used when the DUT is driven by other logic, e.g. at SoC level.

**Q6. How does a monitor deliver data to the scoreboard and coverage?**
Through an analysis port: `write()` is a non-blocking function broadcast to all subscribers, so adding a consumer never changes the monitor. The monitor creates a new transaction per observation.

**Q7. How do you avoid driver/DUT races?**
Drive with non-blocking assignments after the clock edge or through a clocking block, and sample at the edge (or via clocking block skew), so both sides agree on which cycle a value belongs to.


---

## Recap in five lines

1. An **agent** = sequencer (clerk) + driver (cook) + monitor (camera) for one interface.
2. The **CPU is the master**; our driver answers its requests like an instruction memory.
3. Handshake: `get_next_item` → drive → **`item_done`** (exactly one per item).
4. The **monitor only watches** and creates a **new** transaction each time; it never drives.
5. **Passive** agent = monitor only; the choice lives in a **config object**, and `build` and `connect` must use the same guard.

**Questions beginners often ask**
- *"Why is the monitor a separate class?"* — it must work even when someone else drives the bus, and it is the honest record of what happened.
- *"My test hangs after the first instruction."* — look for a missing `item_done` in the driver.
- *"Why drive with `<=` and sample at the edge?"* — so driver and CPU agree which clock cycle a value belongs to.


---

## Check Your Understanding

1. In `example02.sv`, derive the time of the first `[IFD] drive` line and of the first `[FETCH]` line, and explain why consecutive `[IFD]` lines are 20 ns apart rather than 10.
2. What would the scoreboard (or logger) see if the monitor created one `mcpu_bus_txn` in `build_phase` and reused it for every observation? Give a concrete example with the first two fetches.
3. A passive configuration is requested (`cfg.is_active = UVM_PASSIVE`) but the agent's `connect_phase` is the one in the lesson. What must be true of the test's `run_phase`, and what would go wrong if it still tried `seq.start(env.ifetch_agent.seqr)`?

Answers: `solutions/module04/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Write the load/store-bus monitor for a request/response protocol with back-to-back requests. Subtle sampling trap. |
| `exercise02.md` | Debug the testbench | A driver that hangs after the first instruction, and an agent that crashes when made passive. |
| `exercise03.md` | Design | Design the load/store memory-side agent: items, driver behaviour with variable latency and error injection, monitor, config knobs. |


---

## Reference

**Classes:** `uvm_agent`, `uvm_driver#(REQ,RSP)`, `uvm_sequencer#(REQ,RSP)`, `uvm_monitor`, `uvm_subscriber#(T)`, `uvm_analysis_port#(T)`, `uvm_seq_item_pull_port` (via `seq_item_port`), `uvm_active_passive_enum` (`UVM_ACTIVE`, `UVM_PASSIVE`), `uvm_config_db#(T)`, `uvm_sequence_item`, `uvm_object`.

**Methods:** `seq_item_port.get_next_item(req)`, `try_next_item(req)`, `get(req)`, `item_done()`, `seq_item_port.connect(seqr.seq_item_export)`, `ap.write(t)`, `analysis_export`, `ap.connect(...)`, `uvm_config_db#(T)::set/get`, `type_id::create`, `new("ap", this)`.

**Macros:** `` `uvm_component_utils ``, `` `uvm_object_utils ``, `` `uvm_info ``, `` `uvm_fatal ``.

**Forward references made:** `uvm_config_db` scoping, wildcard pitfalls, TLM ports/exports/imps and FIFOs (Module 05); scoreboard and retire monitor (Module 06); smarter memory models and constrained delays (Module 07); coverage subscribers (Module 08); reset handling in the driver and error injection (Module 10).
