# Module 02 — Check Your Understanding: Answers

## 1. No drain time in `example01.sv`

The last objection (`leaf_b`) drops at 25 ns; with drain time 0 the run phase ends at **25**. `report_phase` runs at **25**. The heartbeat at 36 never prints (the 24 ns heartbeat does). `mid`'s task is killed at 25.

## 2. Override registered in the env's `connect_phase`

The factory consults overrides **when `create` is called**. All creates of the testbench tree happen in `build_phase`, which finishes (for the entire tree) before any `connect_phase` begins; phases are barriers. By the time the override is registered, every component it was meant to change already exists. It would only affect creates executed afterwards (e.g. a `create` inside `run_phase`). Fix: register the override in the test's `build_phase` before the env is created.

## 3. Instance override path `"env.sb_b"`

Instance-override paths are matched against full hierarchical names; with no `parent` argument the string is used as-is, so `"env.sb_b"` matches nothing (the real name is `uvm_test_top.env.sb_b`). Without a matching instance override, `sb_b` falls back to the type override:

```
sb_a [SB] I am mcpu_verbose_scoreboard
sb_b [SB] I am mcpu_verbose_scoreboard      <- not strict
sb_c [SB] I am mcpu_scoreboard
```

No warning is printed. This is why "print `get_type_name()`" belongs in your debug toolkit.
