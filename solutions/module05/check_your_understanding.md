# Module 05 — Check Your Understanding: Answers

## 1. `agent_a` ends with `delay=10`, not 99

Two sets target the same field for `agent_a`'s scope: the test's (`"env.*"`, context depth 1 — the test) and the env's (`"agent_a"`, context the env, depth 2). Precedence goes to the set made from the **higher** point in the hierarchy, so the test's 10 wins regardless of the order they ran. If the env's `set` used `cntxt = null` with the absolute path `"uvm_test_top.env.agent_a"`, the context becomes the root (`uvm_top`), which is higher than the test, and that `set` would **win**: `agent_a` would see 99. The context, not the path string, determines precedence. (Ties between contexts at equal depth are **SIMULATOR/VERSION-DEPENDENT**.)

## 2. `set(this, "uvm_test_top.env.agent_b", "mode", "fast")` from the test

The addressed scope is the test's name plus the string: `uvm_test_top.uvm_test_top.env.agent_b`. No component has that name, so the entry is stored but never matched. `agent_b`'s `get` of `mode` fails and it keeps its default `"slow"`. No error, no warning.

## 3. Consumer B with a 5 ns delay

The producer writes at 0, 10, 20. B: `get` at 0, `#5ns` → done at **5** with the FIFO empty (the others are not written yet): `used=0`. Next `get` blocks until the second write at 10, then `#5ns` → done at **15**, `used=0`. Third write at 20 → done at **25**, `used=0`.

```
@ 5   [B] done addr=0x00000000 data=0x000000a0 used=0
@ 15  [B] done addr=0x00000004 data=0x000000a1 used=0
@ 25  [B] done addr=0x00000008 data=0x000000a2 used=0
```

The FIFO never builds up because the consumer is faster than the producer. With the 25 ns delay it queued; the producer's timing was unaffected either way.
