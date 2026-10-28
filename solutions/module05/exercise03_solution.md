# Module 05 / Exercise 03 — Solution (one reference design)

## 1. Connectivity diagram

```
 fetch agent                 lsu agent                  retire monitor (in env)
 mon.ap  -> agent.ap          mon.ap -> agent.ap          ap
     |                             |                        |
     +--------------+--------------+------------------------+
                    | (each producer port fans out to several subscribers)
                    v
   fetch ap ----> scoreboard.fetch_imp   (uvm_analysis_imp_fetch,  write_fetch)    [predictor input]
   retire ap ---> scoreboard.retire_imp  (uvm_analysis_imp_retire, write_retire)   [compare input]
   lsu ap -----> scoreboard.lsu_imp      (uvm_analysis_imp_lsu,    write_lsu)      [load/store checks]
   fetch ap ----> coverage.analysis_export   (uvm_subscriber for instruction coverage)
   lsu ap -----> coverage_lsu.analysis_export (uvm_subscriber, or one subscriber with imp_decl)
```

`agent.ap` is the boundary: each agent forwards its monitor's port (`mon.ap.connect(ap)`, Module 04), so the env connects to `agent.ap` without knowing what is inside.

## 2. Justification

| Consumer | Mechanism | Reason |
|---|---|---|
| Scoreboard (3 inputs) | `uvm_analysis_imp_decl(_fetch)`, `(_retire)`, `(_lsu)` | one class needs several differently typed/named `write` methods; each `write_*` just pushes to a queue or runs the predictor — non-blocking |
| Coverage subscribers | `uvm_subscriber#(T)` (imp inside) | each sample is instantaneous; coverage `sample()` is a function |
| A slow or blocking consumer (e.g. a trace writer to a file with long formatting) | `uvm_tlm_analysis_fifo` + own thread | decouples pacing; the producer never waits |

## 3. Ordering and timing

- Subscribers of the same port are called in an **unspecified order**: the scoreboard and coverage must not depend on each other's callbacks.
- The fetch and retire streams are independent in time: normally fetch precedes retire (the pipeline), but in the same simulation time step either `write_*` may run first. The scoreboard must buffer both and compare when it has both (Module 06's two-queue pattern) rather than assume "expected arrived before actual".
- A `write` runs in the **producer's** thread: it must be fast and non-blocking; never wait for another stream inside a `write`.

## 4. Connect-phase code

```systemverilog
function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  ifetch_agent.ap.connect(sb.fetch_imp);
  ifetch_agent.ap.connect(cov_fetch.analysis_export);
  lsu_agent.ap.connect(sb.lsu_imp);
  lsu_agent.ap.connect(cov_lsu.analysis_export);
  retire_mon.ap.connect(sb.retire_imp);
endfunction
```

A new trace logger is added with one more `connect` line in the env; no monitor or agent changes.

## 5. Failure modes and checks

| Silent failure | Why silent | Check |
|---|---|---|
| A `connect` line missing or in a typo'd phase method | analysis ports may have 0 subscribers | `end_of_elaboration_phase` assertion that every monitor port has `size() > 0`; log in `connect_phase` |
| Scoreboard sees fetches but never retires (retire monitor not connected, or a monitor sampling the wrong signal) | the compare simply never runs | `check_phase`: error if `n_compared == 0`, or if fetched ≫ retired by more than the pipeline depth |
| Wrong `imp` flavour (e.g. two inputs sharing one `write`) | wrong data flows into wrong queue | distinct `imp_decl` suffixes and typed arguments; compile-time errors catch most |

## Self-review checklist

- [x] Every producer port has at least one named consumer; every consumer input has a producer.
- [x] Imp vs FIFO choices justified by timing/blocking.
- [x] Order-independence of subscribers stated.
- [x] Both monitors are non-blocking (analysis `write` only).
- [x] Silent-failure checks listed.

## Expected log

Not applicable (design exercise).

## The result that matters

The decisions are: **who needs the data immediately (imp), who needs to pace themselves (FIFO), and which class needs several inputs (imp_decl)** — and the dangerous property of this style is that miswiring looks like a quiet testbench. Variation to try: add a bounded `uvm_tlm_fifo` between the retire monitor and the scoreboard with a blocking `put` and explain why that would be a mistake for a monitor.
