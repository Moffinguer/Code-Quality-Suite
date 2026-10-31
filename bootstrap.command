#!/usr/bin/env bash
# Double-click launcher for macOS: runs bootstrap.sh (macOS ships bash).
cd "$(dirname "$0")"
./bootstrap.sh "$@"
