# Module 09 — Check Your Understanding: Answers

## 1. `get()` versus `get_mirrored_value()`

`set()` changes only the **desired** value: `get()` returns `0x88` (bit 3 and bit 7 set). The **mirror** is the model's belief about the DUT, and nothing has touched the DUT or told the model anything: `get_mirrored_value()` is still 0. The mirror becomes `0x88` when a frontdoor/backdoor **write** of that value completes (e.g. `update()` writes the difference), when a **read** returns it (the mirror is refreshed with the read data), or when it is told directly with `predict`.

## 2. `mstatus` masked to `0x88`

The DUT stores `0xFFFFFFFF & 0x88 = 0x88`. With auto-predict, the write is predicted field by field: `mie` (bit 3) = 1 and `mpie` (bit 7) = 1, and no other bits exist in the model, so the mirror is `0x88`. A read returns `0x88`. They agree without special handling because the model's fields describe exactly the bits the DUT implements: the *mask* is expressed by which bits belong to RW fields, not by extra code.

## 3. `mepc` without the `zero` field

After the write of `0x1001` the mirror is `0x1000` (EPC = `0x800`). `mirror(UVM_CHECK)` reads `0x1001` and compares the fields: `epc` = `0x1001 >> 1 = 0x800` equals the mirrored `0x800`. Bit 0 belongs to no field, so it is not compared: **no error**, the bug is invisible. (Then the mirror is refreshed to `0x1000`.) The bug-injected DUT is only caught once bit 0 is described, as the RO field `zero` (read 1 versus mirrored 0).
