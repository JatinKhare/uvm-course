# Module 09 / Exercise 02 — Solution

## Full solution code (changed parts)

```systemverilog
// mcpu_mstatus_reg.build(): MIE is bit 3
mie.configure (this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);
mpie.configure(this, 1, 7, "RW", 0, 1'b0, 1, 1, 0);

// mcpu_mepc_reg.build(): describe bit 0 too (read-only zero)
epc  = uvm_reg_field::type_id::create("epc");
zero = uvm_reg_field::type_id::create("zero");
epc.configure (this, 31, 1, "RW", 0, 31'h0, 1, 1, 0);
zero.configure(this,  1, 0, "RO", 0, 1'b0,  1, 0, 0);
```
(and `rand uvm_reg_field epc, zero;` in the class.)

## Run 1 — `mie` configured at bit 4 instead of 3

**Mechanism:** the write of `0xFFFFFFFF` is auto-predicted field by field: `mie` (bit 4) takes `1`, `mpie` (bit 7) takes `1`, so the mirror is `(1 << 4) | (1 << 7) = 0x10 + 0x80 = 0x90`. The correct DUT stores `0xFFFFFFFF & 0x88 = 0x88`. `mirror(UVM_CHECK)` reads `0x88` and compares per field: `mie` (bit 4 of `0x88` = 0) versus mirrored 1 → **mismatch on `mie`**; `mpie` (bit 7 = 1) matches. Bit 3 (the DUT's real MIE) is not part of any field, so it is not compared. The DUT is right; the model has the field at the wrong place.
**Fix:** `lsb_pos = 3`. **After the fix:** mirror `0x88`, read `0x88`, no error.

## Run 2 — bit 0 of `mepc` not described

**Mechanism:** with only the `epc` field [31:1], the write `0x1001` predicts `epc = 0x1001 >> 1 = 0x800`, so the mirror is `0x800 << 1 = 0x1000`. The bug-injected DUT stores `0x1001`. `mirror(UVM_CHECK)` reads `0x1001` and compares the bits that fields describe: `epc` = bits [31:1] of `0x1001` = `0x800` — equal to the mirrored `0x800`. Bit 0 belongs to no field and is never compared, so the stuck bit passes: no error, and the mirror is refreshed to `0x1000`.
**Fix:** add the `zero` field (RO, reset 0). **After the fix:** the check reads bit 0 = 1 against a mirrored 0 on field `zero` → **one `UVM_ERROR`, naming field `zero`**.

## Generic techniques that catch model errors early

1. **Tile check:** after `build()`, assert that the field widths of each register plus its declared reserved ranges add up to the register width (32) and do not overlap: `mstatus`'s fields (1 + 1) leave 30 undescribed bits, which should either be listed as reserved fields or be justified.
2. **Spec table diff:** print every field's name, `lsb`, size, access and reset from the model (`get_fields`, `get_lsb_pos`, `get_n_bits`, `get_access`, `get_reset`) and diff against the specification table by script. A `4` where the spec says `3` is found in seconds.
3. Run `uvm_reg_hw_reset_seq` and `uvm_reg_bit_bash_seq` against a **known-good** DUT or an executable specification model first: any failure there is a model error by definition.

## Self-review checklist

- [x] Both fixes are in the model, not in the test (the DUT is correct in Run 1; the model is incomplete in Run 2).
- [x] Field positions and sizes derived from the specification, with the arithmetic shown.
- [x] The RO `zero` field has `is_rand = 0` and a reset value, as the specification requires.
- [x] Auto-predict assumption consistent with the numbers (mirror updated per field).

## Expected log (hand-derived, not simulated)

After the fixes: Run 1 — no mirror error. Run 2 — one library `UVM_ERROR` on `mepc` field `zero` (read `0x1`, mirrored `0x0`); text is library-specific.

## The result that matters

A register check is only as strong as the model: **a bit that no field describes cannot fail.** Whenever a mirror check "passes" on a DUT you suspect, count the bits the model actually compares. Variation to try: describe bits [31:8] of `mstatus` as an RO "reserved" field and decide whether it should be volatile.
