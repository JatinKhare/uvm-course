# Module 03 — MANIFEST

## Concepts taught
Transaction/sequence/sequencer/driver separation; `uvm_sequence_item`; legality vs preference vs scenario
constraints; `soft`; `randomize() with`; name shadowing and `local::`; non-rand variables as constants;
`start_item`/`finish_item` and late randomisation; `body()`; sequence start flow; directed vs random sequences;
virtual sequence, virtual sequencer, `p_sequencer` vs `m_sequencer`; `do_copy/do_compare/convert2string`
(and why `uvm_field_*` is avoided).

## UVM classes/macros introduced
`uvm_sequence_item`, `uvm_sequence#(REQ)`, `uvm_sequencer#(REQ)`, `uvm_driver#(REQ)`, `uvm_comparer`,
`` `uvm_declare_p_sequencer ``, `` `uvm_do ``/`` `uvm_do_with `` (mentioned), `` `uvm_field_* `` (mentioned),
`seq.start()`, `start_item`, `finish_item`, `seq_item_port.get_next_item/item_done` (preview).

## Shared names defined (file: module03/example01.sv unless noted)
- `package mcpu_seq_pkg`; `package mcpu_vseq_pkg` (example02). Compile pattern: `` `define MCPU_NO_TOP `` then `` `include `` the earlier example (guards its own top).
- `typedef enum bit [3:0] {OP_ADD, OP_SUB, OP_AND, OP_OR, OP_ADDI, OP_LW, OP_SW, OP_BEQ, OP_CSRRW} cpu_opcode_e;`
- `class cpu_instr_item extends uvm_sequence_item` — `rand cpu_opcode_e op; rand bit [4:0] rd, rs1, rs2; rand bit [11:0] imm;`
  `function bit [31:0] encode()`, `convert2string`, `do_copy`, `do_compare` (compares `encode()`); NOP = `32'h0000_0013`.
  Constraints: `c_small_regs` (soft x1..x7), `c_unused_rd`, `c_align`, `c_csr` (0x300/0x305/0x341).
- `typedef uvm_sequencer#(cpu_instr_item) mcpu_ifetch_seqr;`
- `mcpu_instr_seq_base` with `task send_instr(cpu_opcode_e o, bit [4:0] d, s1, s2, bit [11:0] i)`.
- `mcpu_directed_seq`, `mcpu_rand_seq` (`rand int unsigned n_instr`, 1..20).
- `mcpu_stub_driver` — THROWAWAY (logs `[DRV] got ...`, 10 ns per item); Module 04 replaces it with `mcpu_ifetch_driver`.
- example02: `mcpu_mem_item` (`rand bit [31:0] addr, data`; aligned), `typedef uvm_sequencer#(mcpu_mem_item) mcpu_lsu_seqr;`,
  `mcpu_mem_preload_seq`, `mcpu_lw_after_sw_seq`, `mcpu_vseqr` (fields `ifetch_seqr`, `lsu_seqr`),
  `mcpu_lw_after_sw_vseq`, `mcpu_stub_lsu_driver` (throwaway).

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | `rs1 == producer.rd` scoping inside `with` (and `rs1 == rd` constrains nothing) |
| exercise02.md | debug | 2 bugs | constraint conflict hidden by `void'(randomize())`; missing `rand` turns a field into a constant |
| exercise03.md | design | n/a | distinguishable data; alignment by construction; negative scenario |

## Forward references made
Real driver/monitor/agent (M04); `solve before`, `dist`, seeding (M07); coverage of hazard/distance (M08);
CSR instructions and RAL (M09); interrupt injection (M10); scoreboard checking of retire data (M06).
