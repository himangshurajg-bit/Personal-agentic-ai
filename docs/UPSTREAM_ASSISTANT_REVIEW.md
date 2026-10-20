# Upstream assistant comparison and bounded local file search

Reviewed 20 October 2026 for the requested upstream-assistant feature adaptation. The target remains
Personal-agentic-ai; this is not a wholesale import, Windows assistant install or APK.

## Source identity and what was actually inspectable

- Source repository identity: GitHub repository ID `1258466758`, owned by
  `codeninjavik`. Its API record is
  <https://api.github.com/repositories/1258466758>. This stable numeric reference
  preserves the reviewed source identity without using its product name.
- Main inspected at `4f8cd94385274dde8b8eea02834b93ae08471b5e`.
  Its complete tree contained README, LICENSE, .gitignore and five images, not the
  Python modules/project structure illustrated in the README.
- The other listed branch, `terminal_output`, at
  `cc9d80d9060c808a78a15b4ca885867110ee9f62`, also contained documentation/images only.
  The GitHub releases API returned no releases at review time.
- The repository's documented installation points to its related PyPI distribution.
  Inspected its published version 0.3.3 wheel as a ZIP, without installing,
  importing, executing or decompiling it. The artifact is identified by the digest
  below; the package's product name is omitted from this comparison.
  The wheel SHA-256, computed locally and matched against PyPI metadata, was
  `a1c68b27e3d978dec7ed4e4306d30110a25680a0fd37c3d41b2477921afd99aa`.
- That artifact is `cp311-cp311-win_amd64`: the desktop/voice/vision modules are
  compiled Windows Python 3.11 extensions. Their behavior was **not** verified.
  The artifact also bundles inspectable JavaScript in its bundled coding-tool distribution directory.
  This is a related published artifact, not code present in the GitHub main tree.

## License/provenance issue: no direct code or asset copying

The GitHub LICENSE contains GNU GPL version 3 and GitHub detects GPL-3.0, while its
README says MIT. The PyPI wheel carries a modified MIT-style notice requiring creator
attribution, and the bundled coding-tool package identifies HunterCode as its upstream
and declares MIT. These observations are not a resolved unified licensing/provenance
chain. GPL code is not inherently unusable, but its obligations cannot be ignored or
silently represented as this target's MIT-only code. The desktop source was also absent
from the inspected GitHub branches.

No reviewed upstream source, binaries, images, fonts, data or dependencies are included in
this change. The target LICENSE is unchanged. The implemented feature below is written
independently for this project's needs; sources are credited for the comparison, not
presented as a transferred implementation. Direct copying would first require the exact
source and applicable notices/provenance to be resolved. No activation or premium access
was bypassed.

## Comparison against actual bundled JavaScript

Component paths below are relative to the bundled coding-tool distribution directory;
its product-named directory prefix is omitted. This is a comparison, not copied code.

| Inspected component | Observed implementation | Decision for this starter |
|---|---|---|
| `tools/grep.js` | Recursive, case-insensitive JavaScript regex search; line-numbered matches, 200-result cap, binary NUL skip and ignored build dirs | Useful idea: local text search. Independently implement literal matching with explicit root and byte/entry/depth limits; no regex, model path selection or shell. |
| `tools/list_files.js` | Recursive directory listing; 500-entry and depth-5 limits; shared ignored-directory set | Use bounded traversal as a design requirement, not copied code. Do not add a separate browser/indexing service. |
| `tools/read_file.js` | Reads a whole UTF-8 file then slices numbered lines | Do not import unrestricted path reads or full-file loading; return bounded matching excerpts only. |
| `tools/run_bash.js` | Shell subprocesses; a destructive-command pattern list invokes confirmation | Do not import a general shell or pattern-based safety gate. Existing exact-action reviews and lack of an external executor remain intact. |
| Desktop voice, device controls, messaging and vision | README claims and compiled module names; no inspectable desktop implementation verified | Not ported or advertised as working here. No microphone, camera, accounts or background autostart enabled. |

The distribution lists broad dependencies for Qt/WebEngine, audio, camera, Windows
controls, networking and service clients, with mostly lower-bound-only version constraints.
Importing the application would add substantial platform, dependency and permission scope.
The independent search feature needs only Python's standard library and none of these
third-party assets or runtime dependencies. No claims are made about the security of
unexecuted compiled modules.

## New working feature

```sh
python -m agent files "approval" --root ./docs
python -m agent files "Newton" --root /path/to/your/study-notes
```

`files` is a separate, explicit local CLI command, not a model-plan tool. `--root` is
required every time. It does not invoke a provider, create/open the memory database,
send results anywhere, index the device, or persist search results. Even with cloud
credentials configured, this command does not contact a model. JSON output includes
relative path, one-based line number, matching-line excerpt, scan counts and limits.
File contents are untrusted data, never action instructions.

### Scope and limits

- Literal case-insensitive Unicode matching, not regex or semantic search. Query length
  is 1–200 nonblank characters, on one line.
- Only UTF-8 `.txt`, `.md`, `.rst`, `.py`, `.js`, `.ts`, `.jsx`, `.tsx`, `.html` and `.css`.
  Other extensions, invalid UTF-8, NUL-containing binary data and files over 64 KiB are skipped.
- Hidden entries, common build/dependency/cache dirs, and names containing common sensitive
  words (`secret`, `credential`, `password`, `token`, `private_key`) are skipped. This is
  **not** secret detection or a guarantee that an eligible file contains no private data.
  Choose a directory you intend to read; don't choose your whole home or system directory.
- Up to 1,000 entries, 100 successfully decoded files, depth 5 below root, 2 MiB of reads
  plus one byte for oversize detection, and 20 matching lines. Excerpts show at most the
  first 240 characters of each matching line; `text_truncated` indicates clipping.
- `limit_reached` is conservative: reaching a cap can mark it even if no more matches exist.
  An empty result means no match in scanned eligible files, not absence elsewhere.
  `skipped_files` also counts skipped entries/directories, not only regular files.
- Directory-relative descriptors and no-follow opens skip symlink files/directories,
  including a child replaced by a symlink between inspection and open. FIFOs/devices are
  not read. This requires the corresponding OS primitives; unsupported platforms fail
  closed with a structured error. Tested on Linux only. No Windows, Android or macOS
  compatibility claim is made for this feature.
- This is a trusted-local-workspace utility, not a security sandbox against a hostile OS
  user, mount/hard-link manipulation or network-filesystem stalls. Byte/count bounds are
  not a hard wall-clock deadline. Files may change while being read.

Read results are not automatically fed to a model. Integrating file reads into a future
planner requires a separate, owner-bound workspace capability and explicit disclosure
policy; a model must not select its own filesystem root. Existing draft approval,
expiry, payload binding, single-use and no-uncertain-retry controls are unchanged.

See [the verification record](VERIFICATION.md) for feature and regression test receipts.
