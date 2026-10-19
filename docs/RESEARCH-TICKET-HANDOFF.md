# Research ticket handoff (data only)

This stage connects a genuine, already-verified controller research decision to
an on-disk *inert ticket*. It does **not** launch AI, dispatch GitHub Actions,
compile a DLL, install anything or start Wine.

## Preconditions

The local supervisor completes an explicitly allowed paired test and verifies
both result uploads, exit receipts, graphics modes and DLL identity. The
controller recomputes A/B evidence and stores a unique decision under its
existing locked ledger. Only decisions with disposition
`ready_for_new_research` and `ledger_committed=true` can produce a ticket.

The new `scripts/agent/research_ticket.py` checks that the decision
fingerprint, experiment ID, UTC day and research action all agree with a single
ledger event. It rejects review holds, repeats, incomplete evidence,
contradictory authority flags, and existing output paths. A ticket contains
only a bounded next-step category, fingerprint, and vetted policy explanation.

`lab-supervisor.py --coordinate` creates the ticket only after both
verified runs are finished. The ticket lives in the local experiment folder
next to the corresponding controller decision.

## Explicitly not authorized

Every generated ticket contains the following false flags:

- approved_to_invoke_model
- approved_to_dispatch_cloud_workflow
- approved_to_compile
- approved_to_execute_game
- approved_to_deploy

It also includes requires_separate_budget_and_dispatch_review=true.

A later dispatcher must impose real token/cost limits and actual workflow
authorization at its own boundary. The current controller's three-requests-per-
UTC-day rule is a research planning throttle, **not** a guarantee of dollar
spending limits. Local JSON/ledger content is not a digital signature and
cannot substitute for authenticated execution approval.

No new source changes to the actual game are made by this feature.
