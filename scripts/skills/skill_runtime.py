"""Shared, lossless skill discovery and execution runtime."""

from __future__ import annotations

import argparse
import datetime as _datetime
import json
import os
import re
import subprocess
import stat
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any


class _Pairs(list):
    """An object represented as pairs, so duplicate keys remain observable."""


class _Number(str):
    """An exact JSON number lexeme."""


def decode_json(text: str) -> Any:
    return json.loads(text, parse_int=_Number, parse_float=_Number,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(f"Invalid JSON number: {x}")),
                      object_pairs_hook=_Pairs)


def _mapping(value: Any, label: str, *, duplicates: bool = True) -> dict[str, Any]:
    if not isinstance(value, _Pairs):
        raise ValueError(f"{label} must be a JSON object")
    result: dict[str, Any] = {}
    for key, item in value:
        if duplicates and key in result:
            raise ValueError(f"Duplicate {label} field: {key}")
        result[key] = item
    return result


def _is_integer(value: _Number) -> bool:
    match = re.fullmatch(r"-?(?:0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?", value)
    if not match:
        return False
    fraction, exponent = match.groups()
    digits = value.lstrip("-").split("e")[0].split("E")[0].replace(".", "")
    if not digits.strip("0"):
        return True
    exponent_text = exponent or "0"
    negative_exponent = exponent_text.startswith("-")
    magnitude = exponent_text.lstrip("+-").lstrip("0") or "0"
    limit = len(digits) if negative_exponent else len(digits) + len(fraction or "")
    if len(magnitude) > len(str(limit)):
        return not negative_exponent
    exponent_value = int(magnitude)
    scale = (-exponent_value if negative_exponent else exponent_value) - len(fraction or "")
    if scale >= 0:
        return True
    if not digits.strip("0"):
        return True
    return len(digits) - len(digits.rstrip("0")) >= -scale


def _is_reparse(path: Path) -> bool:
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return False
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def _safe_resolve(path: Path) -> Path:
    cursor = Path(os.path.abspath(path))
    while True:
        if _is_reparse(cursor):
            raise ValueError("Reparse/symlink path component is not allowed")
        if cursor.parent == cursor:
            break
        cursor = cursor.parent
    return path.resolve(strict=True)


