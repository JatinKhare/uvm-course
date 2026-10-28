# Module 10 — MANIFEST

## Concepts taught
Integration questions (runs / checks / trusted); base test vs concrete tests; `run_test()` + `+UVM_TESTNAME`; timeout policy;
reset handling (settle -> reset -> release -> flush -> restart); error-injection kinds (DUT mutation, stimulus fault, protocol fault)
and what each proves; negative tests and `uvm_report_catcher`; logging/verbosity/plusargs; debugging workflow and symptom catalog;
regression thinking (pass/fail conjunction, seeds, triage, coverage merge, exit criteria); capstone verification plan; the 25 interview Q&A.

## UVM classes/macros introduced
`uvm_report_catcher` (`catch`, `get_severity`, `set_severity`, `get_id`, `THROW`/`CAUGHT`), `uvm_report_cb::add`,
`uvm_top.set_timeout`, `uvm_top.print_topology`, `set_report_verbosity_level_hier`, `set_report_id_verbosity_hier`,
plusargs `+UVM_TESTNAME`, `+UVM_VERBOSITY`, `+UVM_MAX_QUIT_COUNT`, `+UVM_TIMEOUT`, `+UVM_PHASE_TRACE`, `+UVM_OBJECTION_TRACE`, `+UVM_CONFIG_DB_TRACE`.

## Shared names defined (module10/example01.sv, example02.sv)
- `interface mcpu_rst_ctl_if` (`bit req`), `module mini_cpu_core (mini_cpu_if.dut bus)` — EXECUTING core: one instruction in flight; raises `if_req`, executes at the edge where it samples
  `if_rvalid`, retires one `retire_*` record the next cycle (30 ns per instruction with the Module 04 agent); internal 256-word data memory; `ls_*` are observation pulses only; no traps/irq/ls_err;
  plusarg `+MCPU_BUG_ADD` makes ADD return a+b+1. (`mini_cpu` stub of Module 01 remains for Modules 01 and 04.)
- `package mcpu_integ_pkg`: `mcpu_rst_scoreboard` (extends `mcpu_scoreboard`; `flush()` clears queues and restarts the ISS, keeps counters; installed by factory override),
  `mcpu_smoke_prog_seq` (the Module 06 five-instruction program), `mcpu_env` (REAL final env: `cfg`, `ifetch_agent`, `retire_mon`, `sb`, `cov`),
  `mcpu_env_base_test` (gets `vif`, builds `cfg`, sets config for the env, factory override, `uvm_top.set_timeout(10us, 0)`), `mcpu_smoke_test`, `mcpu_reset_test`.
- `module tb_top` (final integration top): clock 10 ns, reset released at 42 ns, `rstc` pulse (2 clocks), `run_test()` with `+UVM_TESTNAME`.
- config_db: `(virtual mini_cpu_if, "vif")` and `(virtual mcpu_rst_ctl_if, "rstc")` set at `"uvm_test_top"`; `(mcpu_agent_cfg, "cfg")` set by the test for `env` and by the env for `ifetch_agent`.
- Include chain: M10 ex02 -> M06 ex02 -> M06 ex01 -> (M01, M03, M04 ex01); -> M08 ex01; -> M10 ex01 -> M01 ex01. All shared example files carry include guards.
- Course-level conventions: leaf-example tops guarded by `MCPU_SKIP_LEAF_TOPS`; library examples `define MCPU_NO_TOP`.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | catcher must `set_severity` then return `THROW` (not `CAUGHT`); register globally with `null`; exact count in `check_phase` |
| exercise02.md | debug | 2 bugs | timeout shorter than the test; reset before the last retirement is observed, then `flush()` silently discards the pending expectation |
| exercise03.md | design (capstone) | n/a | trace every plan item to test, checker, coverage; mutation suite; state gaps |

## Forward references made
None (course complete). Not modelled and carried as risks: traps/exceptions, interrupts, error responses, external data memory, multi-issue/out-of-order cores.
