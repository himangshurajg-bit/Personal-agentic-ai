# Local notebook: browse, filter and export

Implemented on the main development branch; existing Python release downloads and the
Android test APK do not gain these features automatically. No model, new dependency,
account, upload, send, device permission or background service is involved.

## Browse in the local interface

Start `python -m agent web`, then use **Browse notes** below the folder-search panel.
An empty filter lists all saved notes, newest first, 20 per page. **Next page** replaces
the visible page rather than accumulating the whole notebook in the browser. Use
**Browse notes** again to restart with a changed filter or see newly saved notes.
Note text is inserted using `textContent`, never as HTML.

## Browse from a terminal

```sh
python -m agent notes
python -m agent notes --query "école" --limit 10
python -m agent notes --limit 10 --before 42
```

Use the preceding response's `next_before` value rather than inventing a cursor.
`has_more` and `next_before` describe continuation, not a total count. Page size is
1–100. Cursors are positive SQLite integer IDs. This is keyset pagination, not a
frozen multi-request snapshot: notes inserted after page one appear when browsing
restarts, not on the older pages. If another program edits/deletes notes, that can
change subsequent results; this feature itself offers no editing or deletion.

Filtering and `find QUERY` now use NFC-normalized Unicode case folding, instead of
SQLite's ASCII-only lower(). `École` matches `école` and decomposed `École`, and
`Straße` matches `STRASSE`. `%` and `_` are literal characters, not SQL wildcards.
This is not fuzzy search, transliteration, accent removal or a language model.
Matching is a local scan, not a full-text index; large notebooks may take longer.

CLI inspection opens the existing database in SQLite read-only mode and does not
create a missing database or change its permissions. Save a first note using
`python -m agent run "remember Practice Python"` before inspecting an empty installation.
The local UI uses the normal database initialization path, like its existing review panel.

## Explicit notes-only JSONL export

```sh
python -m agent export-notes
# Linux/macOS: protect a new output file; noclobber avoids replacing an existing one.
(umask 077; set -C; python -m agent export-notes > notes-backup.jsonl)
```

`--db PATH` goes before the subcommand when using another database. Export prints
one JSON object per line, oldest first, containing only `id`, `text`, and `created_at`.
Newlines/control characters and Unicode are JSON-escaped; decode with a JSON parser
to recover the exact original text. Rows are streamed from one SELECT snapshot,
not loaded into one large Python list. A long export may hold a SQLite read lock.
An empty notebook produces no lines. A missing/unreadable database fails with a
safe JSON error on stderr; check the exit code before treating an export as complete.

The shell creates the destination file, not the agent. The output is plaintext and
can contain personal information. Do not upload it, commit it, store secrets in it,
or confuse it with encrypted storage. Redirecting stdout without `set -C` may
replace an existing file; partial output may remain after an interrupted export.
This is not a full database backup: reviews, draft recipients/text, audit rows and
approval tokens are deliberately excluded. There is no import/restore command.
