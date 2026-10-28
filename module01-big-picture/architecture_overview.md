# The Big Picture: the CPU you are verifying, and the testbench you build around it

> Read this **before** Module 01 and come back to it after every module.
> It answers two questions: **(A) what is `mini_cpu`, from scratch?** and **(B) what does the UVM testbench around it look like, and how does it grow module by module?**
> No prior CPU knowledge is assumed. Every box in every diagram is named after something that exists in the course files.

---

## How to read the diagrams

```
+---------+      a box = a hardware unit, a module, or a class
| name    |
+---------+

 ----->        data / a call flowing in the arrow's direction
 =====>        a connection that is NEW in the module being discussed
 [NEW M04]     a box introduced by that module
 (dashed)      "optional / only in some modules"
```

Two "worlds" appear in every picture:

| World | What lives there | Examples |
|---|---|---|
| **Static world** (hardware / SystemVerilog modules) | clocks, wires, the CPU itself, interfaces | `tb_top`, `mini_cpu`, `mini_cpu_if` |
| **Class world** (UVM) | the testbench objects that create stimulus, watch, and judge | `mcpu_base_test`, `mcpu_env`, agents, scoreboard |

The only bridge between the two worlds is the **virtual interface** (explained in Part B).

---

# PART A — The CPU, from scratch

## A1. What is a CPU doing, in one paragraph?

A CPU runs a **program**: a list of tiny instructions stored in memory (for example "add these two numbers", "load a value from memory", "jump if two values are equal"). It repeats the same four-step loop forever:

```
        +---------+     +----------+     +-----------+     +----------+
   +--> | 1 FETCH | --> | 2 DECODE | --> | 3 EXECUTE | --> | 4 RETIRE | ---+
   |    +---------+     +----------+     +-----------+     +----------+    |
   |    ask memory      work out what    do the work       "this one is     |
   |    for the next    the 32-bit word  (add, load,       finished and its |
   |    instruction     means            store, branch)    result is final" |
   +-----------------------------  repeat with the next pc  <--------------+
```

- **pc** (program counter) = the address of the instruction being processed. After most instructions it simply moves on by 4 bytes (each instruction is a 32-bit = 4-byte word).
- **Registers** = 32 tiny fast storage cells named `x0 … x31`, each 32 bits wide. Instructions mostly work on registers. **`x0` is special: it always reads as 0 and ignores writes.**
- **Memory** = big, slow storage addressed by byte address. Loads copy memory → register, stores copy register → memory.
- **Retire** = the moment an instruction is officially *done*. Verification engineers love retirement: it is the moment when the **architectural result** (which register changed, to what value) is final and can be compared with a reference.

## A2. The `mini_cpu` block diagram

`mini_cpu` is a **small, fictional, 32-bit, in-order CPU** with RISC-V-flavoured instructions. "In-order" means instructions finish in the same order as the program lists them. Here is every unit and how the units connect:

```
  INSTRUCTION MEMORY (outside the CPU)                  DATA MEMORY
        ^  if_req, if_addr                                  ^  ls_req, ls_we, ls_addr, ls_wdata
        |   v if_rvalid, if_rdata                            |   v ls_rvalid, ls_rdata
 +------+---------------------------------------------------+--------------------------+
 |  mini_cpu                                                                           |
 |                                                                                     |
 |   +--------+  pc    +---------+  32-bit word  +----------+  register    +---------+  |
 |   | 1  PC  |------->| 2 FETCH |-------------->| 3 DECODE |------------->| 4 REG   |  |
 |   |        |<-+     |  UNIT   |               |          |  numbers     |  FILE   |  |
 |   +--------+  |     +---------+               +----+-----+              | x0..x31 |  |
 |        ^      |                                    |                     +----+----+  |
 |        | next |           +------------------------+-----------+              |       |
 |        | pc   |           |            |                       |              |       |
 |   +----+------+--+   +----v-----+  +---v----------+      +-----v------+       |       |
 |   | 6  BRANCH     |   | 5  ALU   |  | 7 LOAD/STORE |      | 8  CSR     |       |       |
 |   |    UNIT       |   | add, sub |  |    UNIT      |<---- |    UNIT    |       |       |
 |   | (BEQ: change  |   | and, or  |  | (LW, SW)     |      | (CSRRW)    |       |       |
 |   |  the pc?)     |   +----+-----+  +------+-------+      +-----+------+       |       |
 |   +---------------+        |               |                    |              |       |
 |                            +---------+-----+----------+---------+              |       |
 |                                      v                                           |       |
 |                              +---------------+   writes result back ------------+       |
 |                              | 9  RETIRE /   |                                          |
 |                              |    COMMIT     |-----> retire_valid, retire_pc, retire_instr,
 |                              +---------------+       retire_rd, retire_data  (to the outside)
 +-------------------------------------------------------------------------------------+
          ^ clk, rst_n (clock and active-low reset)            ^ irq (interrupt request)
```

