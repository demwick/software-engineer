#!/usr/bin/env bash
# Fixture helpers for evals. Sourced by suite scripts.
# SPDX-License-Identifier: AGPL-3.0-or-later

_fixtures_dir() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s/../fixtures' "$lib_dir"
}

# Copy a named repo fixture into a fresh tempdir and echo the path.
fixture_repo() {
    local name="$1"
    local src="$(_fixtures_dir)/repos/$name"
    if [[ ! -d "$src" ]]; then
        printf 'fixture_repo: no such fixture: %s\n' "$name" >&2
        return 1
    fi
    local dst
    dst="$(mktemp -d)"
    cp -R "$src/." "$dst/"
    printf '%s' "$dst"
}

# Copy a named state fixture into <workdir>/.se/state.json.
fixture_state() {
    local workdir="$1" name="$2"
    local src="$(_fixtures_dir)/states/$name.json"
    if [[ ! -f "$src" ]]; then
        printf 'fixture_state: no such state: %s\n' "$name" >&2
        return 1
    fi
    mkdir -p "$workdir/.se"
    cp "$src" "$workdir/.se/state.json"
}
