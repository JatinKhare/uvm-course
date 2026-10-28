# Module 08 — MANIFEST

## Concepts taught
Code vs functional coverage; plan-driven bins; covergroup anatomy (coverpoint, bins, array bins, transitions, wildcard,
`ignore_bins`, `illegal_bins`, `default`, cross, `binsof/intersect`, options); sampling discipline (monitor/subscriber, once per
observation, after fields are set); the coverage arithmetic (bins hit / counted bins; covergroup = weighted average);
closure loop; assertions vs coverage (`assert property`/`cover property`, vacuous pass).

## UVM classes/macros introduced
`uvm_subscriber#(T)` used for coverage; no new macros. (SystemVerilog covergroups/assertions.)

## Shared names defined (module08/example01.sv, example02.sv)
- `package mcpu_cov_pkg`, `package mcpu_closure_pkg`. Include chain: M08 ex01 -> M06 ex01 (-> M01/M03/M04 ex01); M08 ex02 -> M08 ex01 with `MCPU_SKIP_LEAF_TOPS`.
- `typedef enum {C_R, C_ADDI, C_LW, C_SW, C_BEQ, C_CSR, C_OTHER} mcpu_cls_e;` `typedef enum {D_NONE, D1, D2, D3} mcpu_dist_e;`
- `function automatic bit [31:0] mcpu_mk_word(cpu_opcode_e o, bit [4:0] d, s1, s2, bit [11:0] i)` — builds an instruction word via `cpu_instr_item.encode()` (no randomisation).
- `class mcpu_instr_cov extends uvm_subscriber#(mcpu_retire_txn)` — `cg` (embedded, `per_instance`): `cp_class` (6 bins, `ignore_bins other`), `cp_dist` (4 bins),
  `x_class_dist` (24 bins); methods `write`, `reset_history`, `cov_line()` (`class=.. dist=.. cross=.. total=..`), `report_phase` (info ID `COV`).
  History = destination registers of the last 3 retired instructions (`x0` never a producer/source).
- `mcpu_cov_env` (member `cov`), tests `mcpu_cov_test`, `mcpu_closure_test` (teaching).
- Convention: coverage subscribers connect to the retire monitor's `ap`; leaf-example `tb_top`s are guarded by `` `ifndef MCPU_SKIP_LEAF_TOPS ``;
  every example file that others include has an include guard (`MCPU_INC_Mnn_EXnn`).

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | set fields BEFORE `sample()`, exactly once; construct `cg` in `new`; transition bin in its own coverpoint |
| exercise02.md | debug | 2 | `default` bin never counts; blanket `ignore_bins` hides the memory-hazard crosses (100% on 5 samples; honest figure 72.2%) |
| exercise03.md | design | n/a | cross sized to be closable; waivers need reasons; assertions paired with `cover property` |

## Forward references made
Register-field coverage and `uvm_reg` built-in coverage (M09); merging coverage across the regression and sign-off criteria (M10).
