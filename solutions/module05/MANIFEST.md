# Module 05 — MANIFEST

## Concepts taught
config_db set/get anatomy; scope = context + inst_name (relative with component, absolute with null); wildcards;
precedence (higher context wins, last write wins at equal context); set deadline = before the target's build_phase;
type-exact matching; what to store (vif, config object, scalars); debugging (`+UVM_CONFIG_DB_TRACE`, print results);
TLM roles (port/export/imp); analysis port semantics (function, 1:N, 0 subscribers legal); imp vs
`uvm_tlm_analysis_fifo`; hierarchical port promotion; `uvm_analysis_imp_decl`; connection errors vs silent misses.

## UVM classes/macros introduced
`uvm_config_db#(T)` (full API), `uvm_analysis_imp#(T,IMP)`, `uvm_analysis_export#(T)`, `uvm_tlm_analysis_fifo#(T)`,
`uvm_tlm_fifo#(T)`, `uvm_blocking_put_port#(T)` (mentioned), `` `uvm_analysis_imp_decl ``, `fifo.get/try_get/peek/used/is_empty`,
`print_config`.

## Shared names defined
- config_db entries used by the course (unchanged from M01/M04): `(virtual mini_cpu_if, "vif")` set from `tb_top`; `(mcpu_agent_cfg, "cfg")` set by the test.
- Rule for the course: tests make all `set`s in `build_phase` before creating the env; `get(this, "", field, var)` is always checked.
- Teaching classes only (do not reuse as TB classes): `mcpu_cfgdb_pkg`, `mcpu_cfg_agent/env/test`, `mcpu_tlm_pkg`, `mcpu_demo_txn`,
  `mcpu_producer`, `mcpu_prod_box`, `mcpu_cons_a`, `mcpu_cons_b`, `mcpu_tlm_env`, `mcpu_tlm_test`, `mcpu_lat_*`, `mcpu_mon`, `mcpu_sb` (exercise-local).
- Planned env wiring (design, Exercise 03): scoreboard inputs `fetch_imp`, `retire_imp`, `lsu_imp` via `uvm_analysis_imp_decl(_fetch/_retire/_lsu)`;
  retire monitor port `retire_mon.ap`; coverage collectors as `uvm_subscriber`s.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | absolute path with a component context doubles the prefix; wildcard would reach other agents |
| exercise02.md | debug | 2 bugs | `set` made in `connect_phase` (too late for a `build_phase` get); typo'd `conect_phase` leaves analysis port unconnected |
| exercise03.md | design | n/a | subscriber order unspecified; two-queue buffering; silent-failure checks |

## Forward references made
Two-input scoreboard, retire-trace compare, predictor (M06); coverage subscribers (M08); connectivity checks in
`end_of_elaboration`, config_db trace plusarg in the debug flow (M10).
