# OpenLRR AI Laboratory — Stage 1: OpenAI observer

This is an OpenAI Agents SDK **read-only** observer, not a continuously coding or
unattended Mac test agent. It polls existing private GitHub benchmark summaries,
then asks an OpenAI model to assess a newly completed pair. It cannot edit
source, invoke GitHub Actions, build DLLs, start Wine, deploy patches, or send
messages into this ChatGPT conversation.

Source SDK: https://openai.github.io/openai-agents-python/quickstart/
Private telemetry: https://github.com/MaultzLabs/OpenLRR-Test-Results

## One-time Mac setup

Run in Terminal:

    brew install python@3.12
    git clone --branch agent-loop-v1 https://github.com/MaultzLabs/OpenLRR.git "$HOME/OpenLRR-Agent"
    mkdir -p "$HOME/.local/share/openlrr-agent"
    /opt/homebrew/bin/python3.12 -m venv "$HOME/.local/share/openlrr-agent/venv"
    "$HOME/.local/share/openlrr-agent/venv/bin/python" -m pip install --upgrade openai-agents
    gh auth status

If the local source checkout already exists, do not blindly clone over it.
Never copy your real game, Sikarugir prefix or private assets into the repo.

## Inspect the measurements without spending money

    "$HOME/.local/share/openlrr-agent/venv/bin/python" \
      "$HOME/OpenLRR-Agent/scripts/agent/openlrr_agent.py" --once --dry-run

This calls only your connected GitHub account. It prints numeric measurements,
test mode flags, timestamp-shaped run names and DLL SHA256 fingerprints; no
OpenAI request is sent.

## API key and cost limits

A ChatGPT subscription does not include API usage. Create a separately billed
project API key at https://platform.openai.com/api-keys and configure an
organization/project HARD spending limit. Avoid saving your key in source files
or pasting it into ChatGPT.

In macOS default zsh Terminal, enter the key interactively without echoing it:

    printf 'Paste API key (hidden): '
    read -s OPENAI_API_KEY
    printf '\n'
    export OPENAI_API_KEY

The default model is gpt-6.1-sol; set --model gpt-6-luna for a less expensive
focused analyst. Model access and billing depend on your Platform project.

## Run the agent once

    "$HOME/.local/share/openlrr-agent/venv/bin/python" \
      "$HOME/OpenLRR-Agent/scripts/agent/openlrr_agent.py" --once

A structured advisory assessment is displayed and saved under
~/.local/share/openlrr-agent/reports/. Run-state is saved locally and caps
attempted model requests at 8 per UTC day. This is NOT a monetary cost cap.

## Watch for new completed benchmarks

Only after a successful one-shot test:

    "$HOME/.local/share/openlrr-agent/venv/bin/python" \
      "$HOME/OpenLRR-Agent/scripts/agent/openlrr_agent.py" --watch --interval 300

The Terminal must remain open, the Mac must remain awake, and gh authentication
must work. An API request is sent only when a new pair of complete reports
appears, not on each five-minute poll. It does not run or restart the game.

**Pause** (checked between polls and before model calls):

    touch "$HOME/.config/openlrr-benchmark/PAUSE"

**Resume:**

    rm "$HOME/.config/openlrr-benchmark/PAUSE"

**Stop**:

    touch "$HOME/.config/openlrr-benchmark/STOP"

Ctrl+C interrupts the foreground process. STOP may not abort an OpenAI network
request already underway. Remove STOP before a deliberate restart. These
switches control the observer, not Wine or GitHub Actions.

## Next development milestones

1. Verify actual Wine game termination, cleanup, crash detection and a hard stop
   that covers the entire Mac test-runner process.
2. Build a supervisor for bounded repetitions with approved binary hashes.
3. Integrate a separate isolated coding agent with PR-only source changes.
4. Gate AI-generated executable testing behind a real security isolation and
   artifact review process; a duplicate Sikarugir app is NOT a security sandbox.
5. Add private status notifications; the agent cannot awaken this exact chat.

This code changes nothing on the Mac until you explicitly install/run it.
