# Module 05 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// mcpu_dbg_env
function void connect_phase(uvm_phase phase);          // Bug B fix: exact name
  super.connect_phase(phase);
  mon.ap.connect(sb.imp);
endfunction

// mcpu_dbg_test
function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  uvm_config_db#(int)::set(this, "env.mon", "n_items", 3);   // Bug A fix: in build_phase, before the create
  env = mcpu_dbg_env::type_id::create("env", this);
endfunction
// (the set is removed from the test's connect_phase)
```

## Bug A — `set` made in `connect_phase`

**Mechanism:** the monitor reads `n_items` in its own `build_phase`. All `build_phase`s finish before any `connect_phase` begins, so by the time the test's `connect_phase` executes the `set`, the monitor has already run its `get`, found nothing, and kept the default `n_items = 1`. The `set` still succeeds (it just stores an entry nobody will read). `uvm_config_db` has no notion of "a set arrived too late", hence no message.
**Symptom link:** `[MON] n_items=1` and a single `write #0`.
**Fix:** perform the `set` in the test's `build_phase` (before the `create`). **Technique to expose it:** the `get` result and value are printed (`n_items=...`); or run with `+UVM_CONFIG_DB_TRACE` and compare the order of `set` and `get` lines (trace format is **SIMULATOR/VERSION-DEPENDENT**).

## Bug B — `conect_phase` (typo)

**Mechanism:** `connect_phase` is a virtual method of `uvm_component` that the phase machinery calls by name. A method named `conect_phase` is just an unrelated user method: it compiles, and is never called. `mon.ap` therefore has zero subscribers. An analysis port may have zero connections without error (by design: a monitor must work with nobody listening), so `ap.write(t)` silently does nothing. That explains no `[SB]` lines even for the one item written.
**Fix:** the exact name and signature `connect_phase(uvm_phase phase)`. **Techniques:** log in every `connect_phase` while debugging; check connectivity with a quick count of subscribers (an `end_of_elaboration_phase` check that `mon.ap.size() > 0`, where `size()` is the number of connections of the port); the `override`-checking habit: some teams add `` `uvm_info `` to each phase callback in new components.

## Self-review checklist

- [x] `set` (`this`, `"env.mon"`, `"n_items"`, type `int`) matches the monitor's `get` (`this`, `""`, `"n_items"`, `int`), and executes before the monitor's `build_phase`.
- [x] `mon.ap` is connected to `sb.imp` in `connect_phase` with the exact signature, `super.connect_phase` called.
- [x] `write(mcpu_demo_txn)` exists in the imp's host class.
- [x] Objection raised and dropped around the 100 ns wait; the monitor's three writes finish by 20 ns.
- [x] No undeclared identifiers.

## Expected log (hand-derived, not simulated)

```
UVM_INFO ... @ 0:  uvm_test_top.env.mon [MON] n_items=3
UVM_INFO ... @ 0:  uvm_test_top.env.mon [MON] write #0
UVM_INFO ... @ 0:  uvm_test_top.env.sb  [SB]  got addr=0x00000000 data=0x000000b0
UVM_INFO ... @ 10: uvm_test_top.env.mon [MON] write #1
UVM_INFO ... @ 10: uvm_test_top.env.sb  [SB]  got addr=0x00000004 data=0x000000b1
UVM_INFO ... @ 20: uvm_test_top.env.mon [MON] write #2
UVM_INFO ... @ 20: uvm_test_top.env.sb  [SB]  got addr=0x00000008 data=0x000000b2
```

(`[SB]` follows the matching `[MON] write` because the imp's `write` executes inside `ap.write`.) The run phase ends at 100 ns.

## The result that matters

Both failures are **silent by design**: config_db misses return 0, and analysis ports with no subscribers are legal. Defensive habits move the failure from "silence" to "a message": print the value you got, check `get`, and assert expected connectivity in `end_of_elaboration_phase`. Variation to try: delete the `[MON]` log from the monitor and decide how you would tell, from the log alone, that nothing was ever connected.
