# Module 09 / Exercise 01 — The adapter for the CSR bus (fill-in)

**Type:** Fill-in. SV/UVM-compile-checkable by inspection.

## Goal

Write `mcpu_csr_adapter`, which lets the register layer talk to the CSR bus. After it is correct, `blk.mtvec.write(status, 32'h200)` and `blk.mtvec.read(status, val)` complete with the right data and do not hang.

## Setup / DUT assumptions

- Bus item (given):

```systemverilog
class mcpu_csr_item extends uvm_sequence_item;
  `uvm_object_utils(mcpu_csr_item)
  bit        we;
  bit [11:0] addr;
  bit [31:0] wdata, rdata;
  function new(string name = "mcpu_csr_item"); super.new(name); endfunction
endclass
```

- Bus: no byte enables. The **driver completes the same item**: for a read it stores the data in `rdata` before calling `item_done`; it never sends a separate response item.
- Register addresses are CSR numbers (12 bits); data is 32 bits. `uvm_reg_bus_op` carries `kind` (`UVM_READ`/`UVM_WRITE`), `addr`, `data` (64-bit `uvm_reg_data_t`) and `status`.

## Skeleton

```systemverilog
class mcpu_csr_adapter extends uvm_reg_adapter;
  `uvm_object_utils(mcpu_csr_adapter)

  function new(string name = "mcpu_csr_adapter");
    super.new(name);
    // TODO 1: describe this bus to the register layer (two properties)
    // YOUR CODE HERE
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    mcpu_csr_item it;
    // TODO 2: build the bus item for this register operation
    // YOUR CODE HERE
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    mcpu_csr_item it;
    // TODO 3: convert the completed bus item back into the register operation
    // YOUR CODE HERE
  endfunction
endclass
```

## A correct answer must achieve

1. A frontdoor write puts the register's address and the write data on the bus item, with `we = 1`.
2. A frontdoor read returns the data that the driver stored in `rdata`, and reports `UVM_IS_OK`.
3. No access hangs waiting for a separate response.
4. A non-`mcpu_csr_item` handed to `bus2reg` produces a clear fatal, not a silent wrong value.
5. For a write, `bus2reg` reports the written data (not stale read data), so the predicted mirror matches the write.

Compare against `solutions/module09/exercise01_solution.md`.
