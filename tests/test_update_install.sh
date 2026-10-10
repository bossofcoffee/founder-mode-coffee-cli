#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir -p "$TEST_TMP/package" "$TEST_TMP/bin"
printf '#!/usr/bin/env bash\nprintf "founder-mode-coffee 2.4.0\\n"\n' > "$TEST_TMP/package/founder-mode-coffee"
tar -czf "$TEST_TMP/release.tar.gz" -C "$TEST_TMP/package" founder-mode-coffee
cp "$ROOT/founder-mode-coffee" "$TEST_TMP/bin/founder-mode-coffee"
PATH="$ROOT/tests/update-fixtures:$PATH" MOCK_UPDATE_ARCHIVE="$TEST_TMP/release.tar.gz" "$TEST_TMP/bin/founder-mode-coffee" update --install
[[ "$("$TEST_TMP/bin/founder-mode-coffee" --version)" == 'founder-mode-coffee 2.4.0' ]]
printf 'PASS: verified self-update replaces the invoked executable\n'
cp "$ROOT/founder-mode-coffee" "$TEST_TMP/bin/founder-mode-coffee"
if PATH="$ROOT/tests/update-fixtures:$PATH" MOCK_UPDATE_ARCHIVE="$TEST_TMP/release.tar.gz" MOCK_CORRUPT=1 "$TEST_TMP/bin/founder-mode-coffee" update --install > "$TEST_TMP/corrupt.out" 2>&1; then
  printf 'FAIL: corrupt update succeeded\n' >&2; exit 1
fi
cmp "$ROOT/founder-mode-coffee" "$TEST_TMP/bin/founder-mode-coffee"
printf 'PASS: corrupt update retains the previous executable\n'
ln -s "$TEST_TMP/bin/founder-mode-coffee" "$TEST_TMP/bin/managed-cli"
if PATH="$ROOT/tests/update-fixtures:$PATH" MOCK_UPDATE_ARCHIVE="$TEST_TMP/release.tar.gz" "$TEST_TMP/bin/managed-cli" update --install > "$TEST_TMP/symlink.out" 2>&1; then
  printf 'FAIL: managed symlink was overwritten\n' >&2; exit 1
fi
[[ -L "$TEST_TMP/bin/managed-cli" ]]
cmp "$ROOT/founder-mode-coffee" "$TEST_TMP/bin/founder-mode-coffee"
printf 'PASS: managed symlink is never overwritten\n'
mkdir -p "$TEST_TMP/Cellar/pkg/2.3.0/bin"
cp "$ROOT/founder-mode-coffee" "$TEST_TMP/Cellar/pkg/2.3.0/bin/founder-mode-coffee"
ln -s "$TEST_TMP/Cellar/pkg/2.3.0/bin" "$TEST_TMP/managed-directory"
if PATH="$ROOT/tests/update-fixtures:$PATH" MOCK_UPDATE_ARCHIVE="$TEST_TMP/release.tar.gz" "$TEST_TMP/managed-directory/founder-mode-coffee" update --install > "$TEST_TMP/managed-directory.out" 2>&1; then
  printf 'FAIL: managed directory alias was overwritten\n' >&2; exit 1
fi
cmp "$ROOT/founder-mode-coffee" "$TEST_TMP/Cellar/pkg/2.3.0/bin/founder-mode-coffee"
printf 'PASS: canonical managed directories are protected\n'
for marker in directory file; do
  source_dir="$TEST_TMP/source-$marker"
  mkdir -p "$source_dir"
  cp "$ROOT/founder-mode-coffee" "$source_dir/founder-mode-coffee"
  if [[ "$marker" == directory ]]; then
    mkdir "$source_dir/.git"
  else
    printf 'gitdir: ../worktree-metadata\n' > "$source_dir/.git"
  fi
  if PATH="$ROOT/tests/update-fixtures:$PATH" MOCK_UPDATE_ARCHIVE="$TEST_TMP/release.tar.gz" "$source_dir/founder-mode-coffee" update --install > "$TEST_TMP/source-$marker.out" 2>&1; then
    printf 'FAIL: source checkout with .git %s was overwritten\n' "$marker" >&2; exit 1
  fi
  cmp "$ROOT/founder-mode-coffee" "$source_dir/founder-mode-coffee"
  printf 'PASS: source checkout with .git %s is protected\n' "$marker"
done
