"""Validate the lossless-text Skill response v1 JSON contract."""

from __future__ import annotations

import sys

try:  # package import and direct script execution are both supported
    from .skill_runtime import validate_response
except ImportError:
    from skill_runtime import validate_response


def main() -> int:
    text = sys.stdin.read()
    try:
        validated = validate_response(text)
    except (ValueError, UnicodeError) as error:
        sys.stderr.write(f"{error}\n")
        return 1
    sys.stdout.write(validated)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
