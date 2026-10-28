# Module 02 — MANIFEST

## Concepts taught
Common phases and their kinds/directions; phase barrier; run-time sub-phases (mentioned); objections and
propagation; drain time; phase timeout; killed `run_phase`; factory registration; `type_id::create`;
type vs instance override and precedence; override timing; `new()` bypass; factory debugging.

## UVM classes/macros introduced
`uvm_phase`, `uvm_objection` (via `phase.phase_done`), `uvm_factory` (`get().print()`), `uvm_object_wrapper`,
`uvm_root::set_timeout`, `set_drain_time`, `set_type_override`, `set_inst_override`, `get_type`, `get_type_name`,
`get_full_name`, phase callbacks `connect/end_of_elaboration/start_of_simulation/extract/check/report/final`.

## Shared names defined
- Teaching-only (do not reuse as TB classes): `mcpu_probe_leaf`, `mcpu_probe_mid`, `mcpu_phase_test`, `mcpu_phase_pkg`,
  `mcpu_factory_pkg`, `mcpu_ovr_env`, `mcpu_ovr_test`, `mcpu_x_*`, `mcpu_dbg_*`, `mcpu_p_*`.
- Shell classes reused later with real bodies: `mcpu_scoreboard` (extends `uvm_scoreboard`; Module 06 fills it),
  variants `mcpu_verbose_scoreboard`, `mcpu_strict_scoreboard` (derive from `mcpu_scoreboard`).
- Convention: tests register overrides in their own `build_phase`, **before** creating `env`; every component is
  created with `type_id::create`; the base test should set a phase timeout (Module 10).

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 4 | instance override must precede `create`; path must be the full name; drain time instead of padding the delay |
| exercise02.md | debug | 2 bugs | `new()` bypasses override; `return` skips `drop_objection` (objection leak) |
| exercise03.md | predict the log | n/a | run phase lasts until the LAST objection drops; killed task never prints |

## Forward references made
`reset_phase`/reset handling and base-test timeout (Module 10); TLM connections in `connect_phase` (Module 05);
sequences started in `run_phase` (Module 03); real scoreboard body (Module 06).
