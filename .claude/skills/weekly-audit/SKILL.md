---
name: weekly-audit
description: >-
  Weekly whole-repo audit of Mole CLI (macOS, main) and Mole CLI (Windows, the
  windows branch) across five dimensions (unsafe, over-design, stale,
  performance, not yet codified), every finding refuted once before it is
  reported, then the approved fixes landed per branch. Use for 每周体检, 全面检查
  CLI, 看看 Mole 和 Windows 版还有什么要优化 / 沉淀 / 不安全 / 过度设计 / 过时.
  Not for one reported bug (/hunt), a safety-sensitive diff (bugs), or a PR
  review (/check).
metadata:
  version: "1.1.0"
---

# Weekly Audit (CLI)

Adapted from Mole Mac's weekly audit (mole-mac `.claude/skills/weekly-audit`).
The first run (2026-10-16, main `eb531ba2`, windows `159657d5`) found `mo clean`
deleting Nix profile generations older than 30 days with no timeout or real
preview, the whole `~/Library/Application Support/Steam` game library offered as
one uninstall data row on macOS while Windows already refuses Steam libraries,
a dozen undocumented tuning variables, dead Windows cleanup stubs with tests that
cannot fail, per-app forks in `mo uninstall <name>` and `--list`, and five stale
release lines. Most of the tree was fine; the value is in the few findings that
survive refutation. Run it once a week and keep the report short.

## Phase 1: Freeze and scope

- For each branch record `git rev-parse HEAD`, the remote head, `git status
  --short`, and `git log --oneline <base>..HEAD`. `main` is this checkout; `windows`
  is its own worktree (`git worktree list`), never checked out over `main`. Fetch
  the remote branch read-only (`git fetch origin windows`) and audit
  `origin/windows` when no clean worktree is at its head.
- Read the newest entry of `docs/weekly-audit.md` on `main`: its "Next window
  from" commits are this run's base per branch, its "Decided, do not re-report"
  list goes to every agent, and its "Open" items are rechecked first. The codify
  dimension reads only that window; the others read the whole tree.
- Exclude `tests/tmp-*`, `.git`, build output and other sessions' worktrees from
  every grep.
- Pick the scope. Both branches whole on the first run, after a release, or when the
  window touched more than about 40 source files; otherwise incremental: the files
  changed in each branch's window, their direct callers, and every Open item. Mole
  for Windows' first whole-tree run cost about 1.15M sub-agent tokens for 18 findings,
  most in code untouched for weeks.
- Read-only until Phase 4. "看看 / 检查 / 跑一遍" never authorizes a write.

## Phase 2: Five read-only audits in parallel

One sub-agent per dimension, each started from the matching prompt in
`references/prompts.md` (shared header plus dimension body) so coverage does not
drift between runs, each covering both branches and naming which branch
every finding belongs to. Read-only: no edit, commit, build, real cleanup or
`sudo`. Tests may run only with `MOLE_TEST_NO_AUTH=1` against fixtures; PowerShell
behavior cannot run on macOS, so Windows findings rest on reading the code and its
Pester tests. Each agent must try to refute every candidate once (find the guard
that already blocks it, the test that locks it, or the AGENTS.md / SYNC.md line
recording the decision, which may sit on the other branch, so grep both before
reporting) and report only survivors, with `branch:file:line`, a concrete failure
scenario and the smallest fix.

1. **Unsafe.** macOS: every removal goes through `mole_delete` / `safe_clean` /
   `safe_remove` or carries a same-line `# SAFE:` reason; matching stays on exact
   bundle IDs or paths (no vendor prefix, TeamID or common-word globs); timeouts
   mean unknown and keep the target, signals cancel; dry-run lists exactly what a
   real run would remove; every `sudo`, `osascript` and `launchctl` has a test-mode
   guard; owner commands (`brew`, `go clean`, `simctl`, npm) cannot mutate an
   unwhitelisted root. Windows: every removal goes through `Remove-Safe*` /
   `Clear-DirectoryContents` and `Test-SafePath`; junction and identity rechecks
   before the sink; uninstall leftovers only after `Test-MoleInstallFolder`.
   Both: hunt for the Steam shape, a folder of irreplaceable user content (game
   libraries, VMs, model weights, local-only chat or clipboard databases, sessions)
   reachable as one cleanup or uninstall target. Do not stop at reading: run
   `find_app_files <bundle-id> <name>` against a fixture `HOME` for launchers that
   hold such content (Steam, Epic, GOG, Battle.net, Parallels, UTM, Ollama, LM
   Studio) and check what `should_protect_data` says; the first run's Steam row
   was missed by reading alone. List every `clean_tool_cache` owner command and
   check it has `run_with_timeout`, a dry-run that plans with the owner, and a
   recovery contract that only removes rebuildable state (Nix generations are not).
