# Module 01 / Exercise 03 — Solution (one reference design)

## 1. Block diagram

```
tb_top (static world: clk, rst_n, mini_cpu_if, mini_cpu DUT, run_test)
  |
  +-- uvm_test_top : mcpu_base_test   (uvm_test)       picks config + sequences
        |
        +-- env : mcpu_env            (uvm_env)
              |
              +-- ifetch_agent : mcpu_ifetch_agent (uvm_agent)   fetch-bus side
              |       sequencer (uvm_sequencer) / driver (uvm_driver) / monitor (uvm_monitor)
              +-- lsu_agent    : mcpu_lsu_agent    (uvm_agent)   load/store-bus side
              |       sequencer / driver / monitor
              +-- irq agent (or irq driver in the env)  drives `irq`
              +-- retire monitor (uvm_monitor)           samples the retire trace (passive)
              +-- scoreboard : mcpu_scoreboard (uvm_scoreboard) + reference model/ISS
              +-- coverage collector (uvm_subscriber)    (Module 08)

All pin access goes through a virtual mini_cpu_if handle (from uvm_config_db).
```

Because the CPU is the **master** of both buses, the bus-side agents act as **slaves/memory**: the driver answers requests (supplying instruction words on the fetch bus, data and responses on the load/store bus). The program under test is delivered as *data* the ifetch driver returns.

## 2. Objects (not components)

| Object | Use |
|---|---|
| Instruction item (`cpu_instr_item`, Module 03) | one randomised instruction; the unit of stimulus |
| Sequence | generates a stream of items |
| Agent / env config object | holds `vif`, active/passive flag, memory image options |
| Bus transaction item | what a monitor reports for a fetch or load/store |
| Register model (Module 09) | CSR abstraction |

## 3. Phases

| Item | Phase | Why |
|---|---|---|
| Env, agents, scoreboard | `build_phase` | the hierarchy must exist before connection; created top-down so parents can set config before children read it |
| Monitor → scoreboard TLM hookup | `connect_phase` | ports can be connected only after both ends exist; bottom-up order |
| Topology print / sanity checks | `end_of_elaboration_phase` | the tree is complete and still at time 0 |
| Sequences, drivers' loops, monitor sampling loops | `run_phase` | only the run phase consumes time |
| Final pass/fail summary | `report_phase` | all checking is finished |

## 4. Checking

The **retire monitor** observes `retire_*` and publishes each retirement on an analysis port (Module 05). The **reference model** (ISS or predictor) is given the same program image and produces the expected retirement stream; the scoreboard compares retired `pc`, `instr`, `rd`, `data` in order (Module 06). Bus monitors additionally check load/store traffic.
The checking is not in the driver because the driver only knows what *it* issued, not what the DUT *did*; checking from the monitor's observation is independent of how stimulus was produced, so it keeps working with random, directed, or replaced stimulus and with a passive agent.

## 5. Who decides what

- **Test:** which env configuration, which overrides, which top-level sequence(s) start, and when the test is over (objections).
- **Env:** structure: which agents exist, how monitors connect to scoreboard/coverage; owns no stimulus intent.
- **Sequence:** the actual instruction/data stream and interrupt timing.

## 6. Bring-up risk

**Risk:** no objection raised (or raised after a delay) → run phase ends at time 0, scoreboard never sees a retirement, and the summary shows zero errors. **Detect:** the log shows no `[RUN]` activity after time 0 and the end-of-test time is 0; make the scoreboard `report_phase` print "N retirements compared" and flag N == 0 as an error.
Second risk: `vif` `config_db` path/field mismatch, caught by a checked `get` with a `uvm_fatal`.

## Self-review checklist (for your own answer)

- [x] Every component has a UVM base class named.
- [x] At least three objects named, none drawn as tree nodes.
- [x] Phases justified by function/task and direction, not recited.
- [x] Retire trace, both buses, and `irq` are all observed.
- [x] Checking is attached to monitors, not the driver.

## Expected log

Not applicable (design exercise; nothing runs).

## The result that matters

The architecture answer is a statement about **where responsibility lives**: structure in the env, intent in the test, stimulus in sequences, observation in monitors, judgment in the scoreboard. If your sketch has the driver "checking", or the test touching pins, restructure. Variation to try: redraw it with the CPU as a *slave* on a debug port (JTAG-like) and note which agents flip direction.
