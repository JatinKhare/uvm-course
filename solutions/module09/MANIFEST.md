# Module 09 — MANIFEST

## Concepts taught
Register model purpose; two CSR access paths (architectural instructions vs register port); desired vs mirrored;
access policies; frontdoor/backdoor; adapter (`reg2bus`/`bus2reg`, flags `provides_responses`/`supports_byte_enable`);
auto-predict vs explicit `uvm_reg_predictor`; built-in sequences; model completeness (undescribed bits are unchecked).

## UVM classes/macros introduced
`uvm_reg_field`, `uvm_reg`, `uvm_reg_block`, `uvm_reg_map`, `uvm_reg_adapter`, `uvm_reg_predictor#(BUSTYPE)`, `uvm_reg_bus_op`,
`uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`, `uvm_reg_access_seq`, enums `uvm_status_e`, `uvm_door_e`, `uvm_predict_e`, `uvm_check_e`;
calls `configure`, `build`, `create_map`, `add_reg`, `lock_model`, `set_sequencer`, `set_auto_predict`, `reset`, `write/read/mirror/update/peek/poke`,
`set/get/get_mirrored_value/predict`, `add_hdl_path`, `add_hdl_path_slice`.

## Shared names defined (module09/example01.sv, example02.sv)
- `package mcpu_ral_pkg` (model) and `package mcpu_csr_pkg` (bus side); example02 includes example01 with `MCPU_SKIP_LEAF_TOPS`.
- `function automatic string mcpu_fmt32(uvm_reg_data_t v)` — `0x%08h` of the low 32 bits.
- Registers (all 32-bit, `UVM_NO_COVERAGE`): `mcpu_mstatus_reg` (`mie`[3] RW, `mpie`[7] RW), `mcpu_mtvec_reg` (`base`[31:2] RW reset 0x40, `mode`[1:0] RW),
  `mcpu_mepc_reg` (`epc`[31:1] RW, `zero`[0] RO), `mcpu_mcause_reg` (`code`[31:0] RO volatile).
- `class mcpu_csr_block extends uvm_reg_block` — members `mstatus`, `mtvec`, `mepc`, `mcause`; `default_map` "csr_map" (base 0, 4-byte data, not byte addressed)
  with addresses `0x300`, `0x305`, `0x341`, `0x342`. Reset values: all 0 except mtvec = `0x100`.
- `interface mini_cpu_csr_if (input logic clk, input logic rst_n)` — `csr_req, csr_we, csr_addr[11:0], csr_wdata, csr_rdata, csr_rvalid`.
  Protocol: master pulses `csr_req` one cycle; slave answers one edge later with `csr_rvalid` and `csr_rdata` = value BEFORE the write.
- `module mini_cpu_csr_regs #(parameter bit MEPC_BIT0_BUG = 0) (mini_cpu_csr_if bus)` — CSR slave stub (mstatus mask 0x88; mepc bit 0 forced 0 unless the bug parameter is set;
  mcause RO). Instance name `csr` in `tb_top_ral` (backdoor path `tb_top_ral.csr`, flops `mstatus_q`, `mtvec_q`, `mepc_q`, `mcause_q`).
- `mcpu_csr_item` (`we, addr[11:0], wdata, rdata`), `mcpu_csr_seqr` (typedef), `mcpu_csr_driver` (3 edges per access; fills `rdata` in the same item),
  `mcpu_csr_adapter` (`provides_responses = 0`, `supports_byte_enable = 0`), `mcpu_csr_test`.
- config_db: type `virtual mini_cpu_csr_if`, field `"csr_vif"`, `set(null, "uvm_test_top*", "csr_vif", vif)`.
- The CSR port is a SEPARATE interface; `mini_cpu_if` unchanged. The Module 10 core (`mini_cpu_core`) does not implement this port.

## Exercises
| file | type | TODOs | subtle trap |
|---|---|---|---|
| exercise01.md | fill-in | 3 | `provides_responses = 1` with a non-responding driver hangs every access; read data comes from `rdata`, not `wdata` |
| exercise02.md | debug | 2 | field at wrong lsb (false failure on a correct DUT); undescribed bit (stuck bit invisible) |
| exercise03.md | design | n/a | prediction architecture for instruction-path and hardware updates; backdoor limits |

## Forward references made
One bench keeping the register layer and ISS CSR model consistent; reset handling for the mirror; trap-driven `mepc`/`mcause` updates (Module 10).
