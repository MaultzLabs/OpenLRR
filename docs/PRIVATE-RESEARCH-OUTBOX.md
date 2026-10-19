# Verified private research outbox

After an explicit source-code A/B run has safely completed inside the isolated
OpenLRR Menu Test app, the lab policy can produce a read-only research ticket
for a negative or inconclusive result. The ticket does **not** authorize
another DLL run or an AI model request.

When the already-existing paired DLL evaluator is invoked with
`--publish-evidence`, it now follows this ordering:

1. Verify original A/B lifecycle receipts, binaries, graphics modes, and tests.
2. Commit the deterministic controller decision to the local locked ledger.
3. Create an inert research ticket if the decision is genuinely
   `ready_for_new_research`.
4. Publish the reviewed A/B experiment to the private results repo **only
   after verifying every run's private upload and lifecycle receipt**.
5. Publish the inert research ticket into the private repo's
   `research-tickets/` directory using
   `scripts/agent/publish_research_ticket.py`.

If any private publication fails, the local verified benchmark remains
available for retry; the failure does not imply the test game is still open.
Existing remote ticket blobs are accepted only if byte-for-byte identical.
No overwriting, deployment, automatic model invocation, game execution or
new source-code patches happen during publication.

Standalone ticket upload is explicit:
```bash
python scripts/agent/publish_research_ticket.py \
  --ticket /path/to/research-ticket.json \
  --decision /path/to/decision.json \
  --ledger /path/to/research-controller.json \
  --manifest /path/to/reviewed-experiment.json \
  --runs-dir /path/to/verified-runs \
  --publish
```

Omit `--publish` for a dry-run with no network access.

This step **does not** make cloud research autonomous yet. A future cloud
dispatcher must obtain private repository access, authenticate and validate
ticket origins and independently enforce usage costs. Tickets are not digital
signatures, trusted shell instructions, execution authorizations, or statements
of proven visual FPS.
