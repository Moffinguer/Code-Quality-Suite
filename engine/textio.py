"""File readers shared by the engine; each caller states its error contract explicitly."""

_RAISE = object()


def read_text(path, *, limit=None, errors="strict", newline=None, default=_RAISE):
    """Read a UTF-8 text file.

    Args:
        path: the file path.
        limit: read at most this many characters (None: the whole file).
        errors: the codec error handler ("strict", "replace", ...).
        newline: passed to open() ("" keeps line ends untouched, None translates them).
        default: value returned when the file cannot be read or decoded; when omitted the
            error is raised instead.

    Returns:
        str: the decoded text, or `default` on failure.

    Raises:
        OSError: the file cannot be read and no default was given.
        UnicodeDecodeError: the file is not valid UTF-8 and no default was given.
    """
    try:
        with open(path, encoding="utf-8", errors=errors, newline=newline) as fh:
            return fh.read() if limit is None else fh.read(limit)
    except (OSError, UnicodeDecodeError):
        if default is _RAISE:
            raise
        return default


def read_bytes(path):
    """Read a file as bytes.

    Args:
        path: the file path.

    Returns:
        bytes: the raw content.

    Raises:
        OSError: the file cannot be read.
    """
    with open(path, "rb") as fh:
        return fh.read()
