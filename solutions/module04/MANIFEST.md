# Module 04 — MANIFEST

## Concepts taught
Agent anatomy; CPU as master -> agents are memory-side responders; active vs passive; config object pattern;
driver–sequencer pull handshake (`get_next_item`/`item_done`, `try_next_item`, `get`); virtual-interface driving
and sampling conventions (NBA after edge, sample at edge, clocking block as alternative); monitor read-only
rule; analysis port broadcast; new transaction per observation; port-to-port promotion; drain time to let the
monitor finish; `uvm_subscriber`.

## UVM classes/macros introduced
`uvm_agent`, `uvm_driver#(REQ,RSP)` (`seq_item_port`, `req`), `uvm_monitor`, `uvm_subscriber#(T)`,
`uvm_analysis_port#(T)` (`write`, `connect`), `uvm_active_passive_enum` (`UVM_ACTIVE`/`UVM_PASSIVE`),
`seq_item_export`, `try_next_item`, `get`, `analysis_export`.

## Shared names defined (module04/example01.sv, example02.sv)
- `package mcpu_ifetch_pkg`, `package mcpu_ifetch_env_pkg`. Compile pattern: example02 `include`s M01 example01 (interface + DUT),
  M03 example01 (sequences), then M04 example01, with `MCPU_NO_TOP` defined.
- `class mcpu_bus_txn extends uvm_sequence_item` — `bit [31:0] addr, data; bit is_write;` `convert2string()` prints `RD|WR addr=0x.. data=0x..`.
- `class mcpu_agent_cfg extends uvm_object` — `virtual mini_cpu_if vif; uvm_active_passive_enum is_active = UVM_ACTIVE;`
  (extend with knobs in later modules). config_db: type `mcpu_agent_cfg`, field `"cfg"`, set by the test with `this`, `"env.ifetch_agent"`.
- `mcpu_ifetch_driver` (`uvm_driver#(cpu_instr_item)`; children get `cfg` by direct assignment from the agent), `mcpu_ifetch_monitor`
  (`ap`: `uvm_analysis_port#(mcpu_bus_txn)`), `mcpu_ifetch_agent` (members `cfg, seqr (mcpu_ifetch_seqr), drv, mon, ap`).
- `mcpu_bus_logger` (`uvm_subscriber#(mcpu_bus_txn)`, prints `[FETCH]`) — TEMPORARY consumer.
- `mcpu_env` (real: members `ifetch_agent`, `bus_logger`; later modules add `lsu_agent`, `scoreboard`), `mcpu_ifetch_test`, `module tb_top` (M04 version, no fetch responder).
- Fetch protocol (stub DUT): DUT holds `if_req`; agent answers with a one-cycle `if_rvalid` + `if_rdata`; first drive at 55 ns, 20 ns per instruction.
- Load/store protocol used in exercises (monitor/agent not implemented in code): `ls_req` held high until `ls_rvalid`; loads return `ls_rdata`.
- Open item: `mini_cpu_if` has NO error-response signal; Module 10 decides whether to add `ls_err`.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 4 | sample on the clock every cycle (edge-wait on a held `ls_req` misses back-to-back accesses); new txn per access |
| exercise02.md | debug | 2 bugs | missing `item_done` (sequence blocked in `finish_item`, objection never dropped); unguarded connect in passive agent |
| exercise03.md | design | n/a | reactive slave-side driver (two threads); interface lacks an error signal |

## Forward references made
`uvm_config_db` scoping/wildcards and TLM details (M05); scoreboard and retire monitor (M06); memory models with constrained
latency, address-aware fetch (M07); coverage subscribers (M08); reset handling in drivers and error injection (M10).
