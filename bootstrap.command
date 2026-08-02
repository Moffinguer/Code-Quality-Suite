#!/usr/bin/env bash
# Doble clic en macOS. Mac trae bash, asi que solo delega en bootstrap.sh.
cd "$(dirname "$0")"
./bootstrap.sh "$@"
