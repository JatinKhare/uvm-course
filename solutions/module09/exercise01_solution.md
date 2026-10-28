# Module 09 / Exercise 01 — Solution

## Full solution code

```systemverilog
class mcpu_csr_adapter extends uvm_reg_adapter;
  `uvm_object_utils(mcpu_csr_adapter)

  function new(string name = "mcpu_csr_adapter");
    super.new(name);
    // TODO 1
    supports_byte_enable = 0;
    provides_responses   = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    mcpu_csr_item it;
    // TODO 2
    it = mcpu_csr_item::type_id::create("csr_it");
    it.we    = (rw.kind == UVM_WRITE);
    it.addr  = rw.addr[11:0];
    it.wdata = rw.data[31:0];
    return it;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    mcpu_csr_item it;
    // TODO 3
    if (!$cast(it, bus_item)) begin
      `uvm_fatal("CAST", "bus2reg: bus_item is not a mcpu_csr_item")
      return;
    end
    rw.kind   = it.we ? UVM_WRITE : UVM_READ;
    rw.addr   = it.addr;
    rw.data   = it.we ? it.wdata : it.rdata;
    rw.status = UVM_IS_OK;
  endfunction
endclass
```

## TODO 1 — The subtle one: `provides_responses = 0`

`provides_responses` tells the register layer whether the driver sends a **separate response item** (`put_response`) that carries the result. This driver completes the same request item (filling `rdata`) and never sends a response. With `provides_responses = 1` the register layer, after `finish_item`, waits for a response that never comes: **every register access hangs** at the first read or write, with no error message. With `0`, it calls `bus2reg` on the same item after `finish_item` returns.
`supports_byte_enable = 0`: the bus has no strobes, so the layer must not generate byte-enable patterns.

## TODO 2 — `reg2bus`

Create the item through the factory, copy the direction (`UVM_WRITE` → `we = 1`), the low 12 address bits, and the low 32 data bits (the 64-bit `rw.data` is truncated explicitly).
**Wrong answers and symptoms:** `it.we = rw.kind` without comparing (a 1-bit assignment of an enum: the value of `UVM_READ` is 0 and `UVM_WRITE` is 1 in the library's enumeration, but relying on it is fragile and wrong if the enumeration changes); forgetting `wdata` → every write stores 0 on the DUT and the mirror (predicted from the *write value in the bus op*) disagrees with the DUT.

## TODO 3 — `bus2reg`

The register layer takes `rw.data` and `rw.status` as the result. For a **read** the data lives in `it.rdata`, filled by the driver; for a write it is `it.wdata`.
**Wrong answers and symptoms:**
- `rw.data = it.wdata` always: reads return 0 (the `wdata` field of a read item is 0): `read` returns 0 for every register, and with auto-predict the mirror is overwritten with 0 after every read.
- No `rw.status` assignment: the status stays at whatever the layer initialised (commonly "not OK" semantics in some flows); reads and writes may report failure even though the bus worked (behaviour library-specific): set it explicitly.
- Using `$cast` without checking: a wrong item type produces a null `it` and a null dereference with a poor message; the checked cast gives a clear fatal.

## Self-review checklist

- [x] No config_db in this class; adapter is a `uvm_object` (name-only constructor, `super.new(name)`).
- [x] `reg2bus` and `bus2reg` signatures match the library (`const ref uvm_reg_bus_op` and `ref uvm_reg_bus_op`).
- [x] The adapter flags match the driver (`provides_responses = 0`, driver stores `rdata` in the same item).
- [x] Reads come from `rdata`, writes from `wdata`; status set.
- [x] Types match (`mcpu_csr_item`); no undeclared identifiers.

## Expected log (hand-derived, not simulated)

With the driver and slave of `example02.sv` and a write of `0x200` to mtvec followed by a read, the adapter-visible effects are: the bus item for the write has `we=1, addr=0x305, wdata=0x00000200`; after the read, `it.rdata = 0x00000200` and `bus2reg` returns `data = 0x200, status = UVM_IS_OK`; `read` yields `0x200` and the mirror stays `0x200`. Times as in `example02.sv` (65 ns and 95 ns).

## The result that matters

The adapter is a two-function translator plus two flags, and the flags decide whether the *whole register layer* hangs. A hang at the first access, with no message, is the signature of `provides_responses` not matching the driver. Variation to try: switch the driver to call `put_response` and decide which flag value and which `bus2reg` source of data are then correct.
