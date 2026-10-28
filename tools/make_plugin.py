"""Write TerminalColorsUnlocked.esp (ESL-flagged) from source.

The plugin holds the colour globals (shared by MCM and the holotape), one
start-game-enabled quest that runs TerminalColorsUnlocked:Main, and the
configuration holotape with its three terminal pages. Record layouts are
copied from vanilla Fallout4.esm records (GLOB, QUST DialogueGenericPlayer,
NOTE/TERM DrinkingBuddyRecipe_GwinnettStout, TERM WorkshopTerminal's VMAD).
Usage: python make_plugin.py <out.esp>
"""
import struct
import sys

FORM_VERSION = 131
MASTER_INDEX = 0x01           # Fallout4.esm is master 00
FIRST_ID = 0x800              # ESL object ids run 0x800-0xFFF

# Vanilla's default Pip-Boy green (fPipboyEffectColorR/G/B 0.08, 1.0, 0.09).
DEFAULT_COLOR = {'TCU_Red': 20, 'TCU_Green': 255, 'TCU_Blue': 23}


def sub(sig, data):
    return sig.encode() + struct.pack('<H', len(data)) + data


def zstr(s):
    return s.encode('latin1') + b'\0'


def wstr(s):
    data = s.encode('latin1')
    return struct.pack('<H', len(data)) + data


def record(sig, form_id, body, flags=0):
    return (sig.encode() + struct.pack('<IIIIHH', len(body), flags, form_id, 0, FORM_VERSION, 0) + body)


def group(label, records):
    body = b''.join(records)
    return b'GRUP' + struct.pack('<I', 24 + len(body)) + label.encode() + struct.pack('<IHHHH', 0, 0, 0, 0, 0) + body


def glob(edid, form_id, value):
    return record('GLOB', form_id, sub('EDID', zstr(edid)) + sub('FNAM', b's') + sub('FLTV', struct.pack('<f', value)))


def object_property(name, form_id):
    # type 1 = Object, status 1 = edited; object format 2: unused, alias -1, form id
    return wstr(name) + bytes([1, 1]) + struct.pack('<HhI', 0, -1, form_id)


def quest(edid, form_id, script, properties):
    script_entry = wstr(script) + b'\0' + struct.pack('<H', len(properties)) + b''.join(
        object_property(name, fid) for name, fid in properties)
    # VMAD v6, object format 2, one script; then the quest fragment block:
    # version 3, no fragments, empty file name, no aliases.
    vmad = struct.pack('<hhH', 6, 2, 1) + script_entry + b'\x03' + struct.pack('<H', 0) + wstr('') + struct.pack('<H', 0)
    # DNAM: flags (Start Game Enabled), priority, form version 0x77, unknown, type
    dnam = struct.pack('<HBBII', 0x0001, 0, 0x77, 0, 0)
    body = (sub('EDID', zstr(edid)) + sub('VMAD', vmad) + sub('FULL', zstr('Terminal Colors Unlocked'))
            + sub('DNAM', dnam) + sub('NEXT', b'') + sub('ANAM', struct.pack('<I', 0)))
    return record('QUST', form_id, body)


def ctda(func, param, value, op=0):
    # condition: operator, comparison value, function, param 1, run on subject
    return sub('CTDA', struct.pack('<B3sfHHIIIIi', op, b'\0\0\0', value, func, 0, param, 0, 0, 0, -1))


GET_GLOBAL_VALUE = 74
EQUAL, NOT_EQUAL = 0x00, 0x20
# Menu item types (ANAM), as vanilla uses them.
SUBMENU, FORCE_REDRAW = 4, 6

# Holotape terminal pages: furniture fields copied from vanilla
# DrinkingBuddyRecipe_GwinnettStoutTerm (a holotape terminal).
TERM_FURNITURE = (sub('MODL', zstr(r'Furniture\Terminals\TerminalWall01.nif'))
                  + sub('KSIZ', struct.pack('<I', 3)) + sub('KWDA', bytes.fromhex('d7560a00bbd506002220 0c00'.replace(' ', '')))
                  + sub('PNAM', bytes.fromhex('cc4c3300')) + sub('FNAM', b'\0\0')
                  + sub('MNAM', bytes.fromhex('01000040')) + sub('WBDT', b'')
                  + sub('XMRK', zstr(r'Markers\MarkerWallTerminal3rdP.nif'))
                  + sub('SNAM', bytes.fromhex('000000000000acc2000000000000000000000000ffffffff')))


def terminal(edid, form_id, script, quest_id, header, bodies, items):
    """bodies: [(text, conditions)]; items: [(text, type, id, submenu, conditions)].
    A plain attached script, no fragments (vanilla WorkshopTerminal's VMAD shape)."""
    vmad = struct.pack('<hhH', 6, 2, 1) + wstr(script) + b'\0' + struct.pack('<H', 1) + object_property('TCU_MainQuest', quest_id)
    body = (sub('EDID', zstr(edid)) + sub('VMAD', vmad) + sub('OBND', bytes.fromhex('eeffccff5600150000008700'))
            + sub('WNAM', zstr(header)) + sub('FULL', zstr('Terminal Colors Unlocked')) + TERM_FURNITURE)
    body += sub('BSIZ', struct.pack('<I', len(bodies)))
    for text, conds in bodies:
        body += sub('BTXT', zstr(text)) + b''.join(conds)
    body += sub('ISIZ', struct.pack('<I', len(items)))
    for text, kind, item_id, submenu, conds in items:
        body += sub('ITXT', zstr(text)) + sub('ANAM', bytes([kind])) + sub('ITID', struct.pack('<H', item_id))
        if submenu:
            body += sub('TNAM', struct.pack('<I', submenu))
        body += b''.join(conds)
    return record('TERM', form_id, body)


