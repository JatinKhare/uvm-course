# Module 04 — Check Your Understanding: Answers

## 1. First drive, first fetch, 20 ns spacing

Reset releases at 42; the DUT registers `if_req` at edge **45**, so `if_req` is sampled high from edge **55**. The driver (already holding item 1 from time 0) loops `@(posedge clk)` until `rst_n && if_req`: at 45 it samples the pre-update `if_req = 0`; at **55** it samples 1 and drives `if_rvalid` (visible after 55). **First `[IFD]` = 55.** The DUT and the monitor sample `if_rvalid = 1` at edge **65**: **first `[FETCH]` = 65** with `addr = pc = 0`.

Spacing: at 65 the driver clears `if_rvalid`, calls `item_done`, takes item 2 immediately, and enters `do @(posedge clk); while (...)`. That construct waits for the **next** edge (75) before evaluating `if_req`, then drives at 75. Each instruction therefore consumes two edges: one for the pulse and clear, one wait-then-drive → 20 ns. A `while (!(cond)) @(posedge clk);` form would evaluate immediately and could drive at 65 itself (but then `if_rvalid` would not return low between instructions, which is a protocol decision: with the stub DUT it would retire one instruction per cycle).

## 2. Reused monitor transaction

With one `mcpu_bus_txn` reused, the first fetch fills it with `addr=0x00000000 data=0x00500093` and publishes the handle; the second overwrites the same object with `addr=0x00000004 data=0x00700113` and publishes the same handle. A `uvm_subscriber` that prints inside `write` (like our logger) still shows both correctly, because it prints before the overwrite — which hides the bug. A scoreboard that stores handles in a queue sees two entries that both read `addr=4, data=0x00700113`: the first fetch has "vanished", producing spurious mismatches against the reference model.

## 3. Passive run with the lesson's `connect_phase`

Nothing may use the sequencer: in passive mode `seqr` and `drv` are never created, so `env.ifetch_agent.seqr` is null; the test must not call `seq.start(...)` on it (a null sequencer is an error or a null access, tool/library-specific). It should guard on the configuration. Note also that the lesson's connect code is unguarded in the *Exercise 02* form: if it is, the run fails earlier, in `connect_phase`, due to the null `drv` — that bug must be fixed first (guard the connection with the same `is_active` condition used in `build_phase`).
