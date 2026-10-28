# Module 09 — Register Abstraction Layer (RAL)

> Prerequisites: Modules 01–08 (config objects and adapters follow the agent pattern of Module 04; monitors and predictors use analysis ports from Module 05; coverage from Module 08).
> What this module gives you: how UVM models a block of registers (here: the CPU's control and status registers, CSRs), how register reads and writes become bus transactions through an adapter, what the *mirror* is and how it is kept up to date, and how frontdoor, backdoor and the built-in sequences find bugs.

UVM 1.2 only. Logs are hand-derived. Labels: **PORTABLE UVM CONCEPT**, **SIMULATOR/VERSION-DEPENDENT**.


---

## Concept

### The story in plain words (start here)

A chip's **registers** are its **control panel**: switches and dials that software sets ("interrupts on", "jump here on a trap"). A **register model** is a testbench-side **photocopy of the panel's manual** — every dial's name, address, which bits it has, and what it's allowed to do — plus a **sticky note** for each dial: *"what I believe it is currently set to"* (the **mirror**).

Then testing becomes natural: write a value, read it back, compare with the sticky note. If the chip disagrees with the note, either the chip or your photocopy is wrong — and finding out which is half the skill (Exercise 02).


### Why a register model

Registers are the software-visible contract of hardware. A **register model** is a testbench-side description of that contract — names, addresses, fields, access policies, reset values — plus a **mirror**: what the testbench believes each register holds. With it, a test writes `blk.mtvec.write(status, 32'h200)` instead of building bus transactions by hand, and generic sequences (reset check, bit-bash, access check) work for any block described in the model.


### CPU specifics: two access paths

A CPU's CSRs are visible two ways:

| Path | How | Checked by |
|---|---|---|
| **Architectural** | the program executes `CSRRW`/`CSRRS` instructions | the retire-trace scoreboard (Module 06): the ISS models the CSR values |
| **Debug / register port** | a separate bus (a debug module, JTAG-to-register bridge, memory-mapped control port) | **RAL** (this module) |

`mini_cpu_if` is not extended in this course; the register port is a **separate interface**, `mini_cpu_csr_if`, defined in `example02.sv` together with a slave stub that holds four CSRs. Module 10 discusses how the two paths coexist in a full bench. The RAL machinery is exactly what you would use for any memory-mapped register block.


### The CSR set

| CSR | Address | Fields | Reset |
|---|---|---|---|
| `mstatus` | 0x300 | `MIE` [3] RW, `MPIE` [7] RW | 0x0 |
| `mtvec` | 0x305 | `BASE` [31:2] RW, `MODE` [1:0] RW | `BASE` = 0x40, i.e. 0x100 |
| `mepc` | 0x341 | `EPC` [31:1] RW, `ZERO` [0] RO | 0x0 |
| `mcause` | 0x342 | `CODE` [31:0] RO, volatile | 0x0 |

(Fictional CPU; the numbers are RISC-V-flavoured.)


---

## UVM Mechanics

### The model classes (**PORTABLE UVM CONCEPT**)

| Class | Role | Key calls |
|---|---|---|
| `uvm_reg_field` | one field: size, bit position, access policy, reset | `configure(parent, size, lsb, access, volatile, reset, has_reset, is_rand, individually_accessible)` |
| `uvm_reg` | one register: owns fields | `new(name, n_bits, has_coverage)`; `build()` creates and configures the fields; `configure(block, regfile, hdl_path)` |
| `uvm_reg_block` | a group of registers and maps | `create_map(name, base, n_bytes, endian, byte_addressing)`; `lock_model()` |
| `uvm_reg_map` | address map: register → address, bus width, sequencer | `add_reg(reg, offset, rights)`; `set_sequencer(seqr, adapter)`; `set_auto_predict(bit)` |
| `uvm_reg_adapter` | converts a register operation (`uvm_reg_bus_op`) to a bus item and back | `reg2bus`, `bus2reg`; flags `supports_byte_enable`, `provides_responses` |
| `uvm_reg_predictor#(BUSTYPE)` | keeps the mirror updated from *observed* bus traffic | fields `map`, `adapter`; port `bus_in` |

`lock_model()` must be called after building and before use; it freezes the structure and computes addresses.

**Access policies** (the `access` string of a field): `"RW"` read/write, `"RO"` read-only (a write has no effect), `"WO"`, `"W1C"` (write 1 to clear), `"RC"` (clear on read), and more. The policy tells the *predictor* what a write does to the mirror, and the checker what to expect on a read. Setting a wrong policy makes the model disagree with a correct DUT.


### Desired versus mirrored

**In plain words:** *desired* = what **you want** the dial to say; *mirrored* = what you **believe it says right now**. `set()` changes only the first. A real write moves the chip, and then your belief follows. `update()` = "write only if what I want differs from what I believe".

Every field has two stored values:
- **desired**: what you intend the register to hold (`set()`, `get()`, `randomize()`);
- **mirrored**: what the model believes the **DUT** holds (updated by completed accesses and by `predict`).

`update()` writes the register if desired ≠ mirrored. `mirror()` reads the DUT and refreshes (and, with `UVM_CHECK`, **compares** the read value with the mirror before updating it). `reset()` sets both to the reset values.

| Call | Does what |
|---|---|
| `write(status, value, path)` | bus write; mirror updated (frontdoor: by auto-predict or the predictor) |
| `read(status, value, path)` | bus read; value returned; mirror refreshed with it |
| `poke` / `peek` | backdoor write/read of the DUT's storage |
| `set` / `get` | model only: desired value |
| `predict(value, be, kind)` | model only: tell the mirror what happened (`UVM_PREDICT_WRITE`: apply access policy; `UVM_PREDICT_READ`; `UVM_PREDICT_DIRECT`: force the value — for hardware-driven changes) |
| `mirror(status, check)` | read, optionally compare with the mirror |

Fields marked **volatile** (hardware can change them, like `mcause`) are not compared by `mirror(UVM_CHECK)`.


### Frontdoor

**In plain words:** *frontdoor* = go in through the real entrance (the bus): slow, but it tests the entrance too. *Backdoor* = look through a window straight at the register's storage: instant, no bus, so side effects don't happen. The **adapter** is the doorman who translates "write 0x200 to mtvec" into the bus's own language.

The access goes through a real bus: `reg.write` → `reg2bus` builds a bus item → the map's sequencer sends it to the driver → the driver completes the item (for a read, **fills in the read data in the same item** when `provides_responses == 0`) → `bus2reg` converts it back into `status` and `value`.

**Adapter flags.** `provides_responses = 0`: the driver completes the same item and the adapter reads the result from it. `provides_responses = 1`: the driver must send a **separate response** (`put_response`) and the register layer waits for it — set it to 1 without a response-sending driver and every access **hangs**. `supports_byte_enable`: whether the bus has byte strobes.


### Mirror updating: auto-predict versus predictor

- **Auto-predict** (`map.set_auto_predict(1)`): the mirror is updated automatically when a register operation *issued through the model* completes. Simple; blind to accesses that did not go through the model.
- **Explicit prediction** (`set_auto_predict(0)`): a **monitor** on the bus publishes every access to a `uvm_reg_predictor`, which updates the mirror. It sees all traffic — other masters, the CPU's own instruction path, hardware — and is the right choice in an integrated bench:

```systemverilog
pred = uvm_reg_predictor#(mcpu_csr_item)::type_id::create("pred", this);
pred.map = blk.default_map;  pred.adapter = adapter;
blk.default_map.set_auto_predict(0);
csr_mon.ap.connect(pred.bus_in);
```

Use one of the two, not both (double updates).


### Backdoor

A backdoor access reads or writes the DUT's storage directly through the **UVM HDL DPI** (`uvm_hdl_read/deposit`), in **zero simulation time**, with no bus activity. It needs hierarchical HDL paths (`blk.add_hdl_path("tb_top_ral.csr", "RTL")`, `reg.add_hdl_path_slice("mstatus_q", 0, 32)`) and simulator support (**SIMULATOR/VERSION-DEPENDENT**: DPI library, signal visibility, read/write access to the signal). Uses: fast initialisation, peeking at a register for debug, and **independent** verification (backdoor read versus frontdoor read finds adapter/decode bugs). Costs: bypasses the bus, so side effects (clear-on-read, bus errors, timing) do not happen.


### Built-in sequences

Ready-made sequences, started with `seq.model = blk; seq.start(null)` (or on a sequencer):

| Sequence | Does |
|---|---|
| `uvm_reg_hw_reset_seq` | reads every register after reset and compares with the reset value |
| `uvm_reg_bit_bash_seq` | writes 1s and 0s to every bit of every RW field and reads back |
| `uvm_reg_access_seq` | writes via frontdoor, reads via backdoor and vice versa |
| `uvm_reg_mem_built_in_seq` | runs the common set |
You can exclude a register from a test with the resource-database attribute `NO_REG_TESTS` (and test-specific ones such as `NO_REG_BIT_BASH_TEST`); the exact attribute handling is **SIMULATOR/VERSION-DEPENDENT**. Their log text is the library's, so this course does not hand-trace it.


### Model completeness

A mirror check compares **only the bits the model describes**. A bit that no field covers is invisible: a stuck bit there passes every test. Describe every implemented bit, including reserved/zero bits (as RO fields), or the checks are blind.


---

## Code Walkthrough

**How to read the examples:** `example01.sv` is the **photocopy only** — no chip, no bus; it shows desired/mirrored/predict with numbers you can check. `example02.sv` adds the **real door**: a tiny bus, a chip stub with a deliberate bug (`mepc` bit 0 stuck), a driver and the adapter. Follow one write: `reg.write` → `reg2bus` → driver → chip → driver returns data → `bus2reg` → mirror updated.


### 1. Building the model (`example01.sv`)

```systemverilog
mie.configure (this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);    // size, lsb, access, volatile, reset, has_reset, is_rand, ind.
...
default_map = create_map("csr_map", 'h0, 4, UVM_LITTLE_ENDIAN, 0);
mstatus.configure(this, null, "");  mstatus.build();
default_map.add_reg(mstatus, 'h300, "RW");
```

Four registers, one block, one map. `byte_addressing = 0` with 4-byte data: one address unit per register, so CSR numbers can be used directly as addresses. The test builds the block (`configure`, `build`, `lock_model`) — the block is a `uvm_object`, not a component.


### 2. What the API does without any bus

The test (no DUT) shows, with hand-derived output at the end of the file: after `reset()` the mirrors hold reset values (mtvec = `0x40 << 2 = 0x100`); `set()` changes the desired value to `0x88` while the mirror stays 0; `predict(0x88, UVM_PREDICT_WRITE)` moves the mirror; a WRITE prediction on RO `mcause` changes nothing, while `UVM_PREDICT_DIRECT 0xB` forces the mirror (a hardware change); `mepc`'s write of `0x1001` predicts `0x1000` because bit 0 is RO.


### 3. Addresses

`get_address()` returns the map offset: `0x300`, `0x305`, `0x341`, `0x342`, available after `lock_model()`.


### 4. A frontdoor stack (`example02.sv`)

The CSR bus (`mini_cpu_csr_if`), a slave stub with the four CSRs (mstatus masked to `0x88`, mtvec full 32 bits, mepc with bit 0 forced to 0 unless a bug parameter is set, mcause read-only), a driver, the item and the adapter:

```systemverilog
reg2bus: it.we = (rw.kind == UVM_WRITE); it.addr = rw.addr[11:0]; it.wdata = rw.data[31:0];
bus2reg: rw.kind = it.we ? UVM_WRITE : UVM_READ;  rw.data = it.we ? it.wdata : it.rdata;  rw.status = UVM_IS_OK;
```

The driver returns the read data in `req.rdata` before `item_done` (matching `provides_responses = 0`). Each access takes three clock edges (30 ns) from the previous completion.


### 5. Reading the run

Hand-derived: `mtvec` write 0x200 completes at 65 ns (first access starts at 42, waits for the 45 ns edge), read at 95 ns returns 0x200; `mstatus` write `0xFFFFFFFF` at 125 ns leaves `0x88` in both the DUT and the mirror; the read at 155 ns returns 0x88, and the backdoor read in the same time step agrees (zero time). Then the bug: the DUT is built with `MEPC_BIT0_BUG`, so writing `0x1001` leaves bit 0 stuck at 1; the mirror predicts `0x1000`; `mirror(UVM_CHECK)` at 215 ns reads `0x1001` and reports a mismatch on the RO field `ZERO` — *because that bit is in the model*. Remove the `zero` field and the same test passes (Exercise 02).


---

## Common Pitfalls

- **`lock_model()` not called** → the first access errors or addresses are wrong (message library-specific) → build, then `lock_model()` once per top-level block.
- **Map has no sequencer/adapter** (`set_sequencer` forgotten) → frontdoor access fails with a "no adapter/sequencer" report (text library-specific) → call `set_sequencer(seqr, adapter)` (conventionally in `connect_phase`).
- **`provides_responses = 1` with a driver that never responds** → every register access hangs → match the flag to the driver's behaviour.
- **`bus2reg` fills `data` from the wrong field** (`wdata` for a read) → reads return stale or zero data → read data comes from the bus item's read field.
- **Both auto-predict and a predictor** → the mirror is updated twice (harmless for plain RW, wrong for clear-on-read/W1C) → pick one.
- **Incomplete model** (reserved or RO bits not described) → a stuck bit passes `mirror(UVM_CHECK)` → describe every implemented bit.
- **Wrong access policy or reset value** → a correct DUT "fails" `uvm_reg_hw_reset_seq` / mirror checks → derive both from the specification, not from the RTL.
- **Backdoor path or visibility wrong** → `uvm_hdl_read` failure (message simulator-specific) or X values → check the instance path and simulator access options.
- **Mixing backdoor writes and mirror checks without `predict`** → mirror out of date, spurious mismatches → use `poke` (updates the mirror) or predict explicitly.


---

## Interview Angle

**Q1. What is a register model, and what is the mirror?**
A testbench description of a block's registers (fields, access, reset, addresses) plus a *mirror*: the model's belief of what the DUT holds. The mirror is updated by completed accesses or by a predictor watching the bus, and is the reference for read checks.

**Q2. Desired versus mirrored value?**
Desired is what you want the register to contain (set locally); mirrored is what the model thinks it currently contains. `update()` writes the difference; `mirror()` reads and (optionally) checks.

**Q3. What does an adapter do?**
Converts between the abstract register operation (`uvm_reg_bus_op`: kind, address, data) and the protocol's bus item: `reg2bus` for requests, `bus2reg` for results. Flags say whether the bus has byte enables and whether responses come as separate items.

**Q4. Frontdoor versus backdoor?**
Frontdoor uses the real bus (takes time, exercises decode and side effects); backdoor reads/writes the DUT's storage by hierarchical path through DPI (zero time, no bus). Use frontdoor to verify the bus path, backdoor for speed, initialisation and independent cross-checks.

**Q5. Auto-predict versus an explicit predictor?**
Auto-predict updates the mirror for operations issued via the model only; an explicit predictor driven by a bus monitor sees all traffic, including accesses from other masters or hardware, and is the robust choice in an integrated environment.

**Q6. Which built-in sequences exist and what do they find?**
`uvm_reg_hw_reset_seq` (wrong reset values), `uvm_reg_bit_bash_seq` (stuck or aliased bits), `uvm_reg_access_seq` (frontdoor/backdoor path mismatch); they find decode, policy and reset errors with no test-specific code.

**Q7. How does RAL help for CPU CSRs, and what does it not cover?**
It verifies the register-port view of the CSRs (reset values, access policies, field behaviour). The architectural effects of CSR *instructions* (CSRRW updating `mepc` on a trap, privilege rules) come from the ISS-based scoreboard; a good bench keeps the two consistent through a predictor that observes both paths.

**Q8. A mirror check passes but the DUT has a stuck bit. What do you suspect?**
The bit is not described by any field (an incomplete model), or the field is marked volatile, or the check is disabled for that register.


---

## Recap in five lines

1. The **model** = photocopy of the manual (fields, access, reset, address) + the **mirror** (my belief).
2. **Desired** vs **mirrored**: `set` changes desired; completed accesses and `predict` change the mirror.
3. **Frontdoor** = through the bus via the **adapter**; **backdoor** = zero-time peek by path (simulator-dependent).
4. `provides_responses` must match the driver, or every access **hangs**.
5. A bit **not described** in the model can **never fail** — describe every implemented bit.

**Questions beginners often ask**
- *"Mirror mismatch on a correct chip?"* — suspect the model first (bit position, access policy, reset value).
- *"Auto-predict or predictor?"* — auto-predict only knows about accesses made through the model; a predictor watching the bus sees everything.
- *"Why is `lock_model()` needed?"* — it freezes the structure and computes addresses; call it once after building.


---

## Check Your Understanding

1. In `example01.sv`, `mstatus.mie.set(1); mstatus.mpie.set(1);` is followed by `get()` returning `0x88` and `get_mirrored_value()` returning 0. What does each return, and what would have to happen for the mirror to become `0x88`?
2. The DUT stub in `example02.sv` masks `mstatus` writes to `0x88`. The test writes `0xFFFFFFFF`. What do the mirror and a read return, and why do they agree without any special handling?
3. If the `zero` field were removed from `mcpu_mepc_reg`, what would `mepc.mirror(status, UVM_CHECK)` report for the bug-injected DUT, and why?

Answers: `solutions/module09/check_your_understanding.md`.


---

## Exercises

| File | Type | Summary |
|---|---|---|
| `exercise01.md` | Fill-in | Write the adapter for the CSR bus. Subtle trap: the response flag, and where read data comes from. |
| `exercise02.md` | Debug the testbench | Two silent model errors: a field at the wrong bit position and a missing reserved bit. |
| `exercise03.md` | Design | Design the CSR verification plan with RAL: tests, predictor, two access paths, coverage. |


---

## Reference

**Classes:** `uvm_reg_field`, `uvm_reg`, `uvm_reg_block`, `uvm_reg_map`, `uvm_reg_adapter`, `uvm_reg_predictor#(BUSTYPE)`, `uvm_reg_bus_op`, `uvm_reg_item` (internal), `uvm_reg_sequence`, built-ins `uvm_reg_hw_reset_seq`, `uvm_reg_bit_bash_seq`, `uvm_reg_access_seq`, `uvm_reg_mem_built_in_seq`.

**Enumerations/types:** `uvm_status_e` (`UVM_IS_OK`, `UVM_NOT_OK`, `UVM_HAS_X`), `uvm_door_e` (`UVM_FRONTDOOR`, `UVM_BACKDOOR`, `UVM_DEFAULT_DOOR`), `uvm_predict_e` (`UVM_PREDICT_DIRECT`, `UVM_PREDICT_READ`, `UVM_PREDICT_WRITE`), `uvm_check_e` (`UVM_CHECK`, `UVM_NO_CHECK`), `uvm_reg_data_t`, `uvm_reg_addr_t`, `UVM_NO_COVERAGE`, `UVM_LITTLE_ENDIAN`, `UVM_READ`, `UVM_WRITE`.

**Methods:** `field.configure(...)`, `reg.build()`, `reg.configure(blk, null, "")`, `blk.create_map(...)`, `map.add_reg(...)`, `map.set_sequencer(seqr, adapter)`, `map.set_auto_predict(bit)`, `blk.lock_model()`, `blk.reset()`, `reg.write/read/mirror/update/poke/peek`, `reg.set/get/get_mirrored_value/get_reset/get_address/predict`, `blk.add_hdl_path`, `reg.add_hdl_path_slice`, `adapter.reg2bus/bus2reg`.

**Forward references made:** one bench with the retire-trace scoreboard and the register layer consistent through a predictor; reset handling that also resets the mirror (Module 10).
