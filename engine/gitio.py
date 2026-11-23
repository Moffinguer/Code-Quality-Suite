"""Run git and return its output (shared by the changelog and repository-facts code)."""

import subprocess

TIMEOUT = 120


def git_out(gitcmd, *args, strict=False):
    """Run git and return its standard output.

    Args:
        gitcmd: the git command line prefix (list of str).
        *args: git arguments.
        strict: when true, failures raise; when false they yield an empty string.

    Returns:
        str: stdout decoded as UTF-8 (undecodable bytes replaced); "" on failure when not strict.

    Raises:
        RuntimeError: strict and git exited with a non-zero status.
        subprocess.TimeoutExpired: strict and git took longer than 120 seconds.
    """
    try:
        p = subprocess.run(gitcmd + list(args), capture_output=True, timeout=TIMEOUT, check=False)
    except (OSError, subprocess.SubprocessError):
        if strict:
            raise
        return ""
    if p.returncode:
        if strict:
            raise RuntimeError(
                f"git {' '.join(args[:2])}: {p.stderr.decode('utf-8', 'replace').strip()}"
            )
        return ""
    return p.stdout.decode("utf-8", "replace")


def git_strict(gitcmd, *args):
    """Run git; raise when it fails (see git_out).

    Args:
        gitcmd: the git command line prefix (list of str).
        *args: git arguments.

    Returns:
        str: the standard output.

    Raises:
        RuntimeError: git exited with a non-zero status.
        OSError: git could not be started.
    """
    return git_out(gitcmd, *args, strict=True)
