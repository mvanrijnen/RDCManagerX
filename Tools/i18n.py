"""Keeps the English UI catalogue (Source/Lang/en.po) in sync with the Dutch source texts.

Texts are collected from:
  - the DFMs: stored Caption, Hint, TextHint, Title and Filter values, Items.Strings lists, and Text inside
    collection items (status bar panels and the like); strings without a letter (e.g. '-') are skipped;
  - the .pas files: the constant argument of every _( ) call (literals, #nn characters and +).

Usage (from the project folder):
  python Tools/i18n.py update   Adds new texts (empty msgstr), keeps existing translations, drops texts that no
                                longer occur, and lists what still needs translating.
  python Tools/i18n.py check    Exit code 1 when a text has no translation or _( ) has a non-constant argument.
  python Tools/i18n.py list     Prints the untranslated texts.

The catalogue is embedded in the exe via Source/Lang.rc (RCDATA LANG_EN); RdcmX.Lang reads it.
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
PO_FILE = os.path.join(ROOT, 'Source', 'Lang', 'en.po')
TEXT_PROPS = {'Caption', 'Hint', 'TextHint', 'Title', 'Filter'}


# --- Pascal / DFM string expressions -------------------------------------------------------------

def parse_string_expr(text, pos):
    """Parses 'a'#9'b' + 'c' starting at pos (whitespace and newlines allowed around +).
    Returns (value, end_pos) or (None, pos) when there is no constant string expression."""
    value = []
    i = pos
    n = len(text)
    seen = False
    expect_part = True
    while i < n:
        c = text[i]
        if c in ' \t\r\n':
            i += 1
            continue
        # Adjacent parts ('a'#9'b') must touch; after whitespace only + may continue the expression
        # (in an Items.Strings list a new line starts the next item).
        if c in "'#" and not expect_part and text[i - 1] in ' \t\r\n':
            break
        if c == "'":
            j = i + 1
            part = []
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        part.append("'")
                        j += 2
                        continue
                    break
                part.append(text[j])
                j += 1
            value.append(''.join(part))
            i = j + 1
            seen = True
            expect_part = False
            continue
        if c == '#':
            m = re.match(r'#(\$[0-9A-Fa-f]+|\d+)', text[i:])
            if not m:
                break
            code = m.group(1)
            value.append(chr(int(code[1:], 16) if code.startswith('$') else int(code)))
            i += len(m.group(0))
            seen = True
            expect_part = False
            continue
        if c == '+' and seen:
            i += 1
            expect_part = True
            continue
        break
    if not seen or expect_part is True and value:
        return None, pos
    return ''.join(value), i


def has_letter(s):
    return re.search(r'[^\W\d_]', s) is not None


# --- Extraction --------------------------------------------------------------------------------

def strip_pascal_comments(text):
    """Replaces comments with spaces (keeps positions), leaving string literals intact."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    break
                if text[j] in '\r\n':
                    break
                j += 1
            i = j + 1
            continue
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
            continue
        if c == '{':
            j = text.find('}', i)
            j = n - 1 if j < 0 else j
            for k in range(i, j + 1):
                if out[k] not in '\r\n':
                    out[k] = ' '
            i = j + 1
            continue
        if text.startswith('(*', i):
            j = text.find('*)', i)
            j = n - 2 if j < 0 else j
            for k in range(i, j + 2):
                if out[k] not in '\r\n':
                    out[k] = ' '
            i = j + 2
            continue
        i += 1
    return ''.join(out)


def extract_pas(path, texts, problems):
    with open(path, encoding='utf-8-sig') as handle:
        raw = handle.read()
    text = strip_pascal_comments(raw)
    rel = os.path.relpath(path, ROOT).replace('\\', '/')
    for m in re.finditer(r'(?<![A-Za-z0-9_.])_\(', text):
        if re.search(r'(function|procedure)\s+$', text[max(0, m.start() - 12):m.start()]):
            continue  # the declaration of _ itself
        value, end = parse_string_expr(text, m.end())
        if value is None or text[end:].lstrip()[:1] != ')':
            line = text.count('\n', 0, m.start()) + 1
            problems.append(f'{rel}:{line}: _( ) needs a constant string argument')
            continue
        if has_letter(value):
            texts.setdefault(value, []).append(rel)


