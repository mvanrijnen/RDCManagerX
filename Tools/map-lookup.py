"""Resolve "RDCManagerX.exe+$1A2B3C" addresses from debug.log to procedure, unit and line.

The Release build writes a detailed map file next to the exe (Win64/Release/RDCManagerX.map; local only, never
distributed). The debug log writes exception addresses and stacks as module + offset (RVA), see RdcmX.Log.

Usage: python Tools/map-lookup.py <map file> <debug.log>
The map must come from the same build as the exe that wrote the log.
"""
import bisect
import os
import re
import sys

IMAGE_BASE = 0x400000  # Delphi's default image base; the map's segment starts are virtual addresses.


def read_map(path):
    """Returns (segment RVA by number, sorted publics, sorted line numbers) as RVA-keyed lists."""
    segments = {}
    publics = []
    lines = []
    unit = None
    section = None
    with open(path, encoding='latin-1') as handle:
        for raw in handle:
            text = raw.strip()
            match = re.match(r'^([0-9A-F]{4}):([0-9A-F]{16}) [0-9A-F]+H \S+', text)
            if match and section is None:
                segments[int(match.group(1), 16)] = int(match.group(2), 16) - IMAGE_BASE
                continue
            if text.startswith('Address') and 'Publics by Value' in text:
                section = 'publics'
                continue
            if text.startswith('Address') and 'Publics by Name' in text:
                section = 'skip'
                continue
            match = re.match(r'^Line numbers for (\S+)\(', text)
            if match:
                section = 'lines'
                unit = match.group(1)
                continue
            if section == 'publics':
                match = re.match(r'^([0-9A-F]{4}):([0-9A-F]{8})\s+(\S.*)$', text)
                if match:
                    publics.append((int(match.group(1), 16), int(match.group(2), 16), match.group(3)))
            elif section == 'lines':
                for number, seg, offset in re.findall(r'(\d+) ([0-9A-F]{4}):([0-9A-F]{8})', text):
                    lines.append((int(seg, 16), int(offset, 16), unit, int(number)))
    to_rva = lambda seg, offset: segments.get(seg, 0) + offset
    publics = sorted((to_rva(seg, offset), name) for seg, offset, name in publics)
    lines = sorted((to_rva(seg, offset), unit_name, number) for seg, offset, unit_name, number in lines)
    return publics, lines


def lookup(rva, publics, lines):
    """Procedure and unit:line at or before rva."""
    index = bisect.bisect_right(publics, (rva, chr(0x10FFFF))) - 1
    start = publics[index][0] if index >= 0 else 0
    name = publics[index][1] if index >= 0 else '?'
    index = bisect.bisect_right(lines, (rva, chr(0x10FFFF), 1 << 30)) - 1
    # Only a line inside the same procedure: RTL units have no line numbers, so an earlier unit's line would lie.
    where = '{}:{}'.format(lines[index][1], lines[index][2]) if index >= 0 and lines[index][0] >= start else ''
    return name, where


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    publics, lines = read_map(sys.argv[1])
    module = os.path.splitext(os.path.basename(sys.argv[1]))[0].lower() + '.exe'
    pattern = re.compile(r'([\w.-]+\.(?:exe|dll))\+\$([0-9A-Fa-f]+)')
    with open(sys.argv[2], encoding='utf-8', errors='replace') as handle:
        for raw in handle:
            line = raw.rstrip('\n')
            found = pattern.search(line)
            if found and found.group(1).lower() == module:
                name, where = lookup(int(found.group(2), 16), publics, lines)
                line = '{}   -> {} {}'.format(line, name, where)
            print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
