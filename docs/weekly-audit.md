# Weekly Audit Log

One entry per run of `.claude/skills/weekly-audit`, newest first, covering Mole CLI (macOS) on `main` and Mole CLI (Windows) on `windows`. The next run reads the newest entry for its commit window (`Next window from`), for the items it must not report again (`Decided, do not re-report`), and rechecks `Open` first. Facts here are a run record; lasting invariants live in `AGENTS.md` on each branch.

## 2026-10-16 (first run)

- Audited: main `eb531ba2`, windows `159657d5`.
- Landed through: main `e78caf97`, windows `9bbebb89` (PR #1751).
- Next window from: main `e78caf97`, windows `9bbebb89`.

### Fixed and verified

| Branch | Finding | Commit | Lock |
| --- | --- | --- | --- |
| main | `mo clean` ran `nix-collect-garbage --delete-older-than`, deleting profile and home-manager generations, with no timeout or owner-planned preview | `c0ea3d48` | `clean_dev_nix collects only unreachable store paths under a timeout` |
| main | Uninstall offered the whole `~/Library/Application Support/Steam` game library as one data row | `6c777967` | `uninstall never offers the Steam library root or anything inside it` |
| windows | `mo remove` recursed through a junction in the config folder into its target | `53b94f11` | `Unlinks a junction in the config folder and keeps its target's files` (CI only, see Open) |
| main | npm cache clean had no owner-command timeout | `22bb8a43` | `clean_dev_npm runs npm cache clean under the owner-command timeout` |
| main | macOS and xrOS DeviceSupport never pruned | `17c74457` | `clean covers every DeviceSupport platform the Xcode uninstall sweep knows` |
| main | Whitelisted Xcode cache entries counted as skipped protected | `ba08ab8f` | `... keeps whitelisted entries out of the skipped count` in `tests/dev_extended.bats` |
| main | `mo uninstall <name>` lowercased per app, `--list` ran `brew info` per cask, report and bundle scans forked per file | `3cc7aa86`, `107d4a83`, `07d78dea` | existing uninstall suites; 9.44 s to 0.059 s and 7.15 s to 2.68 s measured |
| windows | Validated trees walked twice to size | `7b92e1d9` | Windows CI |
| both | Thirteen undocumented tuning env vars on main, `MOLE_ANALYZE_LIVE_SORT` on windows | `654fcef4`, `165d79fd`, `ba791f85` | `removed tuning environment variables are not read again` |
| both | Dead helpers (4 on main, 32 on windows) and two Pester tests that could not fail | `885cb6e0`, `180b62f6`, `754fcb43`, `5904e4d5` | existing suites |
| both | Uncodified oplog contract, recognizer parity, dataless probing, launcher signal stories, nightly-verified issues; stale SYNC release lines, comments and unpinned actions | `5a210db4`, `b9223ebf`, `e78caf97`, `945adbea`, `003157c4` | AGENTS.md, SYNC.md |

### Decided, do not re-report

- macOS and xrOS DeviceSupport get no whitelist rows: only iOS has one, and watchOS, tvOS and visionOS have none either; adding all five clutters the menu.
- `opt_diag_memory_pressure` stays: it prints the memory pressure warning and top processes, so it is not a no-op (an agent claimed otherwise).
- Mole CLI (Windows) writes no operation-log rows in dry runs; recorded as an intentional difference in SYNC.md.
- Existing flags are never proposed for removal without the maintainer.

### Closed after the run (same day)

- windows: `Clear-TempFiles` had three callers but nothing ever registered a temp file, so it only emptied empty lists; removed with its exit event and the two finally blocks in `c6ce917e` (PR #1753).
- windows: the junction test in `53b94f11` is now proven. Restoring the pre-fix `install.ps1` only failed the file at discovery, because the test extracts the new `Remove-MoleConfigEntry`; disabling just its reparse-point branch failed `Unlinks a junction in the config folder and keeps its target's files` on both `powershell` and `pwsh` (draft PR #1754, closed).
- main: GNU coreutils or findutils first in `PATH` aborted `mo clean` (#1752) and silently misread mtimes elsewhere; every `stat` now goes through `$STAT_BSD`, BSD `date -r/-j` through `$_DATE_CMD`, purge's dataless probe and walks through `/usr/bin/find`, and Service Worker discovery uses `-mindepth/-maxdepth` (`c0705ac0`, `66bd98a3`). A source gate refuses new bare forms.
- main: `firmware guard detects a real open file and permits it after close` failed about half the time under the parallel suite because real lsof outlived the 2 s probe budget; the case now runs with 30 s (`420cb224`).

### Open

- None.
