# Tool-free AI mission-design adapter for the OpenLRR game composer

`scripts/composer/ai_mission_designer.py` turns a brief user idea into a
strictly bounded structured mission design, then hands those **fields only**
to the tested native MAP composer.

The model never writes arbitrary files or executable code, never chooses an
output path, never runs the game, never edits Lego.cfg, and never receives
shell or web tools. It chooses only:

- a safe level identifier, title, and original short synopsis;
- easy / medium / hard difficulty;
- dimensions between 12 and 48;
- a reproducible 32-bit random seed;
- an attainable crystal collection goal.

The deterministic backend generates the actual native MAP binaries and
validates map dimensions, tile codes, crystal count, connected caverns and
excavation paths. The narrative brief is included in the package's SHA256
manifest, and the pack is explicitly marked **not a complete playable
mission**.

By default, the CLI performs a **no-network / no-model dry run**:

```bash
python3 scripts/composer/ai_mission_designer.py \
  --theme "A difficult rescue across a newly discovered crystal cave" \
  --out /tmp/MyMission
```

To explicitly request one **paid**, tool-free AI design and create a new
draft in a previously nonexistent folder, the owner may provide a separate
`OPENAI_API_KEY` and `--compose`. Never put an API key in a public commit:

```bash
python3 scripts/composer/ai_mission_designer.py \
  --theme "A difficult rescue across a newly discovered crystal cave" \
  --out /tmp/MyMission --compose
```

No scheduled model spending or automatic installation has been enabled.
The model's actual dollar cost is unknown until the API returns usage.

The next composer phase will need mission-object and NERPs/PTL scripting,
level-selection configuration, native asset provenance and controlled
playability/visual QA in a strongly isolated test environment. Only then
could the system truthfully describe a generated mission as playable.
