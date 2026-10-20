"""Versioned instructions (agent-reviewer: instructions are code; every change is a new version)."""

import os
from pathlib import Path

DEFAULT_VERSION = "v2"
_DIR = Path(__file__).parent / "prompts"


def available_versions() -> list[str]:
    return sorted(p.stem for p in _DIR.glob("v*.md"))


def load_instructions(version: str | None = None) -> tuple[str, str]:
    """Returns (version, text). The version comes from COMMS_INSTRUCTIONS_VERSION or the default."""
    version = version or os.environ.get("COMMS_INSTRUCTIONS_VERSION", DEFAULT_VERSION)
    path = _DIR / f"{version}.md"
    if not path.is_file():
        raise ValueError(f"unknown comms instructions version: {version}")
    return version, path.read_text(encoding="utf-8")