### What each unit does (and what we check about it)

| # | Unit | What it does | Pins it touches | What the testbench cares about |
|---|---|---|---|---|
| 1 | **PC** | holds the address of the current instruction | `if_addr` (it *is* the fetch address) | the address of every fetch is right (including after a branch) |
| 2 | **Fetch unit** | asks instruction memory for the word at `pc` and waits for the answer | `if_req`, `if_addr`, `if_rvalid`, `if_rdata` | the fetch handshake; the testbench plays the *memory* here |
| 3 | **Decode** | splits the 32-bit word into opcode and register numbers | (internal) | not directly visible; its effect shows up in what retires |
| 4 | **Register file** | 32 registers; `x0` is always 0 | (internal) | register values appear indirectly through retired results |
| 5 | **ALU** | does arithmetic/logic: `ADD SUB AND OR` and `ADDI` | (internal) | **result correctness** (`retire_data`) |
| 6 | **Branch unit** | for `BEQ`: if two registers are equal, jump (change the pc) else go on | (changes the pc) | the next fetch address is right |
| 7 | **Load/Store unit (LSU)** | `LW` reads memory into a register; `SW` writes a register to memory | `ls_req`, `ls_we`, `ls_addr`, `ls_wdata`, `ls_rvalid`, `ls_rdata` | right address, right data, store-then-load returns the stored value |
| 8 | **CSR unit** | CSRs = **C**ontrol and **S**tatus **R**egisters (settings like "interrupts enabled", "trap vector"); `CSRRW` reads the old value and writes a new one | (internal; separate debug port in Module 09) | reset values, read/write behaviour |
| 9 | **Retire / commit** | declares an instruction done and publishes what it did | `retire_valid`, `retire_pc`, `retire_instr`, `retire_rd`, `retire_data` | **this is the stream the scoreboard checks** |

> **Real CPUs are pipelined** (several instructions in flight at once, which creates *hazards*). The course's `mini_cpu_core` keeps **one instruction in flight** for simplicity, but the testbench still learns hazard thinking: Module 07 *generates* hazard-rich programs and Module 08 *measures* them. See "What is not modelled" at the end of Part A.

## A3. The pins: `mini_cpu_if`

All the wires of the CPU are bundled into one SystemVerilog **interface** called `mini_cpu_if`. Direction is from the **CPU's** point of view.

```
                         mini_cpu_if                            
   clk, rst_n  ----------------------------------->  (inputs to everyone)

   FETCH BUS      if_req      CPU  --> memory     "I want an instruction"
                  if_addr     CPU  --> memory     "from this address (pc)"
                  if_rvalid   CPU  <-- memory     "here it is" (one-cycle pulse)
                  if_rdata    CPU  <-- memory     the 32-bit instruction word

   LOAD/STORE     ls_req      CPU  --> memory     "I want to load/store"
   BUS            ls_we       CPU  --> memory     1 = store, 0 = load
                  ls_addr     CPU  --> memory     address
                  ls_wdata    CPU  --> memory     data to store
                  ls_rvalid   CPU  <-- memory     response
                  ls_rdata    CPU  <-- memory     data loaded

   INTERRUPT      irq         CPU  <-- outside    interrupt request line

   RETIRE TRACE   retire_valid  CPU --> outside    "an instruction just retired"
   (output only)  retire_pc     CPU --> outside    its address
                  retire_instr  CPU --> outside    its 32-bit word
                  retire_rd     CPU --> outside    destination register (0 = none)
                  retire_data   CPU --> outside    value written to that register
```

Notice who plays what role: **the CPU is the master.** It asks for instructions and data. In the testbench, the "memory side" is played by **UVM agents** (Module 04). That is why the instruction stream in the testbench is not "pushed" at the CPU: it is *served* to the CPU when it asks.

## A4. The instructions the course uses

Nine instructions, encoded exactly like the open RISC-V RV32I format (only the subset we need):

| Mnemonic | Meaning | Format | Example |
|---|---|---|---|
| `ADD  rd, rs1, rs2` | rd = rs1 + rs2 | R | `ADD x3,x1,x2` → `0x002081b3` |
| `SUB  rd, rs1, rs2` | rd = rs1 − rs2 | R | |
| `AND  rd, rs1, rs2` | bitwise and | R | |
| `OR   rd, rs1, rs2` | bitwise or | R | |
| `ADDI rd, rs1, imm` | rd = rs1 + (sign-extended imm) | I | `ADDI x1,x0,5` → `0x00500093` |
| `LW   rd, imm(rs1)` | rd = memory[rs1 + imm] | I | `LW x5,0(x4)` → `0x00022283` |
| `SW   rs2, imm(rs1)` | memory[rs1 + imm] = rs2 | S | `SW x3,0(x4)` → `0x00322023` |
| `BEQ  rs1, rs2, off` | if rs1 == rs2: pc += off, else pc += 4 | B | |
| `CSRRW rd, csr, rs1` | rd = old CSR; CSR = rs1 | I | |