2. **Over-design.** New flags, environment variables or config keys added without
   a stated rejected default (AGENTS.md treats each as a setting); zero-caller
   functions (grep strings, `eval`, `declare -f` and dynamic names too; tests
   alone are not callers); same-body helpers `scripts/audit_function_duplication.py
   --list` misses because they are written differently; output lines that report
   routine skips. Existing flags are never proposed for removal without the
   maintainer.
3. **Stale.** Current-state claims in AGENTS.md (both branches), SYNC.md,
   `.claude/skills/**`, docs and README copies against the code: every test named
   as a lock exists (`grep -rn '@test "<name>"' tests` on main, `It '<name>'` in
   Pester on windows), versions, paths, make targets and commands still exist,
   comments naming removed functions. The "latest stable" and "not released"
   lines in SYNC.md on both branches go stale with every release; check them
   against `gh release list` first. These files deliberately record removed and
   rejected things; read the context before calling a line stale.
4. **Performance.** Forks per item inside loops that scale with app or file count
   (`basename`, `tr`, `$(...)`, `stat` per entry), repeated `du` or `find` over the
   same root, `mdfind` / `system_profiler` / `pgrep` calls not shared within a run,
   unbounded waits, startup work on every command. Tie each to a count or a
   measured time, and check whether it is already cached, pooled or gated by a
   test such as `tests/core_performance.bats`.
5. **Not yet codified.** In the commit window: an area fixed twice, a behavior
   fix with no test touched, a lesson living only in memory, an issue reply or
   one commit message, a rule repeated in several places or grown past use, and
   fixes on one branch that SYNC.md should route to the other (a safety or
   correctness contract the other CLI shares) without a row there.

## Phase 3: Report

One merged report, ranked by risk: unsafe, codify, performance, over-design,
stale. Each row: branch, what, where, evidence, smallest fix, and whether it
needs the maintainer (user-visible behavior, a new or removed flag, a recorded
decision, a release). Verify the weakest high-severity claim yourself before
reporting it: read the code, or reproduce with a fixture `HOME` and
`MOLE_TEST_NO_AUTH=1`. End with what was checked and found fine, and the
questions only the maintainer can answer. Mole for Windows (the paid app) and
Mole Mac are out of scope here; note a cross-product item only as a SYNC.md
candidate.

## Phase 4: Land what the maintainer approves

- One detached worktree per fix family (`git worktree add --detach <dir>/wt-<n>
  origin/main`, or `origin/windows`; no side branches, the maintainer works on main
  and windows), no two agents on the same file, local commits only. Start each
  agent from the fix header in `references/prompts.md`. Do not put a worktree you run Bats in under
  `/private/tmp`: `validate_path_for_deletion` allows that tree before
  `should_protect_path`, so sink tests there fail on clean code (the first run's
  agents each reported three such false reds). Stack and run the full suite in
  the main checkout.
- Every behavior fix carries a test that fails on the old code (red-run by
  restoring the old source in the worktree) and, when it states a new invariant,
  the AGENTS.md line on that branch.
- macOS: `./scripts/check.sh --no-format`, shellcheck on changed tests, then the
  full `TERM=xterm-256color MOLE_TEST_NO_AUTH=1 ./scripts/test.sh` on the stacked
  result before pushing `main`. Windows: `gofmt -l cmd`, `GOOS=windows go build
  ./cmd/...` locally, and the Windows CI result on a pushed branch or PR, because
  Pester cannot run here; never report a Windows fix as verified from macOS alone.
  Red-run on CI: push the test-only commit to the draft PR first, wait for the
  Pester job to fail on it under both `powershell` and `pwsh` (or name the shell
  that stays green and why), then push the fix. When the test reaches into a
  helper the fix introduced (Pester extracting a function from the script),
  restoring the old file fails the whole test file at discovery, which proves
  nothing; break only the judged condition in the new code instead and check
  that exactly that `It` fails. The first run's junction test was proven that
  way after the fact (draft PR #1754).
- Agent reports are leads. Before stacking, read each agent's deviations from its
  brief and accept or undo each one, verify every "this does nothing" or "baseline
  already fails" claim yourself, and close each agent's "not done / outside my
  files" list in the integration commit. In the first run one agent called
  `opt_diag_memory_pressure` a no-op (it prints a warning) and three reported
  `/private/tmp` false reds as baseline failures.
- Items marked "needs maintainer: no" are fixed in the run that reports them once
  the maintainer approves the batch; only items waiting on a decision carry over in
  Open, each with the question it waits on.
- Commit identity and push follow the global Git Safety rules; contributor PRs
  keep their own review path.
- Prepend the run to `docs/weekly-audit.md` (audited and landed commits per
  branch, next window, fixed / decided / open) in the last `main` commit of the
  run.

## Output

The report, then after landing: commits per branch, push status, worktree
leftovers, each finding's state (fixed and verified / decided not to fix with
reason / blocked and what is missing), and each branch's base commit for next
week's window, all also written to `docs/weekly-audit.md`.
