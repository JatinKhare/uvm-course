# Module 06 — MANIFEST

## Concepts taught
Architectural (retire-trace) vs bus-level checking; ISS/predictor pattern and what feeds it (fetch stream vs program
image); in-order FIFO compare vs ID-keyed (out-of-order) compare; `uvm_analysis_imp_decl`; non-blocking `write_*`
and unspecified ordering -> two-queue buffering; `compare()`/`do_compare()` with `===`; end-of-test checks
(empty / leftover / in-flight); aliasing of queued handles; first-failure reporting.

## UVM classes/macros introduced
`uvm_scoreboard` (real body), `` `uvm_analysis_imp_decl `` in use (`write_fetch`, `write_retire`), `uvm_object::compare/do_compare`,
`uvm_comparer` (mentioned), `check_phase`, `report_phase`, `` `uvm_warning ``.

## Shared names defined (module06/example01.sv, example02.sv)
- `package mcpu_sb_pkg`, `package mcpu_sb_env_pkg`. Compile pattern: `example02.sv` includes `example01.sv`, which includes M01/M03/M04 example01 files with `MCPU_NO_TOP`.
- `class mcpu_retire_txn extends uvm_sequence_item` — `logic [31:0] pc, instr, data; logic [4:0] rd;` (`rd == 0` => no register written; stores/branches retire `rd=0, data=0`).
  `convert2string()` -> `pc=0x.. instr=0x.. rd=x<n> data=0x..`; `do_compare` uses `===` on all four fields.
- `class mcpu_iss` (plain SV, not UVM) — members `regs[32]`, `mem[addr]`, `csr[12-bit]`, `pc`; `function mcpu_retire_txn step(bit [31:0] instr)` (new object per call).
- `class mcpu_scoreboard extends uvm_scoreboard` — REPLACES the Module 02 shell. Members: `fetch_imp` (`uvm_analysis_imp_fetch#(mcpu_bus_txn, mcpu_scoreboard)`),
  `retire_imp` (`uvm_analysis_imp_retire#(mcpu_retire_txn, mcpu_scoreboard)`), `iss`, `exp_q`, `act_q`, counters `n_fetch, n_cmp, n_bad`;
  methods `write_fetch`, `write_retire`, `try_compare`, `check_phase`, `report_phase`. Message IDs: `PC_MISMATCH`, `RETIRE_MISMATCH`, `SB_EMPTY`, `SB_LEFTOVER`, `SB_INFLIGHT`, info `SB`.
- `class mcpu_retire_monitor extends uvm_monitor` — `ap` (`uvm_analysis_port#(mcpu_retire_txn)`), `cfg`, `vif`; samples `retire_*` when `rst_n && retire_valid`.
- Teaching/feeder only: `mcpu_sb_feed` (synthetic fetch/retire stream), `mcpu_sb_env`, `mcpu_sb_test`, `mcpu_cmp` (exercise comparator, `_exp/_act` imps).
- Env wiring for the integrated bench (Module 10): `ifetch_agent.ap -> sb.fetch_imp`, `retire_mon.ap -> sb.retire_imp`.
- GAP (carried to Module 10): the Module 01 stub DUT always retires `rd=0, data=0` and does not execute instructions; the integrated bench must
  upgrade the stub DUT (or restrict the compare to `pc`/`instr`). Module 06's logs use a synthetic feeder for that reason.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 4 | `while` (not `if`) and pop-both-on-mismatch; order-independence |
| exercise02.md | debug | 2 bugs | predictor aliasing (shared object); `do_compare` missing a field -> silent pass |
| exercise03.md | interview write-up | n/a | speculation: pull the ISS from retirements/program image, not from fetches |

## Forward references made
Constrained-random programs the ISS predicts (M07); coverage subscribers on the same streams (M08); CSR comparison with the register model (M09);
integrated env, upgraded DUT stub, drain time, first-failure reporting policy (M10).