How a 32-bit word is cut up (R-type shown; the other formats rearrange the same fields):

```
 31         25 24    20 19    15 14  12 11     7 6        0
 +------------+--------+--------+------+--------+----------+
 |   funct7   |  rs2   |  rs1   |funct3|   rd   |  opcode  |      ADD x3,x1,x2
 +------------+--------+--------+------+--------+----------+
 | 0000000    | 00010  | 00001  | 000  | 00011  | 0110011  |   = 0x002081b3
 +------------+--------+--------+------+--------+----------+
     "add"       x2       x1             x3      "register-register ALU op"
```

`cpu_instr_item` (Module 03) is the testbench object that **holds one such instruction** (opcode, rd, rs1, rs2, imm) and knows how to `encode()` itself into the 32-bit word.

## A5. The fetch handshake, step by step

This is the single most important timing relationship in the course (Module 04 implements the memory side; Module 10's `mini_cpu_core` implements the CPU side). With a 10 ns clock (rising edges at 5, 15, 25 … ns) and reset released at 42 ns:

```
 clk       _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
 edge      45   55   65   75   85   95
 if_req    ___/‾‾‾‾‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾‾      CPU asks (high), drops after it got the word
 if_rvalid ________/‾‾‾‾\____________________/‾‾    memory answers with a ONE-cycle pulse
 if_rdata  ========< instr #1 >==========         the instruction word, valid with if_rvalid
 retire_*  ______________________/‾‾‾‾\_____        CPU executes at the edge it sees if_rvalid, then publishes
```

In words:
1. At **45 ns** (first edge after reset is released) the CPU raises `if_req`.
2. At **55 ns** the memory side (the UVM *driver*) sees `if_req` and drives `if_rvalid`/`if_rdata`.
3. At **65 ns** the CPU samples `if_rvalid = 1`: it **executes** the instruction and lowers `if_req`.
4. At **75 ns** the **retire record** is visible and the UVM *retire monitor* samples it.
5. The cycle repeats: with `mini_cpu_core` one instruction takes **30 ns** (executions at 65, 95, 125, 155, 185 ns).

## A6. The CSR block and its debug port (Module 09)

CSRs are a handful of special registers. The course models four, reachable two ways: by the `CSRRW` **instruction**, and through a separate **debug register port** (`mini_cpu_csr_if`) used by the register-model (RAL) bench.

```
   +---------------------------+  csr_req/we/addr/wdata   +-----------------------------+
   | register-port master      | -----------------------> | mini_cpu_csr_regs (CSR stub)|
   | (UVM driver in Module 09) | <----------------------- |  mstatus 0x300  mtvec 0x305 |
   +---------------------------+  csr_rvalid, csr_rdata   |  mepc    0x341  mcause 0x342|
                                                          +-----------------------------+
```

| CSR | Address | What it is for (simplified) |
|---|---|---|
| `mstatus` | 0x300 | global enable bits (MIE: interrupts on, MPIE: previous setting) |
| `mtvec` | 0x305 | where to jump on a trap/interrupt (the "trap vector") |
| `mepc` | 0x341 | the pc to return to after a trap |
| `mcause` | 0x342 | why the trap happened (set by hardware) |

## A7. The two DUT models you will meet

| Name | Where | What it does | Why |
|---|---|---|---|
| `mini_cpu` (**stub**) | Module 01 | fetches sequential addresses and "retires" whatever it fetched; does **not** compute results | gives the first testbench some signals to watch (Modules 01–04) |
| `mini_cpu_core` (**executing**) | Module 10 | really executes the nine instructions, has a register file and a small data memory, retires real `rd`/`data` | the integrated bench can now check *real results* |
| `mini_cpu_csr_regs` | Module 09 | four CSRs behind a register port (with a switchable bug) | gives the register model something to verify |

## A8. What is *not* modelled (be aware of it)

Traps and exceptions, interrupts actually being *taken* (`irq` exists but is ignored), error responses on the memory buses, an external data memory handshake, multi-instruction-per-cycle or out-of-order execution. Real CPU verification must cover these; the course lists them as **risks** in the capstone plan (Module 10, Exercise 03).

---

# PART B — The testbench, from scratch

## B1. Why a testbench, and why UVM?

The CPU (the **DUT**, "device under test") is just hardware: it does nothing on its own. A **testbench** is the surrounding software that:

```
   1. DRIVES it       supplies clock, reset, and the memory it asks for
   2. WATCHES it      records what the pins actually did
   3. JUDGES it       compares what happened with what *should* have happened
   4. MEASURES        records which situations were exercised (coverage)
```

**UVM** (Universal Verification Methodology) is a standard SystemVerilog **class library** with agreed names and structure for exactly these four jobs, so testbench pieces are reusable and every verification engineer reads them the same way.

## B2. Vocabulary you need (and where it is taught)

| Word | Plain meaning | Module |
|---|---|---|
| **component** | a long-lived testbench part with a parent in a tree (test, env, agent, driver, monitor, scoreboard) | 01 |
| **object** | short-lived data (an instruction, a sequence, a config) | 01 |
| **phase** | a named step every component goes through in the same order: build → connect → run → check → report | 02 |
| **objection** | "I'm not finished yet" — keeps the run phase alive | 02 |
| **factory / override** | create classes by name so a test can swap one for another | 02 |
| **sequence item** | one transaction (one instruction) | 03 |
| **sequence** | a recipe producing a stream of items | 03 |
| **sequencer** | the traffic controller between sequences and the driver | 03/04 |
| **driver** | turns a transaction into pin wiggles | 04 |
| **monitor** | turns pin wiggles back into transactions (read-only) | 04 |
| **agent** | driver + sequencer + monitor for one interface | 04 |
| **virtual interface** | a handle that lets class code reach the real wires | 01/04 |
| **config_db** | the global noticeboard for passing settings and handles | 05 |
| **TLM / analysis port** | how a monitor broadcasts what it saw to checkers and coverage | 05 |
| **scoreboard** | compares actual with expected | 06 |
| **reference model / ISS** | a software CPU that predicts the right answer | 06 |
| **constraint / randomisation** | describing *legal* stimulus and letting the simulator pick values | 07 |
| **coverage** | a record of which scenarios occurred | 08 |
| **RAL (register layer)** | a software model of the CPU's registers | 09 |

## B3. The virtual interface: the bridge between the worlds

Classes cannot connect to hardware wires directly. So `tb_top` (the hardware world) hands the class world a **handle** to the interface; every driver and monitor uses that handle to wiggle or sample the wires:

```
   STATIC WORLD                                    CLASS WORLD
   +------------------------+  uvm_config_db       +------------------------------+
   | tb_top                 |  set(... "vif" ...)  | test.get("vif")              |
   |   mini_cpu_if  vif  ---+--------------------->|   virtual mini_cpu_if  vif   |
   |   mini_cpu     (DUT)   |                      |   (a handle = a "remote")    |
   +------------------------+                      +------------------------------+
```

## B4. The three flows through every UVM testbench

Keep these in mind; every later diagram is a variation on them.

```
   STIMULUS FLOW (down)         sequence --> sequencer --> driver --> pins --> DUT
   OBSERVATION FLOW (up)        DUT --> pins --> monitor --> analysis port --> (scoreboard, coverage)
   CONTROL FLOW (sideways)      test --> config objects / factory overrides / phases --> everything
```

---

# PART C — The testbench grows, module by module

Each diagram shows the **whole bench so far**; the parts added by the current module are marked **[NEW Mnn]**.

---

## Module 01 — The big picture: a test, an interface, a DUT

**New idea:** the two worlds, `run_test()`, the first `uvm_test`.

```
  STATIC WORLD                                           CLASS WORLD (UVM)
  +--------------------------------------+               +---------------------------------+
  | tb_top                               |   run_test()  | uvm_test_top                    |
  |                                      | ============> | = mcpu_base_test      [NEW M01] |
  |  clk, rst_n (generated here)         |               |                                 |
  |                                      |   config_db   |   - gets  virtual mini_cpu_if   |
  |  +--------------------+  pins        |  "vif" =====> |   - raises an objection         |
  |  | mini_cpu_if  vif   |<-------------+---------------+   - watches retire_* pins      |
  |  +---------+----------+              |    (reads     |     directly (demo only)        |
  |            | pins                    |     pins)     +---------------------------------+
  |  +---------v----------+              |
  |  | mini_cpu (stub DUT)|  [NEW M01]   |    + a placeholder "memory" answering fetches
  |  +--------------------+              |      inside tb_top (replaced by an agent in M04)
  +--------------------------------------+
```

- **Files:** `module01/example01.sv` (the whole thing), `example02.sv` (shows the *component tree* idea: test → env → agents).
- **You learn:** why `tb_top` makes the clock/reset/DUT, why the test is a *class*, how `run_test()` starts everything, and what an objection does.

---

## Module 02 — Phases, objections and the factory: giving the tree a shape

**New idea:** *when* things happen, and *how* classes are created so they can be swapped.

```
   uvm_test_top  (mcpu_base_test)
        |  creates in build_phase (top-down) -----------------------------+
        v                                                                  |
      env  (mcpu_env)                      [NEW M02: the TREE]            |
        |-- ifetch_agent  (mcpu_ifetch_agent)   <- empty shells for now   |
        |-- lsu_agent     (mcpu_lsu_agent)                                |
        '-- scoreboard    (mcpu_scoreboard)                               |
                                                                           |
   PHASE TIMELINE   [NEW M02]                                              |
   build ---> connect ---> end_of_elab ---> start_of_sim ---> RUN ---> extract/check/report/final
   top-down    bottom-up                                       |
                                                          objections decide
                                                          when RUN ends

   FACTORY  [NEW M02]:   mcpu_scoreboard::type_id::create("sb", this)
        a test can say:  "wherever a mcpu_scoreboard is created, give me a
                          mcpu_strict_scoreboard instead"   (type or instance override)
```

- **Files:** `module02/example01.sv` (phase order + drain time), `example02.sv` (overrides).
- **You learn:** build is top-down, connect is bottom-up, only `run_phase` consumes time, the test ends when all objections drop, `new` bypasses the factory.

---

## Module 03 — Transactions and sequences: the stimulus idea

**New idea:** the instruction as an *object*, and sequences that generate streams of them.

```
   SEQUENCES (objects)                       [NEW M03]
   +-------------------------+
   | mcpu_directed_seq       |  ADDI x1,5 ; ADDI x2,7 ; ADD x3,x1,x2 ; SW x3,0(x4)
   | mcpu_rand_seq           |  n random legal instructions
   +-----------+-------------+
               |  start_item / finish_item     each item = cpu_instr_item  [NEW M03]
               v                               (op, rd, rs1, rs2, imm, encode())
        +----------------+   get_next_item /   +-----------------------+
        | mcpu_ifetch_   |   item_done         | mcpu_stub_driver      |
        | seqr (sequencer)| =================> |   (throw-away: prints |
        +----------------+                     |    each item)         |
                                               +-----------------------+

   VIRTUAL SEQUENCE   [NEW M03]: one sequence coordinating TWO sequencers
        mcpu_lw_after_sw_vseq ---> mcpu_vseqr (virtual sequencer)
                                      |-- ifetch_seqr   (instructions)
                                      '-- lsu_seqr      (data-memory preload via mcpu_mem_item)
```

- **Files:** `module03/example01.sv` (item, sequences, stub driver), `example02.sv` (virtual sequence "LW after SW").
- **You learn:** what a legal instruction is (constraints), how `start_item`/`finish_item` hand an item to the driver, why a virtual sequence exists.
- **Note:** no real pins yet: the stub driver only *prints*. Module 04 connects stimulus to the DUT.

---

## Module 04 — Driver, sequencer, monitor, agent: reaching the pins

**New idea:** the **agent** — the standard package for one interface — and how stimulus actually drives wires.

```
  CLASS WORLD                                                                      STATIC WORLD
  uvm_test_top (mcpu_ifetch_test)
     |  creates mcpu_agent_cfg [NEW M04]  (vif + active/passive)  --config_db-->  agent
     v
  mcpu_env
   |
   +-- mcpu_ifetch_agent  [NEW M04]
   |     +----------------+   +--------------------+  drives if_rvalid, if_rdata   +-------------+
   |     | sequencer      |-->| mcpu_ifetch_driver |==============================>| mini_cpu_if |
   |     | (mcpu_ifetch_  |   |  (acts as the      |  waits for if_req             |   (pins)    |
   |     |  seqr)         |   |   INSTRUCTION      |<==============================|             |
   |     +-------^--------+   |   MEMORY)          |                               |             |
   |             |            +--------------------+                               |             |
   |        sequences from M03        +--------------------+  samples if_addr,     |             |
   |                                  | mcpu_ifetch_monitor|<=== if_rdata when ====|             |
   |                                  | (read-only)        |      if_rvalid = 1    +------+------+
   |                                  +----------+---------+                              |
   |                                       ap (analysis port): mcpu_bus_txn                |
   |                                             |                                         v
   +-- mcpu_bus_logger [NEW M04] <---------------+                                  mini_cpu (DUT)
        (a temporary consumer that prints each fetch)
```

- **Files:** `module04/example01.sv` (agent package: cfg, txn, driver, monitor, agent), `example02.sv` (env, test, top).
- **You learn:** the pull handshake (`get_next_item` → drive → `item_done`), why the monitor is separate and read-only, **active vs passive** agents, why settings travel in a config object.
- **Key roles:** because the CPU is the master, this agent plays the **memory** that serves instructions.

---

## Module 05 — Configuration and connectivity: how the pieces find each other

**New idea:** the two "plumbing" systems. No new boxes — this module explains the **arrows**.

```
  CONFIGURATION PLUMBING  (uvm_config_db)  [NEW M05 explains it]

   tb_top --set("uvm_test_top","vif")--> test --set("env.ifetch_agent","cfg")--> agent
                                             |                                     |
                                       creates cfg object                  get("cfg") then hands
                                       (vif, is_active)                    it to driver & monitor


  CONNECTIVITY PLUMBING  (TLM)  [NEW M05 explains it]

   monitor.ap  ==connect==>  agent.ap  ==connect==>  consumer ...
   (analysis port)           (promoted to the           |-- uvm_analysis_imp  : write() runs at once
                              agent boundary)            '-- uvm_tlm_analysis_fifo : buffers, own pace
   * one analysis port can feed MANY consumers; zero consumers is NOT an error (silent!)
```

- **Files:** `module05/example01.sv` (config_db paths, wildcards, precedence, type matching), `example02.sv` (ports, imps, FIFO).
- **You learn:** why a missing `set` returns "not found" silently, relative vs absolute paths, higher-level `set` wins, and that connectivity mistakes are often silent.

---

## Module 06 — Scoreboard and reference model: judging the CPU

**New idea:** the **observation → checking** flow. A software CPU predicts what should retire; the scoreboard compares.

```
                                                      EXPECTED PATH
   mcpu_ifetch_agent                          +-----------------------------------------+
     monitor --ap--(fetched word)--------------> fetch_imp  --> [ ISS: mcpu_iss ] --+     |
                                              |   (write_fetch)  runs the same     |     |
                                              |   also checks fetch address == ISS pc    |
                                              |                                    v     |
                                              |                          expected queue   |
   mcpu_retire_monitor [NEW M06]              |                                    |      |
     samples retire_* pins --ap--(retire txn)--> retire_imp --> actual queue -------+      |
                                              |   (write_retire)                   v      |
                                              |                         COMPARE in order  |
                                              |            pc, instr, rd, data (with ===) |
                                              |            mismatch -> UVM_ERROR          |
                                              |            end of test -> leftovers check |
                                              |        mcpu_scoreboard [NEW M06]          |
                                              +-----------------------------------------+
```

- **Files:** `module06/example01.sv` (retire transaction, ISS, scoreboard), `example02.sv` (a synthetic feeder with one deliberately wrong result, caught at 35 ns).
- **You learn:** retire-trace checking, `uvm_analysis_imp_decl` (two inputs in one class), buffering both streams (order of arrival is not guaranteed), `===` for X-safe compare, "nothing failed ≠ passed".
- **Note:** this module uses a **synthetic** stream, because the Module 01 stub does not execute instructions.

---

## Module 07 — Constrained random: generating programs automatically

**New idea:** a **generator layer** above the sequences — layers of sequences that build legal, hazard-rich programs.

```
   TEST  (pins a few knobs:  n_alu == 4, hazard == 1, seed)
     |
     v
   mcpu_stream_seq   (scenario layer)          [NEW M07]
     |-- mcpu_alu_burst_seq     n ALU ops, optional dependency chain ("hazard")
     |-- mcpu_sw_lw_burst_seq   SW then LW to the same address
     '-- mcpu_branch_seq        one FORWARD branch (so programs always terminate)
              |
              v                 every instruction is a cpu_instr_item whose
        (sequencer -> driver)   CONSTRAINTS keep it legal (aligned LW/SW, valid CSRs ...)
                                + mcpu_mix_item: opcode mix 40/20/15/15/5/5 via dist  [NEW M07]
```

- **Files:** `module07/example01.sv` (constraint patterns, `dist`, `solve before`, switches), `example02.sv` (layered stream generator).
- **You learn:** legality vs scenario constraints, `:=` vs `:/`, why rare opcodes need `solve before`, seeds and replay.
- **The bench itself does not change** — only what feeds the sequencer. That is the power of UVM's separation of *what* from *how*.

---

## Module 08 — Functional coverage: knowing what was exercised

**New idea:** a second consumer of the **observation flow**: coverage.

```
   mcpu_retire_monitor --ap--+--> mcpu_scoreboard            (judges: right or wrong?)
                             |
                             '--> mcpu_instr_cov [NEW M08]   (measures: did this scenario happen?)
                                    covergroup cg
                                      cp_class  : R, ADDI, LW, SW, BEQ, CSRRW        (6 bins)
                                      cp_dist   : RAW hazard distance none,1,2,3      (4 bins)
                                      x_class_dist : cross                           (24 bins)
                                    sampled ONCE per retired instruction
```

- **Files:** `module08/example01.sv` (the coverage subscriber; Module 06's program gives 66.7 / 50.0 / 16.7 → 44.4%), `example02.sv` (closure loop: 44.4 → 70.8 → 77.8%).
- **You learn:** plan → covergroup, why we sample from monitors (not drivers), the coverage arithmetic, assertions vs coverage.

---

## Module 09 — Register layer (RAL): a second, separate bench for the CSRs

**New idea:** a *software model of the registers* with a mirror, and an adapter that turns register reads/writes into bus transactions. This is a **separate mini-bench** (the CSR port is not part of `mini_cpu_if`).

```
  CLASS WORLD                                                           STATIC WORLD
  mcpu_csr_test
   |
   |  register model [NEW M09]                       frontdoor
   |  mcpu_csr_block (uvm_reg_block)             +-------------------+   csr_req/we/addr/wdata
   |   |- mstatus  (mie, mpie)                   |  uvm_reg_map      |         +-------------+
   |   |- mtvec    (base, mode)   reg.write() -->|  + adapter        |-------->| mcpu_csr_   |
   |   |- mepc     (epc, zero)    reg.read()     |  mcpu_csr_adapter |  item   | driver      |
   |   '- mcause   (code, RO)                    +-------------------+         +------+------+
   |    desired value / MIRRORED value                  ^                             | pins
   |    (what the model thinks the DUT holds)           | bus2reg                     v
   |                                                    '------------------   mini_cpu_csr_if
   |   backdoor (zero-time peek via hierarchical path) ......................>  mini_cpu_csr_regs
   |                                                                            (CSR stub, bug switch)
   |   optional: monitor --> uvm_reg_predictor keeps the mirror right when others change registers
```

- **Files:** `module09/example01.sv` (the model and its API, no bus), `example02.sv` (frontdoor/backdoor + a bug-injected DUT caught by `mirror(UVM_CHECK)`).
- **You learn:** desired vs mirrored, access policies (RW/RO), frontdoor vs backdoor, adapter flags, why an undescribed bit can never fail.

---

## Module 10 — Integration: everything together, plus reset and bug-injection

**New idea:** the complete bench, a **base test**, **reset handling**, **negative tests** and a **regression** mindset. The DUT is now `mini_cpu_core`, which really executes instructions.

```
 STATIC WORLD                                    CLASS WORLD
 +--------------------------------------+     +------------------------------------------------------------+
 | tb_top  (clock, reset, +UVM_TESTNAME)|     | mcpu_env_base_test  -> mcpu_smoke_test / mcpu_reset_test   |
 |                                      |     |   owns: vif, cfg, factory override, run-phase timeout      |
 |  mcpu_rst_ctl_if [NEW M10]           |<====|   reset_test: settle -> request reset -> flush -> rerun    |
 |   (a test requests reset here)       |     |                          |                                 |
 |                                      |     |                      mcpu_env  (final)                      |
 |  mini_cpu_if  <-------pins------+    |     |   +------------------------------------------------+       |
 |                                 |    |     |   | ifetch_agent (seqr, driver, monitor)  [M04]    |       |
 |  mini_cpu_core  [NEW M10]       |    |     |   |    |  stimulus from sequences [M03, M07]       |       |
 |   executes the 9 instructions   |    |     |   |    '--ap--> scoreboard.fetch_imp               |       |
 |   +MCPU_BUG_ADD = seeded bug    |    |     |   | retire_mon  [M06] --ap--> scoreboard.retire_imp |       |
 +---------------------------------+----+     |   |                   '--ap--> cov (mcpu_instr_cov) |       |
                                              |   | scoreboard (mcpu_rst_scoreboard: flush())       |       |
                                              |   |   = ISS predictor + in-order compare [M06]      |       |
                                              |   +------------------------------------------------+       |
                                              +------------------------------------------------------------+
```

- **Files:** `module10/example01.sv` (the executing core and the reset-control interface), `example02.sv` (env, base test, smoke test, reset test, final `tb_top`).
- **You learn:** how a base test owns configuration and timeouts, the reset ordering rule, how a seeded DUT bug proves the checker can fail (errors at 135 ns and 195 ns), regression thinking, and the **capstone verification plan** with the 25 interview questions.

---

# PART D — The final picture, with every flow labelled

```
                                      +----------------------------+
                                      |  TEST (mcpu_*_test)        |   CONTROL FLOW
                                      |  chooses sequences, knobs, |   (config objects,
                                      |  overrides, reset, timeout |    factory, phases,
                                      +-------------+--------------+    objections)
                                                    |
         +------------------------------------------+------------------------------------------+
         |                                          |                                          |
         v                                          v                                          v
  +--------------+                         +----------------+                         +----------------+
  | GENERATOR    |   STIMULUS FLOW         |  AGENT          |   OBSERVATION FLOW      |  CHECKERS      |
  | sequences    | ----------------------> |  sequencer      | analysis ports          |  scoreboard    |
  | (M03, M07)   |  cpu_instr_item         |  driver         | ----------------------> |   + ISS (M06)  |
  +--------------+                         |  monitor        |  mcpu_bus_txn           |  coverage (M08)|
                                           +--------+-------+  mcpu_retire_txn        |  mirror (M09)  |
                                                    |                                  +----------------+
                                          pins (virtual interface)                              ^
                                                    v                                           |
                                           +-----------------+          retire monitor ---------+
                                           |  mini_cpu_core  |--------------- retire_* pins -----+
                                           |   (the DUT)     |
                                           +-----------------+
```

### The same story as a table: who plays which role?

| Role in the real system | Played in the testbench by |
|---|---|
| Instruction memory | `mcpu_ifetch_driver` (serves the words the sequences generated) |
| Program written by a programmer | sequences + `cpu_instr_item` (Modules 03 and 07) |
| Engineer watching the pins | monitors (`mcpu_ifetch_monitor`, `mcpu_retire_monitor`) |
| A known-good CPU to compare against | `mcpu_iss` inside `mcpu_scoreboard` |
| The referee | `mcpu_scoreboard` (`RETIRE_MISMATCH`, `PC_MISMATCH`, end-of-test checks) |
| The test plan tracker | `mcpu_instr_cov` (covergroups) |
| The spec of the control registers | `mcpu_csr_block` (register model) |
| The lab technician pressing reset | `mcpu_reset_test` + `mcpu_rst_ctl_if` |

---

# PART E — Follow one instruction all the way through

`ADD x3,x1,x2` in the program `ADDI x1,x0,5; ADDI x2,x0,7; ADD x3,x1,x2; SW x3,0(x4); LW x5,0(x4)`, as it passes through the Module 10 bench (times from the hand-derived trace):

```
 STEP  TIME   WHERE                      WHAT HAPPENS
 ----  -----  -------------------------  --------------------------------------------------------------
  1    t0     sequence                   mcpu_smoke_prog_seq calls send_instr(OP_ADD, rd=3, rs1=1, rs2=2)
  2    t0     cpu_instr_item             randomize() with every field pinned; encode() -> 0x002081b3
  3    t0     sequencer -> driver        finish_item hands it over; driver's get_next_item returns it
  4    115    driver                     CPU is requesting (if_req=1) -> drive if_rdata=0x002081b3, if_rvalid=1
  5    125    mini_cpu_core              samples if_rvalid: decode, read x1(5) and x2(7), ADD -> 12, write x3,
                                         lower if_req, set retire_* = (pc 8, instr, rd 3, data 12)
  5b   125    ifetch monitor             sees if_rvalid=1: publishes mcpu_bus_txn(addr 8, data 0x002081b3)
  6    125    scoreboard.write_fetch     checks addr 8 == ISS pc 8 ; ISS.step(0x002081b3) -> expected
                                         (pc 8, rd 3, data 12) queued;   coverage later decodes it too
  7    135    retire monitor             samples retire_valid=1: publishes mcpu_retire_txn(8, instr, 3, 12)
  8    135    scoreboard.write_retire    pairs it with the expected entry: equal -> match (n_cmp++)
  9    135    mcpu_instr_cov.write       class = R-type, nearest producer 1 back -> bins (R, d1) sampled
 10    185+   driver `item_done`         ... and the test's objection drops after the 5th instruction;
                                         50 ns drain lets the last retirement be compared; report at 235 ns
```

With the seeded bug (`+MCPU_BUG_ADD`) step 5 computes 13, step 8 finds `exp data=0x0c, act data=0x0d` and prints `RETIRE_MISMATCH` at **135 ns** — the whole point of the testbench in one line.

---

# PART F — Quick reference

### Which box appears in which module

| Box / class | Introduced in | Real file |
|---|---|---|
| `tb_top`, `mini_cpu_if`, `mini_cpu` (stub), `mcpu_base_test` | 01 | `module01/example01.sv` |
| env tree shells, phases, factory overrides | 02 | `module02/example01.sv`, `example02.sv` |
| `cpu_instr_item`, sequences, `mcpu_vseqr`, virtual sequence | 03 | `module03/example01.sv`, `example02.sv` |
| `mcpu_agent_cfg`, `mcpu_ifetch_driver/monitor/agent`, `mcpu_bus_txn` | 04 | `module04/example01.sv` |
| `config_db` use, analysis ports/imps/FIFOs | 05 | `module05/example01.sv`, `example02.sv` |
| `mcpu_retire_txn`, `mcpu_iss`, `mcpu_scoreboard`, `mcpu_retire_monitor` | 06 | `module06/example01.sv`, `example02.sv` |
| `mcpu_mix_item`, burst/scenario sequences | 07 | `module07/example01.sv`, `example02.sv` |
| `mcpu_instr_cov` (covergroups) | 08 | `module08/example01.sv` |
| register model, adapter, `mini_cpu_csr_if`, CSR stub | 09 | `module09/example01.sv`, `example02.sv` |
| `mini_cpu_core`, `mcpu_env`, base test, reset test | 10 | `module10/example01.sv`, `example02.sv` |

### Five facts worth memorising

1. **The CPU is the master;** the testbench plays memory and answers its requests.
2. **Retirement is the checking point:** `retire_pc/instr/rd/data` is compared with a software reference model.
3. **Stimulus flows down, observation flows up, control flows sideways.**
4. **Drivers drive, monitors only watch, scoreboards judge, coverage measures** — four different jobs, four different classes.
5. **Silence is not success:** most UVM mistakes (missing connection, missing `set`, no objection) produce *no error at all*, which is why the course keeps asking you to count, print and prove your checkers can fail.
