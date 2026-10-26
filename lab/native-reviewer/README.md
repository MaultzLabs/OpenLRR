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

`python3 lab/native-reviewer/review.py` produces an offline packet from five
allowlisted files (with line-numbered view excerpts) at the exact HEAD commit. It does not use an API key. No WADs,
audio, saves, private recordings, environment values or uncommitted files are
included. `python3 -m unittest discover -s lab/native-reviewer/tests -v` uses
synthetic API responses only.

The existing GitHub Actions workflow is manual-only. The default `run_model=false`
prepares the packet without spending. Setting `run_model=true` explicitly
requests ONE billable Responses API call using the existing `OPENLRR_AI_LAB_KEY`
secret and the existing bot model, `gpt-6-luna`. Model access is not verified.
Input is bounded to 60,000 UTF-8 bytes before request encoding; generated output
is capped at 6,000 tokens, with low reasoning effort. These are usage limits, **not a dollar or prepaid-balance
guarantee**. No retries, tools, auto-applied patches, schedules, Windows builds,
new credit purchases or billing changes. A manually rerun job can spend again.
Timeouts may still have consumed credits; they are never retried automatically.

On October 26, Max authorized using API funds where it materially helps the
port. One gameplay review is authorized for evaluation. The temporary
`lab-native-review-once.yml` requires an exact one-shot commit message and
first run attempt; its only push trigger is a change to its own workflow file.
Remove it after the attempt. No recurring paid task is authorized by this setup.
Remaining prepaid credit and account charging settings are still unverified.

API reference: https://developers.openai.com/api/reference/typescript/resources/responses/methods/create
The response's status and token usage are recorded alongside its review. An
incomplete response is not promoted to a successful validation result. I will
inspect findings and implement justified fixes in the native branch before CI.

Attempt A (run 40267087764) returned incomplete: 26,456 input tokens,
2,000 reasoning/output tokens, no text and no usable finding. Attempt B narrows
the packet to movement/drilling cancellation, requests low reasoning effort,
and reserves 6,000 output tokens. A response without completed status and text
now fails the job after preserving usage rather than appearing successful.
