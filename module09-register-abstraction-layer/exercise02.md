# Module 09 / Exercise 02 — Debug the testbench

**Type:** Debug. SV/UVM-compile-checkable by inspection.

## Goal

The register model below has two errors. Neither makes anything crash: one produces a false failure on a *correct* DUT and the other lets a real DUT bug through. For each: locate it, explain the mechanism with the arithmetic, and give the fix.

## Setup / DUT assumptions

The bench is `module09/example02.sv` with the model changed as shown. Auto-predict is on. The DUT stub behaves per its specification: `mstatus` keeps only bits 3 and 7 (mask `0x88`); `mepc` keeps `bit 0 = 0` — except in Run 2, where the DUT is built with the `MEPC_BIT0_BUG` parameter set (bit 0 is stored).

## Code

```systemverilog
// in mcpu_mstatus_reg.build()
mie  = uvm_reg_field::type_id::create("mie");
mpie = uvm_reg_field::type_id::create("mpie");
mie.configure (this, 1, 4, "RW", 0, 1'b0, 1, 1, 0);
mpie.configure(this, 1, 7, "RW", 0, 1'b0, 1, 1, 0);

// in mcpu_mepc_reg.build()
epc = uvm_reg_field::type_id::create("epc");
epc.configure(this, 31, 1, "RW", 0, 31'h0, 1, 1, 0);       // no other field
```

Test steps:
- **Run 1** (correct DUT): `blk.mstatus.write(status, 32'hFFFF_FFFF); blk.mstatus.mirror(status, UVM_CHECK);`
- **Run 2** (bug-injected DUT): `blk.mepc.write(status, 32'h0000_1001); blk.mepc.mirror(status, UVM_CHECK);`

## Symptoms

**Run 1.** The library reports a `UVM_ERROR` from `mirror(UVM_CHECK)` on `mstatus`: the value read from the DUT is `0x00000088` while the mirrored value is `0x00000090`. The DUT is correct.

**Run 2.** The mirror check on `mepc` reports **no error**, although the DUT stored `0x00001001` and the specification says bit 0 of `mepc` always reads 0.

## A correct answer must achieve

- For Run 1: the exact mirrored value after the write (derive `0x90` from the field positions), the read value, and which field the library flags.
- For Run 2: what the mirror holds after the write and after the check (derive it), and why the model cannot see bit 0.
- Minimal fixes for both, and the numbers the corrected model produces (Run 1: no error; Run 2: one error on which field).
- One generic technique (a test or a review step) that finds this class of model error before a DUT bug does.

Compare against `solutions/module09/exercise02_solution.md`.
