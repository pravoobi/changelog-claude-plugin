---
description: Undo the last automatic changelog write — restores CHANGELOG.md from the backup created before the last auto-update or release.
---

# /changelog:undo

Revert `CHANGELOG.md` to the state it was in before the last automatic write or release.

## Steps

### 1. Check for backup

Check whether `.changelog/backups/CHANGELOG.md.bak` exists.

If not, tell the user there is no backup to restore and stop.

### 2. Show the diff

Read both the current `CHANGELOG.md` and the backup `.changelog/backups/CHANGELOG.md.bak`.

Show the user a summary of what will be reverted (what entries would be removed).

Ask: "Restore CHANGELOG.md from backup? This will undo the last auto-write or release."

If the user says no, stop without changing anything.

### 3. Restore

Copy the backup content back to `CHANGELOG.md` (overwrite the current file).

Remove `.changelog/backups/CHANGELOG.md.bak` after a successful restore.

### 4. Report

Tell the user that `CHANGELOG.md` has been restored. Let them know that if they want
to redo the write, they can run `/changelog:sync`.
