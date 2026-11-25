"""Structured logging shared by the engine (same line format as log-lib.sh).

Text:  <ts> <LEVEL> comp=<c> [file=..] [action=..] [status=..] msg="..."
JSON:  one object per line (QUALITY_LOG_FORMAT=json).
"""

import json
import os
import sys
import threading
import time

_LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}
_lock = threading.Lock()


def _now():
    """UTC timestamp for a log line.

    Returns:
        str: the time as YYYY-MM-DDTHH:MM:SSZ.
    """
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def log(level, comp, msg="", file="", action="", status="", console=True):  # noqa: PLR0913, PLR0917 - legacy code, kept as is in the 7.1.1 cleanup
    """console=False: log file only (the caller already printed a friendlier line)."""
    threshold = _LEVELS.get(os.environ.get("QUALITY_LOG_LEVEL", "INFO"), 20)
    if _LEVELS.get(level, 20) < threshold:
        return
    msg = str(msg).replace("\r", " ").replace("\n", " ")
    if os.environ.get("QUALITY_LOG_FORMAT", "text") == "json":
        rec = {"ts": _now(), "level": level, "comp": comp}
        for k, v in (("file", file), ("action", action), ("status", status)):
            if v:
                rec[k] = v
        rec["msg"] = msg
        line = json.dumps(rec, ensure_ascii=False)
    else:
        parts = [_now(), level, f"comp={comp}"]
        for k, v in (("file", file), ("action", action), ("status", status)):
            if v:
                parts.append(f"{k}={v}")
        parts.append(f'msg="{msg}"')
        line = " ".join(parts)
    threshold_console = _LEVELS.get(os.environ.get("QUALITY_LOG_CONSOLE", "WARN"), 30)
    with _lock:
        # why: the terminal shows warnings and errors; the full trail goes to the log file
        if console and _LEVELS.get(level, 20) >= threshold_console:
            sys.stderr.write(line + "\n")
            sys.stderr.flush()
        path = os.environ.get("QUALITY_LOG_FILE", "")
        if path:
            try:
                os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
                with open(path, "a", encoding="utf-8") as fh:
                    fh.write(line + "\n")
            except OSError:
                pass


def result(comp, file, action, ok, msg=""):
    """Log the outcome of an action.

    Args:
        comp: the component name.
        file: the file concerned.
        action: the action name.
        ok: true for success.
        msg: an optional message.
    """
    log("INFO" if ok else "ERROR", comp, msg, file, action, "SUCCESS" if ok else "ERROR")
