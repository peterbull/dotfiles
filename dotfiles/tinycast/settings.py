#!/usr/bin/python3
import argparse
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys
import tempfile
from xml.parsers.expat import ExpatError

DOMAIN = 'com.tinycast.app'
DEFAULTS = '/usr/bin/defaults'
SNAPSHOT = Path(__file__).resolve().with_name('settings.plist')
TYPES = {
    'boundAppBundleIDs': list,
    'favoriteApps': list,
    'calendarMenuBarDisplay': int,
    'quicklinksEnabled': bool,
    'showInMenuBar': bool,
}


def managed(key):
    return key in TYPES or key == 'hotkey.togglePalette' or any(
        key.startswith(prefix) and len(key) > len(prefix)
        for prefix in ('hotkey.app.', 'hotkey.command:')
    )


def reject_constant(value):
    raise ValueError('Invalid JSON constant')


def validate(data):
    for key, value in data.items():
        if not managed(key):
            raise ValueError('Unknown snapshot key: ' + key)
        expected = TYPES.get(key, str)
        valid = type(value) is expected
        if valid and expected is list:
            valid = all(type(item) is str for item in value)
        if valid and expected is str:
            try:
                valid = type(json.loads(value, parse_constant=reject_constant)) is dict
            except (ValueError, RecursionError):
                valid = False
        if not valid:
            raise ValueError('Invalid value type or JSON object for key: ' + key)


def decode(data, label):
    try:
        result = plistlib.loads(data)
    except (ValueError, TypeError, OverflowError, ExpatError) as error:
        raise ValueError('Malformed plist: ' + label) from error
    if type(result) is not dict:
        raise ValueError('Expected a dictionary plist: ' + label)
    return result


def defaults(action, data=None):
    result = subprocess.run([DEFAULTS, action, DOMAIN, '-'], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise ValueError('defaults {} failed (exit {})'.format(action, result.returncode))
    return result.stdout


def export():
    return decode(defaults('export'), 'live preferences')


def require_closed():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'Tinycast'],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode == 0:
        raise ValueError('Close Tinycast manually before applying preferences.')
    if result.returncode != 1:
        raise ValueError('pgrep failed (exit {})'.format(result.returncode))


def differences(expected, actual):
    return sorted(key for key in expected
                  if key not in actual or type(expected[key]) is not type(actual[key])
                  or expected[key] != actual[key])


def snapshot():
    selected = {key: value for key, value in export().items() if managed(key)}
    validate(selected)
    data = plistlib.dumps(selected, fmt=plistlib.FMT_XML, sort_keys=True)
    fd, name = tempfile.mkstemp(prefix='.settings-', dir=str(SNAPSHOT.parent))
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(name, SNAPSHOT)
    print('Snapshot written: ' + str(SNAPSHOT))


def apply(expected):
    require_closed()
    live = export()
    if not differences(expected, live):
        print('Managed preferences already match; nothing imported.')
        return
    merged = dict(live, **expected)
    data = plistlib.dumps(merged, fmt=plistlib.FMT_XML, sort_keys=True)
    directory = Path(tempfile.mkdtemp(prefix='tinycast-backup-', dir='/tmp'))
    os.chmod(directory, 0o700)
    backup = directory / 'backup.plist'
    fd = os.open(str(backup), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(plistlib.dumps(live, fmt=plistlib.FMT_XML, sort_keys=True))
        stream.flush()
        os.fsync(stream.fileno())
    print('Full preference backup: ' + str(backup), flush=True)
    print('Restore with Tinycast closed: {} import {} {}'.format(
        DEFAULTS, DOMAIN, shlex.quote(str(backup))), flush=True)
    require_closed()
    defaults('import', data)
    actual = export()
    if differences(merged, actual) or actual.keys() != merged.keys():
        raise ValueError('Preference readback mismatch; use the printed backup to restore.')
    print('Preferences applied and verified.')


def main(argv=None):
    parser = argparse.ArgumentParser(description='Snapshot, merge, or check Tinycast preferences.')
    parser.add_argument('action', choices=('snapshot', 'apply', 'check'))
    args = parser.parse_args(argv)
    try:
        if args.action == 'snapshot':
            snapshot()
        else:
            expected = decode(SNAPSHOT.read_bytes(), str(SNAPSHOT))
            validate(expected)
            if args.action == 'apply':
                apply(expected)
            else:
                changed = differences(expected, export())
                if changed:
                    print('Managed keys differ: ' + ', '.join(changed))
                    return 1
                print('Managed preferences match.')
    except (OSError, ValueError) as error:
        print('Error: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
