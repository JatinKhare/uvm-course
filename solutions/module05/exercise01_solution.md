# Module 05 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_lat_agent extends uvm_component;
  `uvm_component_utils(mcpu_lat_agent)
  mcpu_lat_cfg cfg;

  function new(string name = "mcpu_lat_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    bit from_db;
    super.build_phase(phase);
    // TODO 2
    from_db = uvm_config_db#(mcpu_lat_cfg)::get(this, "", "lat_cfg", cfg);
    if (!from_db) cfg = mcpu_lat_cfg::type_id::create("default_cfg");
    `uvm_info("LAT", $sformatf("min=%0d max=%0d (%s)", cfg.min_lat, cfg.max_lat,
              from_db ? "from config_db" : "default cfg"), UVM_LOW)
  endfunction
endclass

class mcpu_lat_test extends uvm_test;
  `uvm_component_utils(mcpu_lat_test)
  mcpu_lat_env env;

  function new(string name = "mcpu_lat_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    mcpu_lat_cfg lsu_cfg;
    super.build_phase(phase);
    lsu_cfg = mcpu_lat_cfg::type_id::create("lsu_cfg");
    lsu_cfg.min_lat = 2;
    lsu_cfg.max_lat = 4;
    // TODO 1
    uvm_config_db#(mcpu_lat_cfg)::set(this, "env.lsu_agent", "lat_cfg", lsu_cfg);
    // TODO 3
    env = mcpu_lat_env::type_id::create("env", this);
  endfunction
endclass
```

## TODO 1 — The subtle one: relative path with a component context

With `cntxt = this` (the test, full name `uvm_test_top`), the scope addressed is `uvm_test_top` + `"."` + `inst_name`. So `inst_name` must be **relative**: `"env.lsu_agent"`.
**Wrong answers and symptoms:**
- `set(this, "uvm_test_top.env.lsu_agent", ...)`: scope becomes `uvm_test_top.uvm_test_top.env.lsu_agent`; no match; `lsu_agent` logs `(default cfg)`, `min=1 max=1`; no message.
- `set(null, "env.lsu_agent", ...)`: with a `null` context the path is absolute from the root, so `"env.lsu_agent"` (no `uvm_test_top.` prefix) matches nothing; same symptom. (`set(null, "uvm_test_top.env.lsu_agent", ...)` would be correct.)
- `set(this, "env.*", ...)`: both agents (and any future agent) receive the object; requirement 4 violated, and `ifetch_agent` would log `min=2 max=4`.
- Type `uvm_config_db#(uvm_object)::set` with a `#(mcpu_lat_cfg)::get`: different pools; no match.
- Field name other than `"lat_cfg"`: no match.

## TODO 2 — `get` with fallback, no fatal

`get(this, "", "lat_cfg", cfg)` returns 1 on a match and assigns the handle. If it returns 0 the code creates a default object. Using `uvm_fatal` on a miss would break requirement 3 for `ifetch_agent`; ignoring the return value would leave `cfg` null and crash at the first `cfg.min_lat`.

## TODO 3 — Create the env

`env = mcpu_lat_env::type_id::create("env", this)`. The name `"env"` is part of the path used in TODO 1. (Placing the `set` before the `create` is the course habit; strictly the `set` just has to execute before the agents' `build_phase`, which runs after the test's `build_phase` returns.)

## Self-review checklist

- [x] Every `get` has a matching `set` for the one agent that should receive it: type `mcpu_lat_cfg`, field `"lat_cfg"`, scope `uvm_test_top.env.lsu_agent`.
- [x] No ports to connect.
- [x] `super.build_phase` called in both classes.
- [x] No objections used (no run phase activity).
- [x] The miss path is handled without a fatal.
- [x] No undeclared identifiers.

## Expected log (hand-derived, not simulated)

All at time 0, in build order (siblings in name order):

```
UVM_INFO ... @ 0: uvm_test_top.env.ifetch_agent [LAT] min=1 max=1 (default cfg)
UVM_INFO ... @ 0: uvm_test_top.env.lsu_agent    [LAT] min=2 max=4 (from config_db)
```

## The result that matters

With a component context, the instance path is *relative to the context*; with `null` it is absolute. The same misspelt scope fails silently in both forms. Variation to try: set the same field from the env for `lsu_agent` with different values and predict which wins (the test's), then repeat with the env's set done in the test's `connect_phase` instead (too late).
