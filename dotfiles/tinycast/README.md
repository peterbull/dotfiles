# Tinycast preferences

Personal preferences captured from Tinycast **0.11.12**. Use the same version on
both Macs when possible. This standalone macOS helper uses the standard library
in `/usr/bin/python3` (tested with Python 3.9.6). It needs no Pi, packages, or
automatic installs. Install Tinycast and the apps targeted by shortcuts yourself.

## Restore on the home Mac

After you transfer these files, install Tinycast and close it before applying:

```sh
/usr/bin/python3 ~/dotfiles/tinycast/settings.py apply
/usr/bin/python3 ~/dotfiles/tinycast/settings.py check
open -a Tinycast
```

## Capture changes on the work Mac

Run this only on the Mac whose settings you want to keep, then review the Git diff:

```sh
/usr/bin/python3 ~/dotfiles/tinycast/settings.py snapshot
git -C ~ diff -- dotfiles/tinycast/settings.plist
```

Do not run `snapshot` on the home Mac before restoring. It replaces the saved
work-Mac settings with the home Mac's current preferences.

- `check` reads only. It compares managed keys, prints differing key names without
  values, and exits 1 for differences or errors.
- `snapshot` exports `com.tinycast.app`, filters and validates it, then atomically
  overwrites this directory's `settings.plist` with sorted XML. Run it explicitly
  only when you intend to replace the tracked snapshot. Tinycast may remain open.
- `apply` validates the entire snapshot before any preference action. **Close
  Tinycast manually first**, then run `apply` and reopen it with `open -a Tinycast`.
  The helper checks that Tinycast is closed again immediately before import.

`settings.plist` is a personal preferences source, never a symlink into
`~/Library/Preferences`. The helper locates it relative to its own script, not the
current directory. There is no fully automatic ongoing sync.

## Included

Only these keys are managed:

- `boundAppBundleIDs` and `favoriteApps`: string arrays.
- `calendarMenuBarDisplay`: integer.
- `quicklinksEnabled` and `showInMenuBar`: booleans.
- `hotkey.togglePalette`, `hotkey.app.<nonempty target>`, and
  `hotkey.command:<nonempty target>`: strings containing valid JSON objects.

Command hotkeys contain bindings only, not command definitions. For example, the
clipboard-history shortcut does not copy clipboard contents. Enabling quicklinks
does not copy quicklink data.

No secrets, AI/MCP settings, Keychain items, clipboard contents, chats, notes,
snippets, custom command definitions, quicklink data, empty `boundCustom*` arrays,
or `NS*` machine preferences are copied into the snapshot. All other keys are
excluded; unknown snapshot keys or invalid types cause an error.

## Merge and recovery

`apply` merges managed values into the full live dictionary. It does not remove
other hotkeys or settings, including keys absent from the snapshot. If managed
values already match, it skips import and backup. A fresh empty domain is valid.

Before a changed import, the helper saves the full live preferences outside Git
in `/tmp/tinycast-backup-*/backup.plist` (on macOS, `/tmp` resolves to
`/private/tmp`). The directory has mode `0700`; the file has mode `0600`. **This
full backup can contain private data. Do not add it to Git or share it.**

The helper prints the backup path and an exact recovery command:

```sh
/usr/bin/defaults import com.tinycast.app /tmp/tinycast-backup-EXAMPLE/backup.plist
```

Use the printed path, with Tinycast closed. Recovery restores the full domain,
not just managed keys. Reopen Tinycast afterward. Backups are retained for manual
recovery; the helper does not automatically restore or delete them.

Import uses the merged plist on stdin. The helper then exports the domain again
and checks the full dictionary, including unmanaged keys. A command failure,
malformed export, or readback mismatch exits 1 with an explicit error. An error
after import can mean preferences changed; use the printed backup to recover.
