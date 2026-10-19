#!/usr/bin/env python3
"""Tool-free AI game mission designer feeding the verified native MAP composer.

A model may suggest only a small bounded design brief; it cannot write map
bytes, choose file paths, run code, patch an existing mission, or start Wine.
Any paid model call is explicit. Generated output is a DRAFT, not playable.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys

import native_map_composer as native

MODEL = "gpt-6-luna"
DIFFICULTIES = frozenset({"easy", "medium", "hard"})
SAFE_THEME = re.compile(r"^[^\x00-\x1f\x7f]{12,600}$")


def check_request(theme: str, destination: Path) -> str:
    if type(theme) is not str or not SAFE_THEME.fullmatch(theme):
        raise ValueError("Mission theme is missing, too long or contains control characters")
    native.safe_output(destination)
    return theme.strip()


def validate_design(plan: dict) -> dict:
    expected = {
        "schema_version", "name", "title", "synopsis",
        "difficulty", "width", "height", "seed", "crystal_goal",
    }
    if type(plan) is not dict or set(plan) != expected or plan["schema_version"] != 1:
        raise ValueError("AI design used an unsupported schema")
    if type(plan["name"]) is not str or not native.SAFE_NAME.fullmatch(plan["name"]):
        raise ValueError("AI selected an unsafe level ID")
    if plan["difficulty"] not in DIFFICULTIES:
        raise ValueError("Unknown mission difficulty")
    for key, low, high in (("title", 8, 80), ("synopsis", 20, 450)):
        value = plan[key]
        if type(value) is not str or not low <= len(value) <= high:
            raise ValueError("Invalid AI " + key)
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError("Unsafe AI control character")
    w, h = plan["width"], plan["height"]
    if (type(w) is not int or type(h) is not int
            or not native.MIN_AXIS <= w <= native.MAX_AXIS
            or not native.MIN_AXIS <= h <= native.MAX_AXIS):
        raise ValueError("AI requested unsupported native map dimensions")
    if (type(plan["seed"]) is not int or not 0 <= plan["seed"] < 2**32
            or type(plan["crystal_goal"]) is not int
            or not 1 <= plan["crystal_goal"] <= 50):
        raise ValueError("AI requested unbounded seed or crystal goal")
    # A model cannot directly choose illegal tile codes or invent a game-ready
    # binary. Validate the real deterministic blueprint under the same rules.
    native.generate(plan["name"], w, h, plan["seed"], plan["crystal_goal"])
    return plan


def propose(theme: str, model: str = MODEL) -> dict:
    from agents import Agent, Runner, set_tracing_disabled
    from pydantic import BaseModel, Field
    from typing import Literal

    set_tracing_disabled(True)

    class DraftMission(BaseModel):
        schema_version: Literal[1] = 1
        name: str = Field(min_length=3, max_length=40)
        title: str = Field(min_length=8, max_length=80)
        synopsis: str = Field(min_length=20, max_length=450)
        difficulty: Literal["easy", "medium", "hard"]
        width: int = Field(ge=12, le=48)
        height: int = Field(ge=12, le=48)
        seed: int = Field(ge=0, lt=2**32)
        crystal_goal: int = Field(ge=1, le=50)

    agent = Agent(
        name="OpenLRR Native Mission Designer",
        model=model,
        tools=[],
        output_type=DraftMission,
        instructions=(
            "Propose ONE original LEGO Rock Raiders-style crystal recovery mission "
            "as a bounded structured design brief. No copyrighted game dialogue "
            "or cloned original maps. The deterministic native MAP writer, not "
            "you, will generate five map layers from your dimensions, seed and "
            "crystal objective. Name must begin with an ASCII letter and use "
            "only ASCII alphanumeric, underscore, hyphen. No paths, extensions, "
            "commands, scripts, code, file changes or approval claims. The "
            "mission is NOT playable without separate config/objectives/NPL "
            "integration and gameplay tests. If the requested idea is not "
            "feasible, propose a small safe crystal-recovery concept instead."
        ),
    )
    answer = Runner.run_sync(
        agent, json.dumps({"user_requested_theme": theme}, sort_keys=True),
        max_turns=1,
    ).final_output
    if not isinstance(answer, DraftMission):
        raise ValueError("Unexpected AI game composer output")
    return validate_design(answer.model_dump())


def create_draft(destination: Path, design: dict) -> dict:
    validate_design(design)
    native.safe_output(destination)
    blueprint = native.generate(
        design["name"], design["width"], design["height"],
        design["seed"], design["crystal_goal"],
    )
    brief = {
        "schema_version": 1,
        "title": design["title"],
        "synopsis": design["synopsis"],
        "difficulty": design["difficulty"],
        "crystal_goal": design["crystal_goal"],
        "native_install_authorized": False,
    }
    info = native.write_pack(destination, blueprint, mission_brief=brief)
    return {
        **info,
        "ai_proposed_only_bounded_design_fields": True,
        "model_executed_shell_commands": False,
        "game_executed": False,
        "candidate_for_actual_game_testing": False,
        "human_level_assembly_required": True,
        "actual_api_cost_usd": None,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", required=True,
                        help="Short original game mission idea, not an instruction file")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--compose", action="store_true",
                        help="Explicit one-time paid tool-free AI brief + binary draft")
    args = parser.parse_args(argv)
    request = check_request(args.theme, args.out)
    if not args.compose:
        print(json.dumps({
            "mode": "offline_preflight",
            "requested_theme_chars": len(request),
            "model_invoked": False,
            "game_launched": False,
            "working_game_modified": False,
        }, sort_keys=True))
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("One-time model request requires explicit OPENAI_API_KEY")
    result = create_draft(args.out, propose(request, args.model))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, TypeError,
            json.JSONDecodeError) as exc:
        print("AI MISSION COMPOSER REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
