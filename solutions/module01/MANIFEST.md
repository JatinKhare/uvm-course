# Module 01 — MANIFEST

## Concepts taught
UVM purpose; layered testbench; component vs object; static vs dynamic world; virtual interface;
`run_test`, `uvm_test_top`, `uvm_top`; factory registration (macro); phase schedule preview;
minimal objection; reporting macros and verbosity; hierarchy/full name; `print()`.

## UVM classes/macros introduced
`uvm_pkg`, `uvm_test`, `uvm_env`, `uvm_agent`, `uvm_scoreboard`, `uvm_component`, `uvm_object`, `uvm_phase`,
`uvm_root`/`uvm_top`, `uvm_config_db#(T)::set/get`, `` `uvm_component_utils ``, `` `uvm_object_utils ``,
`` `uvm_info ``, `` `uvm_fatal ``, `type_id::create`, `raise_objection/drop_objection`, `convert2string`.

## Shared names defined
- `interface mini_cpu_if (input logic clk, input logic rst_n)` — signals: `if_req, if_addr[31:0], if_rvalid, if_rdata[31:0], ls_req, ls_we, ls_addr[31:0], ls_wdata[31:0], ls_rvalid, ls_rdata[31:0], irq, retire_valid, retire_pc[31:0], retire_instr[31:0], retire_rd[4:0], retire_data[31:0]`; modport `dut`.
- `module mini_cpu (mini_cpu_if.dut bus)` — stub DUT in Module 01 (fetches, retires what it fetches).
- `module tb_top` — clock 10 ns, reset released at 42 ns, sets `vif`, calls `run_test`.
- `package mcpu_pkg` — TB classes live here. config_db: type `virtual mini_cpu_if`, field `"vif"`, path `"uvm_test_top"`.
- `class mcpu_base_test extends uvm_test` — gets `vif`; later modules add `env`.
- Class shells (example02): `mcpu_env` (children `ifetch_agent`, `lsu_agent`, `scoreboard`), `mcpu_ifetch_agent`, `mcpu_lsu_agent`, `mcpu_scoreboard`, `mcpu_run_info` (uvm_object).
- Naming: all classes prefix `mcpu_`; sole exception is `cpu_instr_item` (Module 03, name fixed by the spec). NOP = `32'h0000_0013`.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 5 | objection raised before first delay, dropped after last log |
| exercise02.md | debug | 2 bugs | config_db instance path `uvm_test` vs `uvm_test_top`; missing objection |
| exercise03.md | design / interview | n/a | checking attached to monitors, not driver |

## Forward references made
Phases/objections/factory (M02); `cpu_instr_item`, sequences (M03); agent bodies, monitors (M04);
config_db details, TLM (M05); scoreboard/ref model (M06); coverage (M08); CSR model (M09).
