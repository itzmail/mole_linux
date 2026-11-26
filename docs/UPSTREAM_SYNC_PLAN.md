# Upstream Sync & Porting Plan (Mole Linux V1.56.0)

Sync reference: Upstream `tw93/mole` commit range `105663c6..upstream/main`.

## Objectives
Port critical fixes and performance/safety improvements from upstream macOS `mole` into `mole_linux`, skipping macOS-only components (`launchctl`, `plutil`, `LaunchServices`, macOS bundle scanning) and adapting paths/behavior for Linux standards.

---

## Targeted Upstream Patches

### 1. Docker Storage Accounting Fix
- **Upstream Commit**: `d6cd104b`, `c76bec92`
- **Issue**: Docker Engine 29.x (`moby/moby#51775`) reports in-use images as 100% reclaimable.
- **Scope**:
  - `lib/clean/user.sh`: Tambahkan helper `docker_df_review_segment` dan parse column `TotalCount` & `Active`.
  - `tests/clean_user_core.bats`: Unit tests untuk kalkulasi review Docker.

### 2. Dry-Run Nested Candidate Double-Counting Fix
- **Upstream Commit**: `60557607`
- **Issue**: Folder nested (misal `~/.cache` dan `~/.cache/yarn/v6`) dihitung 2x pada estimasi "Potential space" di mode `--dry-run`.
- **Scope**:
  - `bin/clean.sh`: Implementasikan field ke-7 (`covered_by`) pada preview ledger untuk mendeteksi ancestor yang sudah terhitung.
  - `tests/clean_core.bats`: Test deduplikasi nested path di Perl & Bash fallback engines.

### 3. SQLite Open-Handle Probe Timeout Isolation
- **Upstream Commit**: `2b927fff`
- **Issue**: Timeout pada SQLite open-handle check (exit code 124) menyebabkan `MOLE_CLEAN_CANCEL_STATUS=124`, membatalkan seluruh cleanup step berikutnya.
- **Scope**:
  - `lib/core/file_ops.sh`: Return `2` (unknown/keep) khusus untuk timeout tanpa membatalkan seksi clean lainnya.
  - `tests/core_safe_functions.bats`: Test skenario SQLite timeout tidak menghentikan step berikutnya.

### 4. Open-Handle Probe Debug Leak Fix
- **Upstream Commit**: `79f6a92a`
- **Issue**: Saat `mo clean --debug`, trace output dari `run_with_timeout` masuk ke buffer stderr probe lsof, membuat buffer tidak pernah kosong dan mendowngrade status database menjadi "busy".
- **Scope**:
  - `lib/core/file_ops.sh`: Jalankan probe dengan `MO_DEBUG=0`.
  - `tests/core_safe_functions.bats`: Verifikasi status probe konsisten antara `MO_DEBUG=0` dan `MO_DEBUG=1`.

### 5. Minimum Threshold Purge Hints for Build Artifacts
- **Upstream Commit**: `dbb728e7`
- **Issue**: Hint `mo purge` muncul untuk artifact build yang sangat kecil (< 200MB, misal 20KB), menimbulkan noise.
- **Scope**:
  - `lib/clean/hints.sh`: Tambahkan batasan floor 204800 KB (200MB) sebelum menampilkan baris hint.
  - `tests/clean_hints.bats`: Test verifikasi keheningan di bawah 200MB dan tampil di atas 200MB.

### 6. Status TUI Process Card: Drop Zombie Line
- **Upstream Commit**: `0ef945bb`
- **Issue**: Baris Zombie di card `Processes` memakan 1 slot dari 3 slot proses teratas.
- **Scope**:
  - `cmd/status/view.go`: Hapus `renderProcessCardWithZombies`, pertahankan 3 baris proses teratas (zombie metrics tetap ada di output `--json`).
  - `cmd/status/view_test.go`: Sesuaikan pengujian unit TUI.

### 7. Config Root Safety in `mo remove`
- **Upstream Commit**: `32364826`, `52643d00`
- **Issue**: Jika instalasi custom ditempatkan di direktori bersama (seperti `~/.local`), `mo remove` berisiko menghapus data luar jika salah mendeteksi kepemilikan direktori.
- **Scope**:
  - `lib/manage/remove.sh`: Batasi penghapusan penuh hanya pada `~/.config/mole`. Untuk custom path, beri status "kept for manual review".
  - `tests/uninstall.bats`: Test skenario custom config directory.

### 8. Update Channel Receipt Precedence
- **Upstream Commit**: `7ae16e27`
- **Issue**: `get_install_channel` mendahulukan default config dibanding `SCRIPT_DIR/install_channel`.
- **Scope**:
  - `lib/manage/update.sh`: Dahulukan `$SCRIPT_DIR/install_channel` atau `$MOLE_CONFIG_DIR`.
  - `tests/update.bats`: Test verifikasi prioritas receipt.

### 9. Test Runner `TERM=dumb` Compatibility
- **Upstream Commit**: `7d676b26`
- **Scope**:
  - `scripts/test.sh`: Fallback `TERM="xterm-256color"` jika `TERM` kosong atau `dumb`.

---

## Execution Phases

1. **Phase 1: Core Shell Fixes & Safety** (Items 3, 4, 7, 8, 9)
2. **Phase 2: Cleanup Accounting & Hints** (Items 1, 2, 5)
3. **Phase 3: Go Status TUI Refactor** (Item 6)
4. **Phase 4: Verification & Release Prep**
   - Jalankan `make verify`, `make test-go`, dan `./scripts/check.sh --format`.
   - Update `docs/release-notes/V1.56.0.md` dan bump versi ke `1.56.0`.
