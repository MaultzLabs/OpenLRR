# OpenLRR privacy-hardened one-run Wine sampler

## Existing evidence
Mac TEST `2026-10-19_20-59`: exactly one `wine_related` and one
`isolated_test_wrapper` held writable handles on verified TEST
`menuperf.csv`. The earlier profiler refused multiple owners. The newer
candidate selects **only the unique Wine owner** when the other owner(s)
are exclusively the isolated TEST wrapper, never the wrapper itself.
Zero Wine, multiple Wine, unrecognized, or two+ LegoRR owners still fail
closed. PID and native CPU trace remain local; only bounded anonymous
categories may be reported.

## Next Mac run
`menu-diagnostic-session.py --session 3` is a new **one baseline**
Mac TEST plan (not two) with one optional 3-second native CPU sample
during repeated known menu stalls. It runs the pinned known reviewed
baseline diagnostic DLL only. No gameplay, graphics or wrapper changes.
The script defaults to dry run without `--run`.

## Upload hardening
CI artifact includes a new `privacy-validate-benchmark.py`; the uploader
fails before any GitHub write unless all proposed telemetry is validated:
CSV fixed eight-column numeric-only schema + fixed operation vocabulary,
JSON bounded keys, allowed presentation modes, finite numbers, exact run
identity, SHA-256 identity, fixed supervised exit receipt. Unsupported
strings/paths/URLs/secrets fail closed. No `report.txt` is uploaded
on new runs (free-form report remains on Mac). Existing private
reports are not deleted. The already-existing upload mechanism
checks private visibility each time.

The supervisor's verification will still check private CSV,
summary and lifecycle. Explicit `OPENLRR_REPORT_REPO` must point to the
same established private repository.

## Public commit email privacy
GitHub/Git author email settings cannot be changed using this repo code.
The owner must enable **Keep my email addresses private** and
**Block command line pushes that expose my email** in GitHub Settings > Emails;
set local Git author email to their exact account-specific noreply address.
Existing public commits still retain historic metadata unless history is
rewritten, which is out of scope.
