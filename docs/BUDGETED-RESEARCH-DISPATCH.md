# Bounded one-call model research dispatcher

The cloud research workflow now has a separate authority boundary:

1. The private ticket reader reconstructs the original supervised Mac A/B
   evidence and independently verifies its exact controller fingerprint.
2. Only a nonreviewer `new_hypothesis`, `improve_instrumentation`, or
   `isolate_regression` result can proceed.
3. Model execution is **off** unless all are true:
   - The user deliberately dispatches the workflow with an exact ticket ID.
   - The repository variable `OPENLRR_RESEARCH_EXECUTION_ENABLED` is
     explicitly `true`.
   - A separate `OPENLRR_RESULTS_WRITE_TOKEN` secret can write to the
     **private results repo** (the default source repo token is insufficient).
   - An `OPENLRR_AI_LAB_KEY` model key is configured.
   - GitHub accepts exclusive, immutable reservations for both the UTC day
     and the particular ticket.
4. Only after both private reservations are acknowledged does the lab make
   **one tool-free structured research call**, with `max_turns=1`.
5. It uploads a *research plan for review*, never a DLL or code patch.

The first reservation uses a shared UTC-day path in the private repo,
`research-dispatches/daily_YYYYMMDD.json`. GitHub file creation is atomic
without a previous blob SHA, meaning two different calls racing for the same
day cannot both claim it. The second is permanent for that exact ticket:
`research-dispatches/ticket_research_<24hex>.json`.

This limits the laboratory to **at most one reserved model attempt per UTC
day**, and no repeat of the same ticket. If a GitHub/model failure occurs
after reservation, the slot is consumed. Retries do not silently spend again.
A failed private write blocks the model call.

**Important billing limitation:** one model call is not a fixed-dollar cost
ceiling. API pricing and the model's internal token usage still apply. This
scheme restricts frequency but does not estimate or guarantee USD spending.
API account-level hard budgets should independently enforce any monetary
ceiling. The research model has no tools and receives only independently
verified categorical outcomes, not private raw Mac logs.

Usage, offline/no-network:

```bash
python scripts/agent/budgeted_research_dispatch.py \
  --ticket-id research_aaaaaaaaaaaaaaaaaaaaaaaa
```

A manually dispatched workflow can perform an actual paid request, but until
the separate private write token and opt-in variable are configured, the
workflow fails closed or skips the job.

The resulting plan cannot approve candidate execution, change the user's
working installation or assert that the game actually looks smooth. All
compiled patches still require isolated execution and verified visual QA.
