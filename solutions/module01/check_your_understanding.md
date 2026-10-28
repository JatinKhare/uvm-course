# Module 01 — Check Your Understanding: Answers

## 1. Time and address of the third retire

Clock rises at 5, 15, 25, ... (10 ns period, starts low, toggles every 5 ns). Reset releases at 42 ns.
- First posedge after release: **45**. The DUT sees `rst_n=1` and sets `if_req` high (visible after 45).
- Posedge **55**: the responder sees `if_req=1`, sets `if_rvalid` high (visible after 55).
- Posedge **65**: the DUT sees `if_rvalid=1`, sets `retire_valid`, `retire_pc` (= `pc` = 0) and advances `pc` (all non-blocking, visible after 65).
- Posedge **75**: the test samples `retire_valid=1`, `retire_pc=0` → retire #1 at 75 ns. Because `pc` advanced at 65, the next retire at 85 shows `pc=4`.

Retire #1 at 75 (pc 0), #2 at 85 (pc 4), **#3 at 95 ns, `pc=0x00000008`**.
Key idea: the test samples before the non-blocking updates of the same edge, so it always sees the previous edge's results; the pipeline latency is therefore three clock edges after reset release.

## 2. No objections

Remaining lines: `[BUILD]` at 0, `[RUN] waiting for reset release` at 0. The `reset released` line (42 ns) and all retire lines never print, because the run phase ends at the end of time 0. `[REPORT] mcpu_base_test finished` still prints at **0** — `extract`, `check`, `report`, `final` phases all still run, just at time 0. The report summary shows no errors, which is why this failure looks like a pass.

## 3. `cpu_instr_item` as a component: two reasons

1. **Lifecycle:** components are created in `build_phase`, before time 0, and live forever; instruction items are created per-instruction at run time, thousands to millions of times. Creating components during `run_phase` goes against the phase model (the hierarchy is meant to be fixed after build, and late-created components miss the earlier phases), and each one would stay in the tree for the whole simulation.
2. **Wrong semantics and cost:** items need constructor `new(name)` with no parent, `rand` fields, `do_copy/do_compare/convert2string`, and sequence-item handshake support (`uvm_sequence_item`). A component carries parent linkage, phase callbacks and a registry entry that an item never uses — wasted memory and per-object phase bookkeeping.
Bonus: items belong in the data flow (sequence → driver, monitor → scoreboard), not the structure tree; the topology print is meant to show structure.
