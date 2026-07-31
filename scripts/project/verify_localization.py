#!/usr/bin/env python3
"""Validate Filius on iPad localization catalogs and source usage."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ENTRY = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$')
CALL = re.compile(r'FiliusLocalization\.t\("([^"]+)"')
PLURAL_CALL = re.compile(r'FiliusLocalization\.plural\(\s*"([^"]+)"')
KEY = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=')

def unescape(value: str) -> str:
    return bytes(value, 'utf-8').decode('unicode_escape') if '\\' in value else value

def read_catalog(path: Path) -> tuple[dict[str, str], list[str]]:
    values: dict[str, str] = {}
    errors: list[str] = []
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if not line.strip() or line.lstrip().startswith(('/*', '*', '//')):
            continue
        match = ENTRY.match(line)
        if not match:
            errors.append(f'{path}:{number}: malformed catalog entry')
            continue
        key = unescape(match.group(1)); value = unescape(match.group(2))
        if key in values:
            errors.append(f'{path}:{number}: duplicate key {key}')
        values[key] = value
    return values, errors

def placeholders(value: str) -> list[str]:
    return re.findall(r'%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@diouxXfFeEgGcCsSpaAn%]', value)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root
    resource = root / 'ios' / 'FiliusPad' / 'Resources'
    catalogs = {}
    errors = []
    for language in ('de', 'en', 'fr'):
        values, parse_errors = read_catalog(resource / f'{language}.lproj' / 'Localizable.strings')
        catalogs[language] = values
        errors.extend(parse_errors)
    sets = {language: set(values) for language, values in catalogs.items()}
    if len({frozenset(keys) for keys in sets.values()}) != 1:
        errors.append('catalog key sets differ: ' + ', '.join(f'{k}={len(v)}' for k,v in sets.items()))
    keys = sets['en']
    for key in sorted(keys):
        for language, values in catalogs.items():
            if not values.get(key, '').strip(): errors.append(f'{language}: empty translation for {key}')
            if placeholders(catalogs['en'][key]) != placeholders(values[key]):
                errors.append(f'{key}: interpolation placeholders differ between en and {language}')
    identical_allowlist = {line.strip() for line in (root/'scripts/project/localization/technical-identical-keys.txt').read_text(encoding='utf-8').splitlines() if line.strip() and not line.startswith('#')}
    # Identical cross-language values are accepted only after key-specific review.
    # This catches copied prose while retaining protocol names, product terms, and format-only values.
    identical_keys = {
        key for key in keys
        if len({catalogs[language][key] for language in catalogs}) < len(catalogs)
    }
    for key in sorted(identical_keys - identical_allowlist):
        errors.append(f'unreviewed identical cross-language value {key}')
    for key in sorted(identical_allowlist - identical_keys):
        errors.append(f'stale identical-value allowlist key {key}')

    german_prose = re.compile(
        r'\b(?:diese|dieser|diesen|einstellungen|gespeichert|werden|weder|anschluss|anschlüsse|netzwerkmaske|regel|regeln|gerät|geräte|ausgewählt|nicht|leere|felder|verbindung|adressvergabe|erfolgen|folgende|zwischen|verschieben|bearbeiten|speichern|aufbewahrung)\b',
        re.IGNORECASE,
    )
    for language in ('en', 'fr'):
        for key, value in catalogs[language].items():
            if german_prose.search(value):
                errors.append(f'semantically untranslated German prose {language}:{key}')

    critical = [line.strip() for line in (root/'scripts/project/localization/critical-keys.txt').read_text(encoding='utf-8').splitlines() if line.strip() and not line.startswith('#')]
    for key in critical:
        if key not in keys: errors.append(f'missing critical key {key}')
    source = '\n'.join(p.read_text(encoding='utf-8') for p in (root/'ios/FiliusPad').rglob('*.swift'))
    preferences_source = (root/'ios/FiliusPad/TopologyEditor/State/TopologyProductShell.swift').read_text(encoding='utf-8')
    app_source = (root/'ios/FiliusPad/FiliusPadApp.swift').read_text(encoding='utf-8')
    for contract, needle in {
        'launch language default': 'language: .system',
        'language preference field': 'var language: FiliusAppLanguage',
        'UserDefaults preference storage': 'defaultStorageKey',
        'launch activation': 'FiliusLocalization.activate(loadedPreferences.language)',
        'settings language picker': 'selection: $preferences.language',
        'settings language accessibility label': '.accessibilityLabel(FiliusLocalization.t("settings.language.title"))',
    }.items():
        if contract == 'launch activation':
            haystack = app_source
        elif contract.startswith('settings language'):
            haystack = (root/'ios/FiliusPad/TopologyEditor/View/TopologyProductShellView.swift').read_text(encoding='utf-8')
        else:
            haystack = preferences_source
        if needle not in haystack:
            errors.append(f'missing {contract} contract')
    plural_bases = set(PLURAL_CALL.findall(source))
    plural_keys = {suffix for base in plural_bases for suffix in (f'{base}.one', f'{base}.other')}
    used = (set(CALL.findall(source)) | plural_keys) - {r'error.validation.\(rawValue)'}
    if 'runtime.files' not in plural_bases:
        errors.append('production plural contract is unused')
    for key in sorted(used - keys):
        errors.append(f'source references missing key {key}')
    for key in critical:
        if key not in used and not key.startswith('error.validation.'):
            errors.append(f'critical key is unused {key}')
    # Scan the whole product-shell/editor/runtime view source, including multiline
    # alerts, TextField prompts, accessibility labels/values, helper title args,
    # computed labels, and ProjectFileNotice/LocalizedError presentation inputs.
    ui_pattern = re.compile(
        r'\b(?:Text|Label|Button|Toggle|Section|Picker|Menu|LabeledContent|TextField)\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
        re.S,
    )
    argument_pattern = re.compile(
        r'\b(?:title|message|explanation|prompt|label|value)\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
        re.S,
    )
    alert_pattern = re.compile(
        r'\.(?:alert|confirmationDialog)\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
        re.S,
    )
    accessibility_pattern = re.compile(
        r'\.accessibility(?:Label|Value|Hint)\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
        re.S,
    )
    helper_patterns = [
        re.compile(r'\bContentUnavailableView\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"', re.S),
        re.compile(r'\bpacketCell\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"', re.S),
        re.compile(r'\bheaderDetails\(\s*title:\s*"([^"\\]*(?:\\.[^"\\]*)*)"', re.S),
        re.compile(r'\b(?:firewallToggle|infrastructureConfigurationSection|headerCell|firewallHeader)\(\s*(?:title:\s*)?"([^"\\]*(?:\\.[^"\\]*)*)"', re.S),
    ]
    allowed = {'TCP', 'UDP', 'ICMP', 'OK', '—', '', '-', 'ID'}
    allowed_non_prose = re.compile(r'^[A-Za-z0-9_./:@\[\]<>|+*=-]+$')
    for path in (root/'ios/FiliusPad/TopologyEditor/View').rglob('*.swift'):
        text = path.read_text(encoding='utf-8')
        matches = []
        for pattern in [ui_pattern, argument_pattern, alert_pattern, accessibility_pattern, *helper_patterns]:
            matches.extend(pattern.finditer(text))
        # Computed accessibility/title/label helpers must not return prose literals.
        matches.extend(re.finditer(r'\breturn\s+"([^"\\]*(?:\\.[^"\\]*)*)"', text))
        for match in matches:
            literal = match.group(1)
            number = text.count('\n', 0, match.start()) + 1
            line_start = text.rfind('\n', 0, match.start()) + 1
            if text[line_start:match.start()].lstrip().startswith('//'):
                continue
            context = text[max(0, match.start() - 80):match.start()]
            if literal in allowed or literal.startswith(('runtime.', 'design.', 'debug.', 'productShell.')):
                continue
            if literal.startswith('\\('):
                continue
            if allowed_non_prose.fullmatch(literal):
                # Wire labels, protocol values, asset paths, SF Symbol names, and
                # accessibility identifiers are not translatable product prose.
                continue
            if 'systemImage' in context or 'relativePath' in context or 'fallbackSystemImage' in context:
                continue
            errors.append(f'hard-coded user-facing literal {path}:{number}: {literal}')
    result = {'languages': {k: len(v) for k,v in catalogs.items()}, 'keys': len(keys), 'usedSourceKeys': len(used), 'criticalKeys': len(critical), 'errors': errors}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if errors else 0

if __name__ == '__main__': sys.exit(main())
