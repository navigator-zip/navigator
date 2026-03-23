#!/bin/bash
set -euo pipefail

# Requires: python3

python3 - <<'PY'
import glob
import json
import sys

paths = glob.glob('**/*.xcstrings', recursive=True)
issues = []

for path in paths:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        issues.append((path, f'JSON parse error: {e}'))
        continue

    if data.get('version') != '1.1':
        issues.append((path, f"version {data.get('version')!r}"))

    strings = data.get('strings')
    if not isinstance(strings, dict):
        issues.append((path, 'missing strings dict'))
        continue

    for key, entry in strings.items():
        if not key or key.strip() == '':
            issues.append((path, f'empty/whitespace key {key!r}'))
            continue

        if not isinstance(entry, dict):
            issues.append((path, f'entry for {key!r} not dict'))
            continue

        if entry.get('extractionState') != 'manual':
            issues.append((path, f'{key}: extractionState {entry.get("extractionState")!r}'))

        localizations = entry.get('localizations')
        if not isinstance(localizations, dict):
            issues.append((path, f'{key}: missing localizations dict'))
            continue

        for lang in ('en', 'ja'):
            loc = localizations.get(lang)
            if not isinstance(loc, dict):
                issues.append((path, f'{key}: missing {lang} localization'))
                continue

            string_unit = loc.get('stringUnit')
            if not isinstance(string_unit, dict):
                issues.append((path, f'{key}: {lang} missing stringUnit'))
                continue

            value = string_unit.get('value')
            if value is None or value == '':
                issues.append((path, f'{key}: {lang} empty value'))

if issues:
    for path, message in issues:
        print(f'{path}: {message}')
    sys.exit(1)

print('No xcstrings issues found.')
PY
