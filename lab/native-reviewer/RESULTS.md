# Paid bot trial — October 26, 2026

Max authorized spending when it would significantly accelerate the native port.
The bot was redirected from its old Wine-only DirectDraw task to current native
movement/drilling review. Only two calls were made; no recurring paid task or
billing settings were enabled.

| Attempt | Result | Input tokens | Output tokens | Reasoning tokens included in output |
| --- | --- | ---: | ---: | ---: |
| [A](https://github.com/MaultzLabs/OpenLRR/actions/runs/40267087764) | Incomplete; empty review | 26,456 | 2,000 | 2,000 |
| [B](https://github.com/MaultzLabs/OpenLRR/actions/runs/40267354497) | Completed; NO_FINDINGS | 9,474 | 1,003 | 954 |

Total reported usage: 35,930 input + 3,003 output = 38,933 tokens. This is not
a dollar cost statement; remaining balance and billed cost were not available.

Attempt B used narrower line-numbered source excerpts, low reasoning effort,
and a 6,000-token output ceiling. It found no defensible defect without making
assumptions about omitted functions or SceneKit callback ordering. This is
not proof of correct gameplay. No model-authored code was applied, and no
measurable development speedup was demonstrated by the review trial.

The one-shot push workflow has been removed. The existing manual workflow
remains available with offline preparation as its default. Future paid work
should target a specific implementation or reproducible failure with a clear
acceptance test, and be evaluated by accepted fixes/tests rather than calls.

Separately, native game commit 4e2cf87 passed portable Swift tests and Mac ARM64
compilation: https://github.com/MaultzLabs/OpenLRR/actions/runs/40266326851
Real-asset gameplay and audible mission music remain unverified on a Mac.
