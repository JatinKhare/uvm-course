# Module 05 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

Two independent bugs; **neither produces an error message**. For each: locate it, explain the mechanism that produces the symptom, give the minimal fix, and state the expected log after both fixes.

## Setup / DUT assumptions

No DUT. All classes compile. `mcpu_demo_txn` is the item from `module05/example02.sv`. Time unit ns.

## Code

```systemverilog
class mcpu_mon extends uvm_component;
  `uvm_component_utils(mcpu_mon)
  uvm_analysis_port#(mcpu_demo_txn) ap;
  int n_items = 1;                              // default
  function new(string name = "mcpu_mon", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    void'(uvm_config_db#(int)::get(this, "", "n_items", n_items));
    `uvm_info("MON", $sformatf("n_items=%0d", n_items), UVM_LOW)
  endfunction
  task run_phase(uvm_phase phase);
    mcpu_demo_txn t;
    for (int i = 0; i < n_items; i++) begin
      t = mcpu_demo_txn::type_id::create("t");
      t.addr = i * 4;
      t.data = 32'hB0 + i;
      `uvm_info("MON", $sformatf("write #%0d", i), UVM_LOW)
      ap.write(t);
      #10ns;
    end
  endtask
endclass

class mcpu_sb extends uvm_component;
  `uvm_component_utils(mcpu_sb)
  uvm_analysis_imp#(mcpu_demo_txn, mcpu_sb) imp;
  function new(string name = "mcpu_sb", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction
  function void write(mcpu_demo_txn t);
    `uvm_info("SB", {"got ", t.convert2string()}, UVM_LOW)
  endfunction
endclass

class mcpu_dbg_env extends uvm_env;
  `uvm_component_utils(mcpu_dbg_env)
  mcpu_mon mon;
  mcpu_sb  sb;
  function new(string name = "mcpu_dbg_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = mcpu_mon::type_id::create("mon", this);
    sb  = mcpu_sb::type_id::create("sb", this);
  endfunction
  function void conect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(sb.imp);
  endfunction
endclass

class mcpu_dbg_test extends uvm_test;
  `uvm_component_utils(mcpu_dbg_test)
  mcpu_dbg_env env;
  function new(string name = "mcpu_dbg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = mcpu_dbg_env::type_id::create("env", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    uvm_config_db#(int)::set(this, "env.mon", "n_items", 3);
  endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "dbg");
    #100ns;
    phase.drop_objection(this, "dbg done");
  endtask
endclass
```

## Symptoms

The test author intends the monitor to produce **three** items and the scoreboard to print each. The log is:

```
UVM_INFO ... @ 0:  uvm_test_top.env.mon [MON] n_items=1
UVM_INFO ... @ 0:  uvm_test_top.env.mon [MON] write #0
```

and nothing else: no more `[MON] write` lines, and no `[SB] got ...` line at all. The summary shows no errors and no warnings.

## A correct answer must achieve

- Both root causes named with exact lines, and which symptom each one explains (there are two distinct symptoms: the item count, and the silent scoreboard).
- Why UVM says nothing in either case.
- Minimal fixes that keep the structure (config via `config_db`, connection via TLM).
- The expected log after the fixes, with times.
- One technique each (a plusarg, a debug print, or a code habit) that would have exposed each bug quickly.

Compare against `solutions/module05/exercise02_solution.md`.
