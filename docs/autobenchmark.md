# Unattended OpenLRR menu benchmark — experimental MVP

**Status:** Windows compilation and real Mac runtime test must both pass before considering the harness validated.

This branch implements the first step toward automated debugging. It does **not** currently run a self-modifying AI agent. It avoids manually choosing the graphics mode and waiting at the menu, automates a time-limited session, and collects comparable DirectDraw performance metrics.

## Architecture

1. A special, otherwise ordinary OpenLRR DLL enables automation only when \`menuperf.autotest\` is present in the current Wine working directory. Its contents specify test duration in seconds (default 210, accepted range 15..600).
2. The flag instructs OpenLRR's existing Init selection path to choose the best available hardware device in a window, bypassing the modal Mode Selection dialog. This selection is **not guaranteed to be identical** to a user-selected configuration; inspect it in the first real run.
3. Along with \`menuperf.enable\`, game code measures each DirectDraw frame and logs the same \`menuperf.csv\` metrics previously collected by hand. The timed interval begins on its first completed frame, not at the process launch.
4. After the interval, a \`WM_CLOSE\` is posted to the game window. A \`menuperf.finished\` file means the window close request was posted, **not that the game successfully exited**.
5. The Mac runner waits for this marker, archives the performance log and a short comparison-friendly report, and restores the prior DLL and marker state in the duplicated **OpenLRR Menu Test.app**. It will not kill unrelated Wine processes.

## First-time workflow

- Finish/quit any ongoing manual A/B tests.
- Download the successful GitHub Actions artifact for the \`automated-benchmark-harness\` branch. Save it to Downloads as \`OpenLRR-autobenchmark-x86.zip\`, with \`openlrr.dll\` at the ZIP root.
- Save \`scripts/macos/run-autobenchmark.sh\` into \`~/Downloads/run-autobenchmark.sh\`.
- Run \`bash "$HOME/Downloads/run-autobenchmark.sh"\`.
- The log/report are saved under \`~/Downloads/OpenLRR Benchmark Runs/autobenchmark-<timestamp>/\`.
- Optional: \`OPENLRR_BENCH_SECONDS=300 bash "$HOME/Downloads/run-autobenchmark.sh"\` to include more menu activity in the session.
- The runner refuses to start if \`menuperf.gdi\`, \`menuperf.nowait\`, \`menuperf.optimize\` or an existing \`menuperf.autotest\` marker is present, to avoid mixing incompatible experiments.

## What it can and cannot validate

- Useful: no manual clicking of the startup graphics selector, bounded startup and rendering capture, automatic log archive, consistent per-call timing summary, preserving the working installation.
- **Not yet validated on the user's Wine wrapper**; GitHub compilation is not a test of Sikarugir or Apple Silicon graphics.
- Still slower than a synthetic microbenchmark because it deliberately uses **real game initialization and rendering**. At present a 210-second sample can take >3 minutes.
- If the app never reaches its first rendered frame, or the close request never happens, the runner times out and reports the failure. The runner does not kill processes or pretend the benchmark completed.
- No automatic screenshot analysis, game-state/menu phase labeling, deterministic rendering assertions, continuous background agent, model code edits, or cloud ingestion in this first version.
- The test uses the **existing underlying graphics pipeline** and does not fix the ~1.25-second DirectDraw stalls; it provides automation and better evidence to inform a later fix.

## Future milestones

1. Verify one unattended run on the actual M4 Pro test app and validate that expected 640×480 windowed hardware mode is selected.
2. Add deterministic short, isolated microbenchmarks of \`Blt\`, surface \`GetDC\`, lock/unlock and surface creation to compare compat layers in seconds instead of minutes, with explicit phase labels in the CSV.
3. Add automatic baseline-vs-candidate comparisons and fail/success thresholds.
4. Create a secure, isolated on-device runner that only executes reviewed, signed/approved builds, has bounded test time, and uploads sanitized results to a private repository. Do not allow arbitrary public GitHub workflow code to execute on the personal Mac.
5. Add AI-assisted change suggestions, rebuild/test repetitions and human-approved promotion to the working game.

All automated code modifications and performance experiments should be restricted to a separate test branch and test app. Never overwrite the known-good wrapper.

## Automatic, private GitHub results submission

The Mac runner can now optionally upload a **strictly selected** performance CSV and its small generated report to a **private** GitHub repository after each local run. It does not upload the user's home folder, game assets, executable, Wine registry or other data.

### One-time setup on the Mac (user-authorized)

1. Install GitHub CLI, if necessary: `brew install gh`. Log in using `gh auth login`, choosing GitHub.com and browser authorization. Credentials remain in GitHub CLI's local store, not in this repo or in ChatGPT.
2. Create a **private** results repository, preferably `MaultzLabs/OpenLRR-Test-Results`, using the GitHub website or:
   `gh repo create MaultzLabs/OpenLRR-Test-Results --private --add-readme`
3. Configure its name once, WITHOUT storing tokens:

```bash
mkdir -p "$HOME/.config/openlrr-benchmark"
printf '%s\n' 'MaultzLabs/OpenLRR-Test-Results' > "$HOME/.config/openlrr-benchmark/private-results-repo"
```

4. Give the ChatGPT GitHub connector access to that private results repository if you want its contents to be visible in later GitHub-connected conversations. This may require changing the GitHub App installation's repository permissions in GitHub. Grant only that repository, not all private repos.

The benchmark runner reads ONLY the repository name from this config file. It invokes `publish-benchmark.sh` only if configured and a CSV was generated. The publisher verifies `gh` authentication, checks the target is actually **PRIVATE**, checks the CSV schema and 2MB limit, and publishes only `menuperf.csv` and the small summary `report.txt`. Any upload failure is non-fatal; the local files remain available and the prior test DLL is restored.

Results become available at `https://github.com/MaultzLabs/OpenLRR-Test-Results/tree/main/runs/` under unique timestamp-named subdirectories. Each file is committed separately through the GitHub API, and each run has its own directory; partial uploads may occur if connection fails. Do not grant the uploader write access to the public OpenLRR code repo to store logs.

**Important:** This is automatic **upload**, not a self-running agent. It will not independently wake this ChatGPT conversation or cause the assistant to modify code without a separate authorized CI / OpenAI API agent. Mac Wine graphics must still be run on the real M4 Pro for a meaningful performance verdict.

## Acceptance goals (technical quality gates, subject to real user validation)

- Cold launch until first interactive title menu: **target under 5 seconds**, compared to current ~120 seconds; log time to first frame and menu-interactive milestone separately in a subsequent instrumented build.
- Main menu input latency: **target below 100 milliseconds**. Avoid the repeatable ~1250ms DirectDraw stalls.
- Menu rendering: no repeated >100ms frame hitches under normal usage; animations visually and functionally match stock at chosen quality.
- Gameplay: no unacceptable performance regression compared with current ~213 FPS baseline on identical mission, wrapper and graphics settings; preserve resolution/effects.
- No crashes, black frames, corrupted colors, broken input, or disabled features. Verify visually on actual machine before promoting any patch.

Long term: instrument one subsystem at a time, classify each test phase, create short synthetic graphics probes, use repeatable baselines and regression checks, then integrate reviewed AI-assisted patch recommendations. We are adapting the open-source OpenLRR reconstruction of the classic game; testing does not automatically recover the complete original proprietary source code.
