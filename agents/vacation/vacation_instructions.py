"""Versioned instructions (agent-reviewer: instructions are code; every change is a new version)."""

import os
from pathlib import Path

DEFAULT_VERSION = "v1"
_DIR = Path(__file__).parent / "prompts"


def available_versions() -> list[str]:
    return sorted(p.stem for p in _DIR.glob("v*.md"))


def load_instructions(version: str | None = None) -> tuple[str, str]:
    """Returns (version, text). The version comes from VACATION_INSTRUCTIONS_VERSION or the default."""
    version = version or os.environ.get("VACATION_INSTRUCTIONS_VERSION", DEFAULT_VERSION)
    path = _DIR / f"{version}.md"
    if not path.is_file():
        raise ValueError(f"unknown vacation instructions version: {version}")
    return version, path.read_text(encoding="utf-8")