def extract_dfm(path, texts):
    with open(path, encoding='utf-8-sig', errors='replace') as handle:
        text = handle.read()
    rel = os.path.relpath(path, ROOT).replace('\\', '/')
    joined = text
    # Walk "Name = value" assignments; track whether we are inside a collection (item ... end within < >).
    collection_depth = 0
    i = 0
    n = len(joined)
    line_re = re.compile(r'[ \t]*(?:(item)\s*$|(end)>?\s*$|([A-Za-z_][\w.]*)\s*=\s*)', re.MULTILINE)
    while i < n:
        m = line_re.match(joined, i)
        eol = joined.find('\n', i)
        eol = n if eol < 0 else eol + 1
        if not m:
            i = eol
            continue
        if m.group(3):
            prop = m.group(3)
            after = m.end()
            if joined.startswith('<', after):
                collection_depth += 1
                i = eol
                continue
            if joined.startswith('(', after) and prop.endswith('Items.Strings'):
                j = after + 1
                while True:
                    value, end = parse_string_expr(joined, j)
                    if value is None:
                        break
                    if has_letter(value):
                        texts.setdefault(value, []).append(rel)
                    j = end
                close = joined.find(')', j)
                i = joined.find('\n', close) + 1 if close >= 0 else n
                if i == 0:
                    i = n
                continue
            short = prop.split('.')[-1]
            if short in TEXT_PROPS or (short == 'Text' and collection_depth > 0):
                value, end = parse_string_expr(joined, after)
                if value is not None:
                    if has_letter(value):
                        texts.setdefault(value, []).append(rel)
                    i = joined.find('\n', end)
                    i = n if i < 0 else i + 1
                    continue
            i = eol
            continue
        if m.group(2) and joined[m.start(2):m.end(0)].rstrip().endswith('>'):
            collection_depth = max(0, collection_depth - 1)
        i = eol
    return texts


def collect():
    texts = {}
    problems = []
    for path in sorted(glob.glob(os.path.join(ROOT, 'Source', '*.dfm'))):
        extract_dfm(path, texts)
    for path in sorted(glob.glob(os.path.join(ROOT, 'Source', '*.pas'))):
        extract_pas(path, texts, problems)
    return texts, problems


# --- PO file -----------------------------------------------------------------------------------

def po_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\r', '\\r').replace('\n', '\\n').replace('\t', '\\t')


def po_unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            i += 1
            out.append({'n': '\n', 'r': '\r', 't': '\t'}.get(s[i], s[i]))
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def read_po(path):
    entries = {}
    if not os.path.exists(path):
        return entries
    msgid = msgstr = None
    part = None

    def flush():
        if msgid:
            entries[msgid] = msgstr or ''

    with open(path, encoding='utf-8-sig') as handle:
        lines = handle.read().splitlines()
    for line in lines:
        if line.startswith('msgid '):
            flush()
            msgid, msgstr, part = po_unescape(line[7:-1]), '', 'id'
        elif line.startswith('msgstr '):
            msgstr, part = po_unescape(line[8:-1]), 'str'
        elif line.startswith('"') and part:
            if part == 'id':
                msgid += po_unescape(line[1:-1])
            else:
                msgstr += po_unescape(line[1:-1])
        elif not line.strip():
            flush()
            msgid = msgstr = part = None
    flush()
    return entries


def po_string(keyword, value):
    if '\n' in value and len(value) > 1:
        parts = value.split('\n')
        chunks = [p + '\n' for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])
        return f'{keyword} ""\n' + ''.join(f'"{po_escape(c)}"\n' for c in chunks)
    return f'{keyword} "{po_escape(value)}"\n'


def write_po(path, texts, translations):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = ['# English UI texts for RDCManagerX. The msgid is the Dutch source text.\n',
           '# Maintained with Tools/i18n.py (update/check); embedded via Source/Lang.rc.\n',
           'msgid ""\n',
           'msgstr ""\n',
           '"Content-Type: text/plain; charset=UTF-8\\n"\n',
           '"Language: en\\n"\n',
           '\n']
    for msgid, files in texts.items():
        refs = ' '.join(dict.fromkeys(files))
        out.append(f'#: {refs}\n')
        out.append(po_string('msgid', msgid))
        out.append(po_string('msgstr', translations.get(msgid, '')))
        out.append('\n')
    with open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(''.join(out))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'check'
    texts, problems = collect()
    translations = read_po(PO_FILE)
    missing = [t for t in texts if not translations.get(t)]
    if command == 'update':
        dropped = [t for t in translations if t not in texts]
        write_po(PO_FILE, texts, translations)
        print(f'{len(texts)} texts, {len(texts) - len(missing)} translated, {len(missing)} to translate, {len(dropped)} dropped')
    elif command == 'list':
        for t in missing:
            print(repr(t))
    for p in problems:
        print('ERROR', p)
    if command == 'check':
        for t in missing:
            print('MISSING', repr(t))
        print(f'{len(texts)} texts, {len(missing)} without translation, {len(problems)} problems')
        sys.exit(1 if missing or problems else 0)


if __name__ == '__main__':
    main()
