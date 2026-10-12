"""#60 JSON adapter for the existing skill-installer GitHub URL helper."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys


class AdapterArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def _source_candidates():
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        yield Path(codex_home) / "skills/.system/skill-installer/scripts/github_utils.py"
    user_profile = os.environ.get("USERPROFILE")
    if user_profile:
        yield Path(user_profile) / ".codex/skills/.system/skill-installer/scripts/github_utils.py"


def _respond(successful, exception, result):
    sys.stdout.write(
        json.dumps(
            {"isSuccessful": successful, "exception": exception, "result": result},
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + "\n"
    )


def main():
    try:
        parser = AdapterArgumentParser(add_help=False)
        parser.add_argument("--source-path")
        args, unknown = parser.parse_known_args()
        if unknown:
            raise ValueError("Unbekannte Adapterargumente.")
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise ValueError("Eingabe muss ein JSON-Objekt sein.")
        for name in ("repo", "path", "ref"):
            if not isinstance(request.get(name), str) or not request[name].strip():
                raise ValueError(f"Pflichtparameter {name} fehlt oder ist leer.")

        if args.source_path:
            source = Path(args.source_path).expanduser()
        else:
            source = next((candidate for candidate in _source_candidates() if candidate.is_file()), None)
        if source is None or not source.is_file():
            raise FileNotFoundError(
                "github_utils.py nicht gefunden; source_path angeben oder CODEX_HOME/USERPROFILE konfigurieren."
            )

        spec = importlib.util.spec_from_file_location("skill61_github_utils", source)
        if spec is None or spec.loader is None:
            raise ImportError(f"github_utils.py kann nicht geladen werden: {source}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        function = getattr(module, "github_api_contents_url")
        result = function(request["repo"], request["path"], request["ref"])
        if not isinstance(result, str):
            raise TypeError("github_api_contents_url lieferte keinen String.")
        _respond(True, None, result)
    except Exception as error:
        _respond(False, {"message": str(error) or error.__class__.__name__}, None)


if __name__ == "__main__":
    main()
