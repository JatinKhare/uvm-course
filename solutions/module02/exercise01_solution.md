# Module 02 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_x_test extends uvm_test;
  `uvm_component_utils(mcpu_x_test)
  mcpu_x_env env;

  function new(string name = "mcpu_x_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // TODO 1
    mcpu_scoreboard::type_id::set_inst_override(mcpu_strict_scoreboard::get_type(),
                                                "uvm_test_top.env.sb_b");
    // TODO 2
    env = mcpu_x_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    // TODO 3
    phase.raise_objection(this, "x_test running");
    phase.phase_done.set_drain_time(this, 5ns);
    #30ns;
    `uvm_info("TEST", "work done, releasing objection", UVM_LOW)
    // TODO 4
    phase.drop_objection(this, "x_test done");
  endtask
endclass
```

## TODO 1 — Instance override, registered before `create`, with the full path

`set_inst_override(<override type>, "uvm_test_top.env.sb_b")` on `mcpu_scoreboard::type_id`. The path is the **full hierarchical name** of the instance the env will create: test is `uvm_test_top`, env instance name is `env` (TODO 2), scoreboard instance name is `sb_b`.
**Wrong answers and symptoms:**
- `set_type_override(...)`: both `sb_a` and `sb_b` become strict (`sb_a` log line wrong).
- Path `"env.sb_b"` or `"*.sb_b"` without the right prefix: no match → `sb_b` stays plain, no message.
- Placed **after** TODO 2's `create`: both scoreboards were already built; both say `I am mcpu_scoreboard`, no message. This is the subtle trap: it compiles and runs cleanly.

## TODO 2 — `type_id::create` with name `"env"`

The name `"env"` must match the path in TODO 1. `new` would also work here (no override targets the env) but violates the course habit and would break if someone later overrides the env.

## TODO 3 — Raise first, then drain time on the phase's objection

The objection is raised before the delay. `phase.phase_done.set_drain_time(this, 5ns)` keeps the phase open 5 ns after the last objection drops (30 → 35 ns), so `mcpu_late_mon`'s 33 ns message prints. Any value ≥ 3 ns works; 5 ns leaves margin.
**Wrong answers:**
- Delaying the test's own drop (`#33ns;` or longer): violates requirement 3 (drop at 30) and hides the real issue.
- `set_drain_time` without any objection raised: the phase has already ended at time 0; neither the 30 ns nor the 33 ns line prints.
- Raising an objection in `mcpu_late_mon`: also a valid design, but the component is given and must not be edited.

## TODO 4 — Drop after the last log line

One drop, on every path, after the `uvm_info`. Missing drop → the phase never ends (symptom: no end of simulation).

## Self-review checklist

- [x] No `config_db` use; nothing to match.
- [x] No ports.
- [x] `super.new` and `super.build_phase` present.
- [x] One raise, one drop, same object (`this`), no early exit.
- [x] Overrides registered before the `create` they must affect; path matches instance names.
- [x] Types: override class derives from `mcpu_scoreboard`; `get_type()` passed as the wrapper.
- [x] No undeclared identifiers.

## Expected log (hand-derived, not simulated)

```
UVM_INFO ... @ 0:  uvm_test_top.env.sb_a [SB]   I am mcpu_scoreboard
UVM_INFO ... @ 0:  uvm_test_top.env.sb_b [SB]   I am mcpu_strict_scoreboard
UVM_INFO ... @ 30: uvm_test_top          [TEST] work done, releasing objection
UVM_INFO ... @ 33: uvm_test_top.env.late [LATE] late event observed
```

The run phase ends at 35 ns (30 + 5 drain).

## The result that matters

Objections say "the test is working"; drain time says "the DUT/bench may still be finishing". Late activity belongs in drain time or its own objection, never in padding the test's delay. Variation to try: set drain time to 2 ns and predict which line disappears and when the phase ends (32 ns).