def _json_lossless(value: Any) -> str:
    if isinstance(value, _Number):
        return str(value)
    if isinstance(value, _Pairs):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + _json_lossless(v) for k, v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + _json_lossless(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ",".join(_json_lossless(v) for v in value) + "]"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def validate_response(text: str) -> str:
    doc = _mapping(decode_json(text), "response")
    if set(doc) != {"isSuccessful", "exception", "result"}:
        raise ValueError("Response must contain exactly isSuccessful, exception, and result")
    if not isinstance(doc["isSuccessful"], bool):
        raise ValueError("isSuccessful must be a JSON boolean")
    exception = doc["exception"]
    if doc["isSuccessful"]:
        if exception is not None:
            raise ValueError("Successful response must have exception=null")
    else:
        error = _mapping(exception, "exception", duplicates=False)
        message = error.get("message")
        if type(message) is not str or not message.strip():
            raise ValueError("Failed response requires a nonblank exception.message")
    return text.strip(" \t\r\n")


def _pairs_object(value: Any, label: str) -> dict[str, Any]:
    return _mapping(value, label)


def _contained_path(path: Path, roots: list[Path], *, kind: str) -> Path:
    lexical = Path(os.path.abspath(path))
    cursor = lexical
    while True:
        if _is_reparse(cursor):
            raise ValueError("Reparse/symlink path component is not allowed")
        if cursor.parent == cursor:
            break
        cursor = cursor.parent
    resolved_roots = [_safe_resolve(root) for root in roots]
    candidate = path.resolve(strict=True)
    if kind == "dir" and not candidate.is_dir():
        raise ValueError("Expected directory")
    if kind == "file" and not candidate.is_file():
        raise ValueError("Expected file")
    for base in resolved_roots:
        try:
            candidate.relative_to(base)
            cursor = candidate
            while True:
                if _is_reparse(cursor):
                    raise ValueError("Reparse/symlink path component is not allowed")
                if cursor == base:
                    return candidate
                cursor = cursor.parent
        except ValueError:
            continue
    raise ValueError("Path is outside configured trusted roots")


def _repo_script(root: Path, rel: str) -> Path:
    if type(rel) is not str or not rel or "\\" in rel or ":" in rel or rel.startswith("/"):
        raise ValueError("Invalid repository-relative scriptPath")
    parts = rel.split("/")
    if any(p in ("", ".", "..") for p in parts):
        raise ValueError("Invalid repository-relative scriptPath")
    full = _contained_path(root.joinpath(*parts), [root], kind="file")
    if full.suffix.lower() not in (".ps1", ".py", ".js"):
        raise ValueError("Unsupported script extension")
    return full


def _registry(root: Path) -> list[dict[str, Any]]:
    registry_path = _contained_path(root / "skills" / "registry.json", [root], kind="file")
    data = decode_json(registry_path.read_text(encoding="utf-8"))
    obj = _pairs_object(data, "registry")
    skills = obj.get("skills")
    if type(skills) is not list:
        raise ValueError("Registry skills must be an array")
    found: list[dict[str, Any]] = []
    ids: set[str] = set()
    for item in skills:
        skill = _pairs_object(item, "skill")
        sid = skill.get("id")
        if type(sid) is not str or not sid:
            raise ValueError("Registry skill id must be a nonempty string")
        if sid in ids:
            raise ValueError(f"Duplicate skill id: {sid}")
        ids.add(sid)
        found.append(skill)
    return found


def _select(skills: list[dict[str, Any]], request: dict[str, Any]) -> dict[str, Any]:
    sid, purpose = request.get("skillId"), request.get("purpose")
    if sid is not None:
        if type(sid) is not str or not sid:
            raise ValueError("skillId must be a nonempty string")
        choices = [s for s in skills if s.get("id") == sid]
    elif type(purpose) is str and purpose:
        choices = [s for s in skills if type(s.get("purpose")) is str and purpose.casefold() in s["purpose"].casefold()]
    else:
        raise ValueError("Provide skillId or purpose")
    if len(choices) != 1:
        candidates = ", ".join(str(s.get("id")) for s in choices)
        raise ValueError("Skill not found" if not choices else f"Ambiguous purpose; candidates: {candidates}")
    return choices[0]


def _validate_parameters(skill: dict[str, Any], raw: Any) -> dict[str, Any]:
    params = _pairs_object(raw, "parameters")
    specs = skill.get("parameters")
    if type(specs) is not list:
        raise ValueError("Registry parameters must be an array")
    by_name: dict[str, dict[str, Any]] = {}
    for value in specs:
        spec = _pairs_object(value, "parameter specification")
        name = spec.get("name")
        if type(name) is not str or not name or name in by_name:
            raise ValueError("Invalid or duplicate registry parameter name")
        by_name[name] = spec
    for name in params:
        if name not in by_name:
            raise ValueError(f"Unknown parameter: {name}")
    resolved: dict[str, Any] = {}
    for name, spec in by_name.items():
        if name in params:
            value = params[name]
        elif "default" in spec:
            value = spec["default"]
        elif spec.get("required") is True:
            raise ValueError(f"Required parameter missing: {name}")
        else:
            continue
        expected = spec.get("type")
        actual = ("null" if value is None else "boolean" if isinstance(value, bool) else
                  "integer" if isinstance(value, _Number) and _is_integer(value) else
                  "number" if isinstance(value, _Number) else "string" if type(value) is str else "object" if isinstance(value, _Pairs) else
                  "array" if isinstance(value, list) else "invalid")
        if actual != expected and not (actual == "integer" and expected == "number"):
            raise ValueError(f"Parameter {name} expects {expected}, got {actual}")
        if expected == "string" and spec.get("required") is True and not value.strip():
            raise ValueError(f"Required string parameter is blank: {name}")
        resolved[name] = value
    return resolved


def _plain(value: Any) -> Any:
    if isinstance(value, _Pairs):
        return {k: _plain(v) for k, v in value}
    if isinstance(value, list):
        return [_plain(x) for x in value]
    if isinstance(value, _Number):
        return value
    return value


def _json_default(value: Any) -> Any:
    if isinstance(value, _Number):
        return str(value)
    raise TypeError(type(value).__name__)


def discover(request: dict[str, Any]) -> dict[str, Any]:
    root_value = request.get("repositoryRoot")
    if root_value is not None and type(root_value) is not str:
        raise ValueError("repositoryRoot must be a string")
    root = _safe_resolve(Path(root_value or Path(__file__).parents[2]))
    skill = _select(_registry(root), request)
    script = _repo_script(root, skill.get("scriptPath"))
    language = skill.get("language") or "powershell"
    interpreter = skill.get("interpreter") or ("powershell.exe" if language == "powershell" else None)
    expected_extension = {"powershell": ".ps1", "python": ".py", "javascript": ".js", "js": ".js"}.get(language)
    if expected_extension and script.suffix.lower() != expected_extension:
        raise ValueError("Known language and script extension do not match")
    params = _validate_parameters(skill, request.get("parameters", _Pairs())) if "parameters" in request else {}
    result = skill
    return {"skill": result, "resolvedLanguage": language, "resolvedInterpreter": interpreter,
            "resolvedScriptPath": str(script), "repositoryRoot": str(root), "resolvedParameters": _plain(params)}


def _guid(value: Any, name: str) -> None:
    if type(value) is not str:
        raise ValueError(f"{name} must be a GUID string")
    try:
        uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ValueError(f"{name} must be a GUID") from None


def run(request: dict[str, Any]) -> str:
    # Termination covers the direct child only; no process-tree guarantee is made.
    started_at = _datetime.datetime.now(_datetime.timezone.utc).isoformat()
    started = time.monotonic()
    phase = "Discovery"
    process: subprocess.Popen[bytes] | None = None
    out = err = ""
    exit_code: int | None = None
    timed_out = False
    log_attempted = False
    skill: dict[str, Any] = {}
    execution_ref = request.get("executionRef")
    work_ref = request.get("workItemRef")
    root: Path | None = None
    try:
        root_value = request.get("repositoryRoot")
        if root_value is not None and type(root_value) is not str:
            raise ValueError("repositoryRoot must be a string")
        root = _safe_resolve(Path(root_value or Path(__file__).parents[2]))
        if type(execution_ref) is not str or not execution_ref.strip() or type(work_ref) is not str or not work_ref.strip():
            raise ValueError("workItemRef and executionRef must be nonempty strings")
        skill = _select(_registry(root), request)
        params = _validate_parameters(skill, request.get("parameters", _Pairs()))
        sid = skill["id"]
        phase = "Parameter"
        if sid == "task-token-usage":
            _guid(params.get("task_id"), "task_id")
            accounting = Path(params["accounting_directory"])
            phase = "Prerequisite"
            accounting_roots = request.get("accountingRoots", [])
            if type(accounting_roots) is not list or any(type(p) is not str for p in accounting_roots):
                raise ValueError("accountingRoots must be an array of strings")
            _contained_path(accounting, [Path(p) for p in accounting_roots], kind="dir")
            for prerequisite in (root / "scripts/accounting/Get-TaskTokenUsage.ps1",):
                _contained_path(prerequisite, [root], kind="file")
        if sid == "github-contents-url":
            pass
        phase = "Path"
        script = _repo_script(root, skill.get("scriptPath"))
        lang = skill.get("language") or "powershell"
        registered = skill.get("interpreter") or ("powershell.exe" if lang == "powershell" else None)
        if lang not in ("powershell", "python"):
            raise ValueError(f"UnsupportedTransport: {lang}")
        if (lang == "powershell" and script.suffix.lower() != ".ps1") or (lang == "python" and script.suffix.lower() != ".py"):
            raise ValueError("UnsupportedTransport: language and script extension do not match")
        phase = "Interpreter"
        bindings = _mapping(request.get("interpreterBindings", _Pairs()), "interpreterBindings")
        if registered not in bindings or type(bindings[registered]) is not str or not Path(bindings[registered]).is_absolute():
            raise ValueError(f"No absolute interpreter binding for {registered}")
        bound_value = bindings[registered]
        if type(bound_value) is not str:
            raise ValueError("Interpreter binding must be a string")
        exe = _safe_resolve(Path(bound_value))
        if Path(registered).is_absolute() and _safe_resolve(Path(registered)) != exe:
            raise ValueError("Absolute registry interpreter must match its binding")
        if not exe.is_file():
            raise ValueError("Bound interpreter is not a file")
        timeout = request.get("timeoutSeconds", _Number("60"))
        if not isinstance(timeout, _Number) or not _is_integer(timeout):
            raise ValueError("timeoutSeconds must be an integer from 1 to 86400")
        from decimal import Decimal, InvalidOperation
        try:
            timeout_decimal = Decimal(str(timeout))
            if not timeout_decimal.is_finite() or timeout_decimal != timeout_decimal.to_integral_value():
                raise ValueError
            timeout = int(timeout_decimal)
        except (InvalidOperation, ValueError, OverflowError):
            raise ValueError("timeoutSeconds must be an integer from 1 to 86400") from None
        if not 1 <= timeout <= 86400:
            raise ValueError("timeoutSeconds must be an integer from 1 to 86400")
        # Recheck before process creation.
        script = _repo_script(root, skill.get("scriptPath"))
        argv: list[str]
        input_text: str | None = None
        if sid == "task-token-usage" and lang == "powershell":
            if any(type(params.get(k)) is not str for k in ("task_id", "accounting_directory")):
                raise ValueError("UnsupportedTransport: PowerShell P1 accepts string parameters only")
            launcher = _contained_path(root / "scripts/skills/Invoke-PowerShellAdapter.ps1", [root], kind="file")
            argv = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(launcher),
                    "-AdapterPath", str(script), "-TaskId", params["task_id"],
                    "-AccountingDirectory", params["accounting_directory"]]
        elif sid == "github-contents-url" and lang == "python":
            source = request.get("sourcePath")
            if source is None:
                raise ValueError("sourcePath must identify trusted github_utils.py")
            trusted_roots = request.get("trustedSourceRoots", [])
            if type(trusted_roots) is not list or any(type(p) is not str for p in trusted_roots):
                raise ValueError("trustedSourceRoots must be an array of strings")
            src = _contained_path(Path(source), [Path(p) for p in trusted_roots], kind="file")
            if src.name != "github_utils.py":
                raise ValueError("Trusted source must be github_utils.py")
            if any(type(params.get(k)) is not str for k in ("repo", "path", "ref")):
                raise ValueError("UnsupportedTransport: Python P1 accepts string parameters only")
            argv = [str(script), "--source-path", str(src)]
            input_text = json.dumps({k: params[k] for k in ("repo", "path", "ref")}, ensure_ascii=False, separators=(",", ":"))
        else:
            raise ValueError(f"UnsupportedTransport: {lang}/{sid}")
        env = os.environ.copy()
        if lang == "python":
            env["PYTHONUTF8"] = "1"
            env["PYTHONIOENCODING"] = "utf-8:strict"
        phase = "Start"
        process = subprocess.Popen([str(exe), *argv], cwd=str(root), shell=False,
                                   stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            stdout_b, stderr_b = process.communicate(input=input_text.encode("utf-8", "strict") if input_text is not None else None, timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            phase = "Timeout"
            try:
                process.kill()
            except OSError:
                pass
            try:
                stdout_b, stderr_b = process.communicate(timeout=2)
            except subprocess.TimeoutExpired as timeout_error:
                stdout_b = timeout_error.output or b""
                stderr_b = timeout_error.stderr or b""
            out, err = _timeout_text(stdout_b), _timeout_text(stderr_b)
            exit_code = process.poll()
            raise TimeoutError(f"Skill timed out after {timeout} seconds")
        phase = "Decoding"
        out = stdout_b.decode("utf-8", "strict")
        err = stderr_b.decode("utf-8", "strict")
        exit_code = process.returncode
        if exit_code != 0:
            phase = "Exit"
            raise RuntimeError(f"Skill process exited with code {exit_code}")
        phase = "Contract"
        response = validate_response(out)
        adapter_status = decode_json(response)
        fach_status = _mapping(adapter_status, "response").get("isSuccessful")
        log_attempted = True
        _write_log(request, skill, root, script, exe, started_at, started, timeout, exit_code, out, err, None, phase, timed_out,
                   _plain(params), fach_status)
        if err:
            sys.stderr.write(err)
        return response
    except Exception as exc:
        if process is not None:
            if process.poll() is None:
                try:
                    process.kill()
                except OSError:
                    pass
            if not timed_out:
                try:
                    stdout_b, stderr_b = process.communicate(timeout=2)
                    out = stdout_b.decode("utf-8", "replace")
                    err = stderr_b.decode("utf-8", "replace")
                    exit_code = process.returncode
                except Exception:
                    pass
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    try:
                        stream.close()
                    except OSError:
                        pass
        if not log_attempted:
            try:
                log_attempted = True
                _write_log(request, skill, root, locals().get("script"), locals().get("exe"), started_at, started,
                           locals().get("timeout", 60), exit_code, out, err, {"phase": phase, "message": str(exc)}, phase, timed_out,
                           _plain(locals()["params"]) if "params" in locals() else None)
            except Exception as log_exc:
                phase = "Protocol"
                exc = RuntimeError(f"Execution log write failed: {log_exc}")
        elif phase != "Protocol":
            phase = "Protocol"
            exc = RuntimeError(f"Execution log write failed: {exc}")
        sys.stderr.write(f"{phase}: {exc}\n")
        return json.dumps({"isSuccessful": False, "exception": {"code": "RunnerError", "message": str(exc),
                                                                  "phase": phase, "executionRef": execution_ref}, "result": None},
                          ensure_ascii=False, separators=(",", ":"))


def _timeout_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    return (value or b"").decode("utf-8", "replace")


def _write_log(request: dict[str, Any], skill: dict[str, Any], root: Path | None, script: Any, exe: Any,
               started_at: str, started: float, timeout: Any, exit_code: Any, out: str, err: str,
               error: Any, phase: str, timed_out: bool = False, resolved_parameters: Any = None,
               fach_status: Any = None) -> None:
    execution_ref = request.get("executionRef", "run")
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", execution_ref)[:120] or "run"
    log_path = request.get("logPath") or (Path(tempfile.gettempdir()) / "agent-org-skill-runs" / f"{safe}.json")
    target = Path(log_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        commit = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], shell=False,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3, check=False,
                                text=True, encoding="utf-8", errors="strict").stdout.strip() or None
    except Exception:
        commit = None
    record = {"workItemRef": request.get("workItemRef"), "executionRef": execution_ref,
              "skillId": skill.get("id"), "commit": commit,
              "parameters": request.get("parameters"), "resolvedParameters": resolved_parameters,
              "repositoryRoot": str(root),
              "scriptPath": str(script) if script else None, "interpreter": str(exe) if exe else None,
              "startedAt": started_at, "endedAt": _datetime.datetime.now(_datetime.timezone.utc).isoformat(),
              "durationSeconds": time.monotonic() - started, "timeoutSeconds": timeout,
              "timedOut": timed_out, "exitCode": exit_code,
              "stdout": out, "stderr": err, "error": error, "phase": phase}
    if fach_status is not None:
        record["fachStatus"] = fach_status
    record["rawParametersJson"] = _json_lossless(request.get("parameters"))
    if isinstance(record["parameters"], _Pairs):
        try:
            record["parameters"] = _mapping(record["parameters"], "parameters", duplicates=False)
        except (TypeError, ValueError):
            record["parameters"] = None
    data = _json_lossless(record) + "\n"
    with target.open("a", encoding="utf-8", errors="strict", newline="") as handle:
        handle.write(data)


def _request(args: argparse.Namespace) -> dict[str, Any]:
    if args.request_json is not None:
        raw = args.request_json
    elif args.request_file:
        raw = Path(args.request_file).read_text(encoding="utf-8")
    else:
        raw = sys.stdin.read()
    return _pairs_object(decode_json(raw), "request")


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("operation", choices=("discover", "run"))
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--request-json")
    source.add_argument("--request-file")
    args = parser.parse_args()
    try:
        request = _request(args)
        if args.operation == "discover":
            value = {"isSuccessful": True, "exception": None, "result": discover(request)}
            sys.stdout.write(_json_lossless(value) + "\n")
        else:
            sys.stdout.write(run(request) + "\n")
        return 0
    except Exception as exc:
        response = {"isSuccessful": False, "exception": {"code": "RunnerError", "message": str(exc),
                                                            "phase": "Discovery" if args.operation == "discover" else "Request",
                                                            "executionRef": None}, "result": None}
        sys.stderr.write(str(exc) + "\n")
        sys.stdout.write(_json_lossless(response) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
