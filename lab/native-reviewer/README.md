# Native gameplay assignment for the existing API bot

The old `lab-ai-proposal.yml` checked out a fixed October 18 Wine revision and
only allowed edits inside one DirectDraw presentation block. This isolated
native branch repurposes that workflow to review current native gameplay.
Main's Wine workflow is unchanged.

Current assignment: identify up to four reproducible defects in excavation,
continuous movement cancellation, original-material preservation, first-person
navigation and NERPs UI wiring. Each finding must include an exact source
location, trigger, minimal fix and regression test. Known unported features
are excluded. The returned review is evidence to inspect, not proof of a bug.

`python3 lab/native-reviewer/review.py` produces an offline packet from eight
allowlisted files at the exact HEAD commit. It does not use an API key. No WADs,
audio, saves, private recordings, environment values or uncommitted files are
included. `python3 -m unittest discover -s lab/native-reviewer/tests -v` uses
synthetic API responses only.

The existing GitHub Actions workflow is manual-only. The default `run_model=false`
prepares the packet without spending. Setting `run_model=true` explicitly
requests ONE billable Responses API call using the existing `OPENLRR_AI_LAB_KEY`
secret and the existing bot model, `gpt-6-luna`. Model access is not verified.
Input is bounded to 140,000 UTF-8 bytes before request encoding; generated output
is capped at 2,000 tokens. These are usage limits, **not a dollar or prepaid-balance
guarantee**. No retries, tools, auto-applied patches, schedules, Windows builds,
new credit purchases or billing changes. A manually rerun job can spend again.
Timeouts may still have consumed credits; they are never retried automatically.

Prior user instruction forbids charges. No billable request has been made by
this change. Remaining prepaid credit and account charging settings cannot be
verified through the GitHub connector. Resolve that spending constraint before
turning on `run_model`.

API reference: https://developers.openai.com/api/reference/typescript/resources/responses/methods/create
The response's status and token usage are recorded alongside its review. An
incomplete response is not promoted to a successful validation result. I will
inspect findings and implement justified fixes in the native branch before CI.
