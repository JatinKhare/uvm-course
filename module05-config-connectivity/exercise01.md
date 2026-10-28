# Module 05 / Exercise 01 — Deliver a config object to one agent only (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Two agents are instances of the same class `mcpu_lat_agent`, named `ifetch_agent` and `lsu_agent`. Only `lsu_agent` must receive a non-default latency configuration (`min_lat = 2`, `max_lat = 4`). `ifetch_agent` must keep the defaults (1 and 1) **without** any error, because nobody set a config for it.

## Setup / DUT assumptions

No DUT. Given (do not edit):

```systemverilog
class mcpu_lat_cfg extends uvm_object;
  `uvm_object_utils(mcpu_lat_cfg)
  int unsigned min_lat = 1;
  int unsigned max_lat = 1;
  function new(string name = "mcpu_lat_cfg");
    super.new(name);
  endfunction
endclass

class mcpu_lat_env extends uvm_env;
  `uvm_component_utils(mcpu_lat_env)
  mcpu_lat_agent ifetch_agent, lsu_agent;
  function new(string name = "mcpu_lat_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ifetch_agent = mcpu_lat_agent::type_id::create("ifetch_agent", this);
    lsu_agent    = mcpu_lat_agent::type_id::create("lsu_agent", this);
  endfunction
endclass
```

The agent's config field name in `config_db` is `"lat_cfg"`; the stored type is `mcpu_lat_cfg`.

## Skeleton

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
    // TODO 2: fetch the config object for THIS component; if nothing was set,
    //         use a freshly created default config object (no fatal, no error)
    // YOUR CODE HERE
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
    // TODO 1: publish lsu_cfg so that ONLY env.lsu_agent can retrieve it (use this test as the context)
    // YOUR CODE HERE

    // TODO 3: create the env (instance name "env") under this test
    // YOUR CODE HERE
  endfunction
endclass
```

## A correct answer must achieve

1. Log line from `uvm_test_top.env.ifetch_agent`: `min=1 max=1 (default cfg)`.
2. Log line from `uvm_test_top.env.lsu_agent`: `min=2 max=4 (from config_db)`.
3. No `UVM_ERROR` or `UVM_FATAL` anywhere.
4. A third agent added later under `env` without a config must also get the defaults (i.e. the `set` must not be a wildcard that would reach it).

Compare against `solutions/module05/exercise01_solution.md`.