def holotape(edid, form_id, name, term_id):
    # Layout of vanilla terminal holotapes (DrinkingBuddyRecipe_GwinnettStout).
    body = (sub('EDID', zstr(edid)) + sub('OBND', bytes.fromhex('fdfffdff0000030003000100'))
            + sub('PTRN', bytes.fromhex('a5950900')) + sub('FULL', zstr(name))
            + sub('MODL', zstr(r'Props\Holotape_Prop.nif'))
            + sub('YNAM', bytes.fromhex('a8bf0b00')) + sub('ZNAM', bytes.fromhex('a9bf0b00'))
            + sub('DNAM', b'\x03') + sub('DATA', bytes(8)) + sub('SNAM', struct.pack('<I', term_id)))
    return record('NOTE', form_id, body)


PRESET_NAMES = ['Classic green', 'Amber', 'White', 'Blue', 'Red']  # TCU_Preset 1-5, as on the MCM page


def build():
    next_id = FIRST_ID
    globs, ids = [], {}
    for edid, value in [('TCU_Enabled', 1)] + list(DEFAULT_COLOR.items()):
        fid = (MASTER_INDEX << 24) | next_id
        ids[edid] = fid
        globs.append(glob(edid, fid, value))
        next_id += 1
    quest_id = (MASTER_INDEX << 24) | next_id
    next_id += 1
    # Added after the quest so earlier form ids never move (MCM refers to them).
    for edid, value in [('TCU_Preset', 1)]:
        fid = (MASTER_INDEX << 24) | next_id
        ids[edid] = fid
        globs.append(glob(edid, fid, value))
        next_id += 1
    # Configuration holotape (no MCM needed): three terminal pages.
    for edid in ('TCU_ConfigHolotape', 'TCU_HolotapeMain', 'TCU_HolotapePresets', 'TCU_HolotapeColour'):
        ids[edid] = (MASTER_INDEX << 24) | next_id
        next_id += 1
    script = 'TerminalColorsUnlocked:Holotape'
    on = [ctda(GET_GLOBAL_VALUE, ids['TCU_Enabled'], 1.0)]
    off = [ctda(GET_GLOBAL_VALUE, ids['TCU_Enabled'], 1.0, NOT_EQUAL)]
    pages = [
        terminal('TCU_HolotapeMain', ids['TCU_HolotapeMain'], script, quest_id, 'Terminal Colors Unlocked',
                 [('Terminal colouring is ON.', on), ('Terminal colouring is OFF.', off),
                  ('Changes show at once on an open terminal, otherwise the next time you use one.', [])],
                 [('Turn terminal colouring off', FORCE_REDRAW, 2, 0, on),
                  ('Turn terminal colouring on', FORCE_REDRAW, 1, 0, off),
                  ('Choose a preset colour', SUBMENU, 3, ids['TCU_HolotapePresets'], []),
                  ('Adjust red, green and blue', SUBMENU, 4, ids['TCU_HolotapeColour'], []),
                  ('Show the current colour', FORCE_REDRAW, 5, 0, [])]),
        terminal('TCU_HolotapePresets', ids['TCU_HolotapePresets'], script, quest_id, 'Preset colours',
                 [('Pick a colour. Tab goes back.', [])],
                 [(name, FORCE_REDRAW, 11 + i, 0, []) for i, name in enumerate(PRESET_NAMES)]),
        terminal('TCU_HolotapeColour', ids['TCU_HolotapeColour'], script, quest_id, 'Adjust the colour',
                 [('Each step changes one part of the colour by 15 (0 to 255). Tab goes back.', [])],
                 [(f'{name} {sign}', FORCE_REDRAW, 21 + 2 * c + d, 0, [])
                  for c, name in enumerate(('Red', 'Green', 'Blue')) for d, sign in enumerate(('up', 'down'))]),
    ]
    tape = holotape('TCU_ConfigHolotape', ids['TCU_ConfigHolotape'], 'Terminal Colors Unlocked Settings',
                    ids['TCU_HolotapeMain'])
    qust = quest('TCU_MainQuest', quest_id, 'TerminalColorsUnlocked:Main',
                 [(name, ids[name]) for name in ('TCU_Enabled', 'TCU_Red', 'TCU_Green', 'TCU_Blue', 'TCU_Preset',
                                                 'TCU_ConfigHolotape')])
    record_count = len(globs) + 1 + 1 + len(pages)
    header = (sub('HEDR', struct.pack('<fiI', 1.0, record_count, next_id))
              + sub('CNAM', zstr('sayngwyn'))
              + sub('MAST', zstr('Fallout4.esm')) + sub('DATA', struct.pack('<Q', 0)))
    tes4 = b'TES4' + struct.pack('<IIIIHH', len(header), 0x200, 0, 0, FORM_VERSION, 0) + header  # 0x200 = ESL
    # Top groups in the game's own order.
    return tes4 + group('GLOB', globs) + group('NOTE', [tape]) + group('TERM', pages) + group('QUST', [qust])


if __name__ == '__main__':
    with open(sys.argv[1], 'wb') as f:
        f.write(build())
