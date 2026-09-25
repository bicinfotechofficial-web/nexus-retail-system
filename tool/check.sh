#!/usr/bin/env bash
# CI gate for the whole workspace: resolve, boundaries, format, analyze, test.
#
#   tool/check.sh          everything except emulator suites
#   tool/check.sh --fix    format files in place instead of failing on them
#   tool/check.sh --e2e    also run test/e2e and firebase/ rules tests
#                          (needs `firebase emulators:start` running, see C-4)
#
# Runs on Linux, macOS and Git Bash on Windows. Exit code 0 means green.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX=0
E2E=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --e2e) E2E=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Workspace members, in dependency order. Keep in sync with pubspec.yaml.
MEMBERS=(packages/core packages/data packages/printer apps/pos apps/admin test/e2e)
# Pure Dart members. They must never depend on Flutter.
PURE_DART=(packages/core test/e2e)
# Money logic in packages/core must keep >= 95% line coverage (C-3).
COVERAGE_MIN=95
COVERAGE_FILES=(
  lib/src/money.dart
  lib/src/bill_calculator.dart
  lib/src/return_calculator.dart
  lib/src/summary_delta.dart
)

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Prints line coverage for each gated file and fails below COVERAGE_MIN.
check_coverage() {
  local lcov="$1" f pct
  for f in "${COVERAGE_FILES[@]}"; do
    pct=$(awk -v want="$f" '
      /^SF:/ { cur = substr($0, 4); gsub(/\\/, "/", cur); on = (cur ~ want "$") }
      on && /^DA:/ { split(substr($0, 4), a, ","); total++; if (a[2] > 0) hit++ }
      END { if (total == 0) print "none"; else printf "%.1f", 100 * hit / total }
    ' "$lcov")
    [[ "$pct" != none ]] || fail "no coverage data for packages/core/$f"
    printf '   coverage %5s%%  %s\n' "$pct" "$f"
    awk -v p="$pct" -v min="$COVERAGE_MIN" 'BEGIN { exit !(p >= min) }' \
      || fail "packages/core/$f is below ${COVERAGE_MIN}% line coverage"
  done
}

command -v flutter >/dev/null || fail "flutter is not on PATH (see B-3)"

step "Resolve dependencies"
flutter pub get >/dev/null

step "Check package boundaries"
for m in "${MEMBERS[@]}"; do
  [[ -f "$m/pubspec.yaml" ]] || fail "$m/pubspec.yaml is missing"
  grep -q '^resolution: workspace' "$m/pubspec.yaml" \
    || fail "$m must declare 'resolution: workspace'"
  [[ ! -f "$m/analysis_options.yaml" ]] \
    || fail "$m has its own analysis_options.yaml; use the root one"
done
for m in "${PURE_DART[@]}"; do
  ! grep -Eq 'sdk: *flutter' "$m/pubspec.yaml" \
    || fail "$m is pure Dart and must not depend on Flutter"
done
for m in packages/*/; do
  ! grep -Eq 'nexus_(pos|admin):' "$m/pubspec.yaml" \
    || fail "${m%/} must not depend on an app"
done
! grep -Eq 'nexus_(data|printer|pos|admin):' packages/core/pubspec.yaml \
  || fail "packages/core must not depend on other workspace members"
echo "ok"

step "Format"
# Generated files are excluded from formatting and analysis.
mapfile -t DART_FILES < <(
  find packages apps test tool -name '*.dart' \
    -not -path '*/.dart_tool/*' -not -path '*/build/*' \
    -not -name '*.g.dart' -not -name '*.freezed.dart' \
    -not -name 'firebase_options.dart' | sort
)
if [[ ${#DART_FILES[@]} -gt 0 ]]; then
  if [[ $FIX -eq 1 ]]; then
    dart format "${DART_FILES[@]}"
  else
    dart format --output=none --set-exit-if-changed "${DART_FILES[@]}" \
      || fail "unformatted files; run tool/check.sh --fix"
  fi
fi

step "Analyze"
flutter analyze --no-pub --fatal-infos --fatal-warnings

step "Test"
for m in "${MEMBERS[@]}"; do
  if [[ "$m" == test/e2e && $E2E -eq 0 ]]; then
    echo "-- $m: skipped (use --e2e)"
    continue
  fi
  if [[ ! -d "$m/test" ]]; then
    echo "-- $m: no tests yet"
    continue
  fi
  echo "-- $m"
  if grep -Eq 'sdk: *flutter' "$m/pubspec.yaml"; then
    (cd "$m" && flutter test --no-pub --reporter=compact)
  elif [[ "$m" == packages/core ]]; then
    (cd "$m" && rm -rf .dart_tool/coverage \
      && dart test --reporter=compact --coverage=.dart_tool/coverage \
      && dart run coverage:format_coverage --lcov --report-on=lib \
        --in=.dart_tool/coverage --out=.dart_tool/coverage/lcov.info >/dev/null)
    check_coverage "$m/.dart_tool/coverage/lcov.info"
  else
    (cd "$m" && dart test --reporter=compact)
  fi
done

if [[ $E2E -eq 1 && -f firebase/package.json ]]; then
  echo "-- firebase (rules tests)"
  (cd firebase && npm test)
fi

printf '\nAll checks passed.\n'
