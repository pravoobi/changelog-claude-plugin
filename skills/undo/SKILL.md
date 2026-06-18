---
description: Undo the last automatic changelog write or release — lists available backups and restores the one you choose.
---

# /changelog:undo

Revert `CHANGELOG.md` to a previous state using a backup from `.changelog/backups/`.

## Steps

### 1. List available backups

Read all files matching `.changelog/backups/CHANGELOG.md.*.bak`, sorted newest first.

If no backups exist, tell the user there is nothing to restore and stop.

### 2. Show options

Display the backups with their timestamps so the user can identify which to restore:

```
Available backups (newest first):
  1. CHANGELOG.md.2026-06-18T09-30-00Z.bak  (most recent — last auto-write)
  2. CHANGELOG.md.2026-06-18T08-15-00Z.bak
  3. CHANGELOG.md.2026-06-17T17-45-00Z.bak
```

If there is only one backup, skip the selection step and confirm directly:
"Restore from the only available backup (CHANGELOG.md.2026-06-18T09-30-00Z.bak)?"

### 3. Confirm

Ask the user which backup to restore (default: the most recent one).
Show a brief summary of what will be reverted — specifically what entries will be removed
or changed compared to the current CHANGELOG.md.

If the user says no or cancels, stop without changing anything.

### 4. Restore

Overwrite `CHANGELOG.md` with the chosen backup's content.

Do NOT delete the backup files after restoring — the user may want to redo or pick
a different backup. Let them manage cleanup manually.

### 5. Report

Confirm which backup was restored and remind the user that:
- `/changelog:sync` will re-generate entries from the current git diff
- Other backups are still available in `.changelog/backups/` if needed
