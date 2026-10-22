# Windows virtual playtesting lab (experimental)

**Purpose:** Automate the ORIGINAL Windows LEGO Rock Raiders/OpenLRR application, not claim that the native macOS port is complete. This work is isolated from the Mac/Wine working game.

## What exists

- A Python Windows controller launches a local Windows EXE, or attaches to a specified PID. It matches an exact owning PID plus a configurable window-title regex and refuses ambiguous windows.
- The controller can capture **only that window**, send actual client-relative mouse clicks and whitelisted game keys, and run bounded scenario steps.
- PNG frames, per-step timestamps, visual-change measurements and a JSON pass/fail report are stored locally. A click alone is never proof of successful gameplay.
- A synthetic Windows Forms test window verifies the automation mechanism in public GitHub Actions. **It is not the original game.**
- The real-game starter scenario only launches the installed executable, captures its window and checks that it remains alive. It does not yet automate menu navigation or prove gameplay or 60 FPS.
- Public workflows never bundle the original game's WADs, extracted assets or proprietary captures. The private-game job is conditional on a separately provisioned self-hosted Windows GUI runner; none has yet been provisioned as part of this work.
- Window capture depends on Pillow 11.2+ PrintWindow. Old DirectDraw/Direct3D renderers can produce blank frames under PrintWindow; that remains a compatibility question.

## Portable tests

Run from repository root:

    python3 -m unittest discover -s lab/windows-playtest/tests -v

Public CI workflow: .github/workflows/lab-windows-playtest.yml.
Linux runs pure scenario validation. GitHub-hosted Windows attempts to launch and drive a synthetic WinForms fixture. Some hosted runners may lack a usable interactive desktop: a failure or absent screenshot is an actual unresolved result, not proof that the game works.

## Real game on a Windows virtual machine

Use a dedicated Windows 10/11 VM with an unlocked interactive user desktop, a working graphics device, Python 3.11+, and a private locally installed, legally obtained copy of Rock Raiders / OpenLRR with its original game files. An Actions runner operating as a background Windows service/session 0 does not provide the interactive input desktop the test needs.

Install capture dependency:

    py -m pip install "Pillow>=11.2,<12"

Then, after checking out branch lab-windows-virtual-playtest-v1, from repo root:

    py lab\windows-playtest\playtest.py --exe "C:\Games\Rock Raiders\OpenLRR.exe" --title "Rock Raiders|OpenLRR" --scenario lab\windows-playtest\game-smoke.json --out "C:\OpenLRR-Private-Reports\smoke-001"

Substitute the actual local EXE path. Adjust the title regex if needed, but keep the ownership check.

To test an already running game, replace --exe with --pid and its numeric process ID. Attaching never terminates the existing process; launching a new EXE terminates that test instance when finished.

A real-game workflow job is defined for Windows machines registered with these runner labels: self-hosted, Windows, X64, openlrr-gui. Define OPENLRR_GAME_EXE privately on that runner. The job will not run on normal GitHub-hosted Windows, and will not upload real-game screenshots to the public repository. Workflow dispatch requires the workflow to be available on the default branch before it can be used from the GitHub UI.

## Bounded JSON scenario actions

Each scenario has 1-40 steps and a 180-second execution budget:

- capture: window PNG
- click: x,y in *target game client* pixels, not screen pixels
- key: enter, escape, space, up/down/left/right
- wait: up to 10 seconds
- assert_title: regex against target window title
- assert_changed: measured mean pixel difference from prior frame
- assert_alive: verify that the original HWND still belongs to the original PID

No arbitrary commands, game binaries or network access are accepted from a scenario.

## Next engineering gates

1. Verify that the hosted Windows synthetic fixture actually launches, gets clicked, and captures an image.
2. Provision an interactive Windows VM with legitimate local game files and confirmed legacy graphics compatibility.
3. Verify an authentic game launch, window capture and actual menu action.
4. Expand into deterministic menu/mission interaction and instrument real frame presentation, with a clear distinction between input automation and autonomous strategic gameplay.

**Status:** infrastructure/prototype only. No successful original Windows gameplay run has been demonstrated in this lab.
