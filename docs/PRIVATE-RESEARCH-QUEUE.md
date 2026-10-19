# Autonomous private research queue discovery (gated, one model request/day)

The private results repository now has non-executable directories
`research-tickets/` and `research-dispatches/`. There are no fabricated
research requests, test results or approvals.

`scripts/agent/private_research_queue.py` reads the two private GitHub
directory listings, validates every entry's type/path/name, ignores claim
markers, and chooses one pending ticket deterministically. It **never**
executes a model or an executable and does not interpret ticket contents as
instructions.

The budgeted research workflow now supports leaving its manual ticket ID
blank. It can then pick the next pending item. A once-daily schedule is also
present in the **lab workflow source**, but it cannot become an active
scheduled workflow until explicitly installed on the repository's default
branch and the independent opt-in variable has been configured.

Any real request additionally must pass the original research intake's
full A/B revalidation, then acquire an immutable UTC-day and per-ticket
private reservation, then use a tool-free single-turn model. Unknown or
unverifiable tickets cause a failure **before any model expense**. A day
without pending work makes no paid request.

The dispatcher now feeds its AI research prompt only deterministic
numeric evidence from the independent gate: paired-run count, median
presentation-time change, bootstrap uncertainty, and changes to the logical
frame-throughput proxy. Free-form private run logs or ticket instructions
cannot be injected into the model context.

For local offline no-network confirmation:

```bash
python3 scripts/agent/private_research_queue.py
python3 scripts/agent/budgeted_research_dispatch.py \
  --ticket-id research_aaaaaaaaaaaaaaaaaaaaaaaa
```

Without the separately granted private write token, AI key and explicit
`OPENLRR_RESEARCH_EXECUTION_ENABLED=true`, the paid job remains disabled.
The previous laboratory model workflows must still be reviewed separately:
a variable that enables an older scheduled workflow does not automatically
inherit this per-day gate.

No real game repair or improvement to displayed FPS is established by this
queueing milestone. Mac sandbox execution, continuous visual QA, and a review
step before binary execution remain separate dependencies.
