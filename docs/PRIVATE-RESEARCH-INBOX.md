# Private research inbox: independently revalidate cloud requests

`scripts/agent/private_research_inbox.py` is the opposite end of the
local `publish_research_ticket.py` flow. Its goal is to prevent a private
repository record from silently becoming an authorized instruction.

It accepts an exact `research_<24 lowercase hexadecimal digits>` selector.
By default it does **no network access**. With the explicit
`--verify-private` flag, a separately authenticated read-only GitHub CLI
connection retrieves ONLY:

1. The exact research ticket under `research-tickets/`.
2. The corresponding immutable experiment under `experiments/`.
3. Every declared baseline and candidate run's exit receipt, summary
   and menu-performance CSV under `runs/`.

Each response is constrained to the private `MaultzLabs/OpenLRR-Test-Results`
repository and the `main` ref. It checks the Git blob hash, base64, sizes,
file type, exact expected path, and a total evidence transfer cap. It then
re-runs the actual `remote_evidence_gate` policy from those files.

The verifier recomputes the exact controller evidence fingerprint, compares
the policy's next action and bounded reason against the ticket, and
rejects mismatches. A research ticket derived from reviewer feedback is
currently refused until authenticated reviewer-origin data can also be
verified on the cloud side.

Example dry run (no GH access):

```bash
python3 scripts/agent/private_research_inbox.py \
  --ticket-id research_aaaaaaaaaaaaaaaaaaaaaaaa
```

With *separately configured* private read-only access:

```bash
python3 scripts/agent/private_research_inbox.py \
  --ticket-id research_<exact_24_hex_digit_identifier> \
  --verify-private --out /path/to/unique-verified-intake.json
```

The workflow `.github/workflows/lab-private-research-intake.yml` contains
fully offline tests and a manually invoked verification job. Its private
job requires `OPENLRR_RESULTS_READ_TOKEN` (a separately granted minimum
read-only secret). Without that secret, it stops; it does not fall back to
the regular CI write token or request credentials from a model.

**No AI calls, auto dispatch, binaries, Wine runs, code edits, app launches,
deployment, or source merges** occur during intake. The output is a
non-executable, sanitized JSON verification report.

Known limits: private repository access does not prove the game was visible
on the screen, nor that every uploaded local receipt has hardware attestation.
A digest of statistically derived evidence is not a digital signature.
Real billing enforcement and any model dispatch must remain a separate,
reviewed trust boundary.
