#!/usr/bin/env bash
# Tests the "Preserve changelog history" step of module_release_prep.yml.
# The step's `run:` block is extracted from the workflow and executed in a
# throwaway git repo whose working-tree CHANGELOG.md simulates gh-changelog output.
# Requires python3 with PyYAML.
# Usage: tests/module_release_prep/test_changelog_guard.sh
# No -e on purpose: run_case counts failures instead of aborting on the first one.
set -u
# The cases create their own repos, so ignore a surrounding one (e.g. when run from a git hook)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# Keep the developer's git config (e.g. core.autocrlf) out of the fixtures
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/module_release_prep.yml"
step_name="Preserve changelog history"
failures=0

python3 -c 'import yaml' 2> /dev/null || { echo "python3 with PyYAML is required"; exit 2; }

fx=$(mktemp -d) || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$fx"' EXIT

# The cases below supply VERSION themselves, so check that the workflow does:
# every step that needs it reads it from inputs.version, and no step interpolates
# inputs.version or github.event.inputs into a script.
if python3 - "$workflow" <<'PY'
import sys, yaml
text = open(sys.argv[1]).read()
steps = yaml.safe_load(text)["jobs"]["release_prep"]["steps"]
for name in ("Generate changelog", "Preserve changelog history", "Update metadata.json"):
    step = next(s for s in steps if s.get("name") == name)
    assert step["env"]["VERSION"] == "${{ inputs.version }}", name
    assert "${{" not in step["run"], name + " interpolates an expression into the script"
    assert "VERSION" in step["run"], name + " does not use VERSION"
for step in steps:
    assert "inputs.version" not in step.get("run", ""), step.get("name")
names = [s.get("name") for s in steps]
assert names.index("Generate changelog") < names.index("Preserve changelog history") < names.index("Update metadata.json"), "step order"
preserve = steps[names.index("Preserve changelog history")]
assert "if" not in preserve and "continue-on-error" not in preserve, "the guard must always run and fail the job"
assert '"v${VERSION#v}"' in steps[names.index("Generate changelog")]["run"]
assert "${VERSION#v}" in steps[names.index("Update metadata.json")]["run"]
assert "github.event.inputs" not in text
PY
then echo "PASS: VERSION is wired from inputs.version"
else echo "FAIL: VERSION is not wired from inputs.version"; failures=$((failures + 1)); fi

python3 - "$workflow" "$step_name" > "$fx/step.sh" <<'PY' || { echo "step '$step_name' not found in $workflow"; exit 2; }
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for step in wf["jobs"]["release_prep"]["steps"]:
    if step.get("name") == sys.argv[2]:
        print(step["run"])
        sys.exit(0)
sys.exit(1)
PY

# run_case <name> <committed changelog file|-> <generated changelog file> <expected changelog file> [pass|fail] [<pattern>]
# With "fail" the step must exit non-zero and leave the generated file as is.
# With a <pattern> (for pass or fail) the step output must also contain it.
# The version being prepared is $case_version.
# The step runs with `bash -e` (the Actions default) and again with pipefail.
run_case() {
  local name=$1 old=$2 generated=$3 expected=$4 expect=${5:-pass} pattern=${6:-} flags dir rc ok
  for flags in -e -eo\ pipefail; do
    dir=$(mktemp -d) || { echo "mktemp failed"; exit 2; }
    (
      cd "$dir" || exit 1
      git init -q . && git config user.email t@example.com && git config user.name t || exit 1
      if [ "$old" != "-" ]; then
        cp "$old" CHANGELOG.md && git add CHANGELOG.md
      else
        : > .keep && git add .keep
      fi
      git -c commit.gpgsign=false commit -q -m base || exit 1
      cp "$generated" CHANGELOG.md
      # shellcheck disable=SC2086
      VERSION=$case_version bash $flags "$fx/step.sh"
    ) > "$dir/log" 2>&1
    rc=$?
    ok=1
    if [ "$expect" = pass ]; then [ $rc -eq 0 ] || ok=0; else [ $rc -ne 0 ] || ok=0; fi
    if [ -n "$pattern" ] && ! grep -q -- "$pattern" "$dir/log"; then ok=0; echo "expected output not found: $pattern" >> "$dir/log"; fi
    diff -u "$expected" "$dir/CHANGELOG.md" >> "$dir/log" 2>&1 || ok=0
    if [ $ok -eq 1 ]; then
      echo "PASS: $name [bash $flags]"
    else
      echo "FAIL: $name [bash $flags] (rc=$rc)"; cat "$dir/log"; failures=$((failures + 1))
    fi
    rm -rf "$dir"
  done
}

case_version=3.39.0
preamble='# Changelog

All notable changes to this project will be documented in this file.
'
section() { # <version> <date> <entry...> : one gh-changelog style section
  local v=$1 d=$2; shift 2
  printf '\n## [v%s](https://github.com/o/r/tree/v%s) - %s\n\n[Full Changelog](https://github.com/o/r/compare/vprev...v%s)\n\n' "$v" "$v" "$d" "$v"
  printf '%s\n' "$@"
}

s_new=$(section 3.39.0 2026-11-10 '### Added' '' '- New feature [#750](https://github.com/o/r/pull/750) ([c](https://github.com/c))')
s_old3=$(section 3.38.3 2026-10-01 '### Added' '' '- Thing one [#692](https://github.com/o/r/pull/692) ([a](https://github.com/a))')
s_old2=$(section 3.38.2 2026-09-01 '### Other' '' '- Old other [#600](https://github.com/o/r/pull/600) ([b](https://github.com/b))')

s_unreleased='
## [Unreleased]

### Added

- WIP'

# What is committed: two released versions.
printf '%s\n%s\n%s\n' "$preamble" "$s_old3" "$s_old2" > "$fx/old.md"

# Generator output with the symptoms from PE-47992: the new section plus rewritten
# history (entry removed, Revert lines backfilled, header reclassified).
printf '%s\n%s\n%s\n%s\n' "$preamble" "$s_new" \
  "$(section 3.38.3 2026-10-01 '### Fixed' '' '- Revert "Thing" [#688](https://github.com/o/r/pull/688) ([a](https://github.com/a))')" \
  "$(section 3.38.2 2026-09-01 '### Added' '' '- Old other [#600](https://github.com/o/r/pull/600) ([b](https://github.com/b))')" \
  > "$fx/generated.md"

printf '%s\n%s\n%s\n%s\n' "$preamble" "$s_new" "$s_old3" "$s_old2" > "$fx/expected.md"

run_case "restores historical sections, keeps new top section" "$fx/old.md" "$fx/generated.md" "$fx/expected.md"

# Re-running prep for a version already on top of the committed file replaces
# that section instead of duplicating it.
printf '%s\n%s\n%s\n%s\n' "$preamble" "$(section 3.39.0 2026-11-09 '### Added' '' '- Stale entry')" "$s_old3" "$s_old2" > "$fx/old_rerun.md"
run_case "same-version rerun replaces top section without duplicating" "$fx/old_rerun.md" "$fx/generated.md" "$fx/expected.md"

# A committed Unreleased section is not carried over below the new section.
printf '%s\n%s\n%s\n%s\n' "$preamble" "$s_unreleased" "$s_old3" "$s_old2" > "$fx/old_unreleased.md"
run_case "committed Unreleased section is dropped with a warning" "$fx/old_unreleased.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"
sed 's/\[Unreleased\]/[unreleased]/' "$fx/old_unreleased.md" > "$fx/old_unreleased_lower.md"
run_case "committed unreleased section is dropped regardless of case" "$fx/old_unreleased_lower.md" "$fx/generated.md" "$fx/expected.md"

# Generated file with a single section (and no trailing newline) keeps all of it
# and gets a blank line before the restored history.
printf '%s\n%s' "$preamble" "$s_new" > "$fx/generated_single.md"
run_case "single generated section without trailing newline" "$fx/old.md" "$fx/generated_single.md" "$fx/expected.md"

# Version headers without the "v" prefix in the committed file still match.
sed 's/^## \[v3.38.3\]/## [3.38.3]/' "$fx/old.md" > "$fx/old_noprefix.md"
sed 's/^## \[v3.38.3\]/## [3.38.3]/' "$fx/expected.md" > "$fx/expected_noprefix.md"
run_case "history without v prefix is kept verbatim" "$fx/old_noprefix.md" "$fx/generated.md" "$fx/expected_noprefix.md"

# CRLF line endings are preserved.
sed 's/$/\r/' "$fx/old_rerun.md" > "$fx/old_crlf.md"
sed 's/$/\r/' "$fx/generated.md" > "$fx/generated_crlf.md"
sed 's/$/\r/' "$fx/expected.md" > "$fx/expected_crlf.md"
run_case "CRLF files keep their history" "$fx/old_crlf.md" "$fx/generated_crlf.md" "$fx/expected_crlf.md"

# No committed CHANGELOG.md: nothing to protect, generated file is left alone.
run_case "no committed changelog leaves generated file untouched" "-" "$fx/generated.md" "$fx/generated.md" pass "nothing to preserve"

# Committed file without any "## " sections: leave generated file alone.
printf '# Changelog\n' > "$fx/old_empty.md"
run_case "committed changelog without sections leaves generated file untouched" "$fx/old_empty.md" "$fx/generated.md" "$fx/generated.md" pass "has no '## ' sections"

# Headings in another style cannot be restored, so stop instead of dropping them.
printf '# Changelog\n\n# 3.38.3\n\n- thing\n' > "$fx/old_h1.md"
run_case "committed changelog with h1 sections fails" "$fx/old_h1.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"

# Generator produced no sections while history exists: fail instead of shipping a
# changelog without history.
printf '# Changelog\n' > "$fx/generated_empty.md"
run_case "generated changelog without sections fails" "$fx/old.md" "$fx/generated_empty.md" "$fx/generated_empty.md" fail "refusing to drop the committed history"
: > "$fx/generated_blank.md"
run_case "empty generated changelog fails" "$fx/old.md" "$fx/generated_blank.md" "$fx/generated_blank.md" fail "refusing to drop the committed history"

# CRLF where the generated section does not end in a blank line: the separator
# uses CRLF too.
printf '%s\n%s' "$preamble" "$s_new" | sed 's/$/\r/' > "$fx/generated_single_crlf.md"
sed 's/$/\r/' "$fx/expected.md" > "$fx/expected_crlf_single.md"
sed 's/$/\r/' "$fx/old.md" > "$fx/old_crlf_plain.md"
run_case "CRLF separator when the generated section has no trailing blank line" "$fx/old_crlf_plain.md" "$fx/generated_single_crlf.md" "$fx/expected_crlf_single.md"

# Only the version being prepared is committed: nothing older to restore and no
# stray blank line at the end.
printf '%s\n%s\n' "$preamble" "$(section 3.39.0 2026-11-09 '### Added' '' '- Stale entry')" > "$fx/old_only_new.md"
printf '%s\n%s\n' "$preamble" "$s_new" > "$fx/generated_only_new.md"
run_case "only the prepared version committed" "$fx/old_only_new.md" "$fx/generated_only_new.md" "$fx/generated_only_new.md"

# The generator emitted no section for the requested version: its newest section
# is a rewritten release, so the step fails and leaves the generated file alone.
case_version=3.40.0
run_case "no generated section for the requested version fails" "$fx/old.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to rewrite the released history"
for bad in "" "3.39.0; id" ";x 3.39.0" "1/;e id #" "3.39.0-a/b" "3.39.0-a&b" "latest" "3.39." "3x39.0" "3.39.0-" $'3.39.0\n/;e id #' $'3.39.0\n'; do
  case_version=$bad
  shown=${bad//$'\n'/\\n}
  run_case "invalid version '$shown' fails" "$fx/old.md" "$fx/generated.md" "$fx/generated.md" fail "Invalid version"
done
# Defensive: the step also accepts a version given with a "v" prefix.
case_version=v3.39.0
run_case "version with v prefix is accepted" "$fx/old.md" "$fx/generated.md" "$fx/expected.md"
run_case "version with v prefix replaces a committed section of that version" "$fx/old_rerun.md" "$fx/generated.md" "$fx/expected.md"
case_version=3.39.0

# Headers that are not in the "## [version](url)" form still delimit sections, so
# dropping a section never swallows its neighbours.
s_bare=$(printf '\n## v3.38.3 - 2026-10-01\n\n### Added\n\n- Bare header entry')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$s_unreleased" "$s_bare" "$s_old2" > "$fx/old_mixed.md"
printf '%s\n%s\n%s\n%s\n' "$preamble" "$s_new" "$s_bare" "$s_old2" > "$fx/expected_mixed.md"
run_case "sections with other header styles survive a dropped Unreleased section" "$fx/old_mixed.md" "$fx/generated.md" "$fx/expected_mixed.md"

# A committed file that does not use "## [version]" headers is still restored.
printf '# Changelog\n\n## Release 3.38.3\n\n- thing\n' > "$fx/old_legacy.md"
s_legacy=$(printf '\n## Release 3.38.3\n\n- thing')
printf '%s\n%s\n%s\n' "$preamble" "$s_new" "$s_legacy" > "$fx/expected_legacy.md"
run_case "committed changelog with other header style is restored" "$fx/old_legacy.md" "$fx/generated.md" "$fx/expected_legacy.md"

# A tab after the version also ends the header.
tab_head=$(printf '\n## 3.39.0\t- 2026-11-09\n\n- stale entry')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$tab_head" "$s_old3" "$s_old2" > "$fx/old_tab.md"
run_case "tab-delimited header for the prepared version is replaced" "$fx/old_tab.md" "$fx/generated.md" "$fx/expected.md"
# Bare headers followed by a date (no brackets)
dated=$(printf '\n## Unreleased - 2026-11-01\n\n- WIP\n\n## 3.39.0 - 2026-11-09\n\n- stale entry')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$dated" "$s_old3" "$s_old2" > "$fx/old_dated.md"
run_case "bare headers with a date for Unreleased and the prepared version are dropped" "$fx/old_dated.md" "$fx/generated.md" "$fx/expected.md"
# CRLF line endings on bare headers
bare_old=$(printf '%s\n%s\n%s\n%s\n' "$preamble" "$(printf '\n## Unreleased\n\n- WIP')" "$(printf '\n## 3.39.0\n\n- stale entry')" "$s_old3")
printf '%s\n' "$bare_old" | sed 's/$/\r/' > "$fx/old_bare_crlf.md"
printf '%s\n%s\n%s\n' "$preamble" "$s_new" "$s_old3" | sed 's/$/\r/' > "$fx/expected_bare_crlf.md"
sed 's/$/\r/' "$fx/generated.md" > "$fx/generated_bare_crlf.md"
run_case "CRLF bare headers for Unreleased and the prepared version are dropped" "$fx/old_bare_crlf.md" "$fx/generated_bare_crlf.md" "$fx/expected_bare_crlf.md" pass "Dropping the committed Unreleased section"

# A generated newest section that is not a version (e.g. Unreleased) fails.
printf '%s\n%s\n%s\n' "$preamble" "$s_unreleased" "$s_old3" > "$fx/generated_unreleased.md"
run_case "generated Unreleased section on top fails" "$fx/old.md" "$fx/generated_unreleased.md" "$fx/generated_unreleased.md" fail "Newest generated section is Unreleased"

# Pre-release versions are accepted.
sed 's/^## \[v3.39.0\]/## [v3.39.0-rc.1]/' "$fx/generated.md" > "$fx/generated_rc.md"
sed 's/^## \[v3.39.0\]/## [v3.39.0-rc.1]/' "$fx/expected.md" > "$fx/expected_rc.md"
case_version=3.39.0-rc.1
run_case "pre-release version is accepted" "$fx/old.md" "$fx/generated_rc.md" "$fx/expected_rc.md"
for okv in 3.39.0+build.5 3.39.0-RC-1 3; do
  sed "s/^## \[v3.39.0\]/## [v$okv]/" "$fx/generated.md" > "$fx/generated_ok.md"
  sed "s/^## \[v3.39.0\]/## [v$okv]/" "$fx/expected.md" > "$fx/expected_ok.md"
  case_version=$okv
  run_case "version '$okv' is accepted" "$fx/old.md" "$fx/generated_ok.md" "$fx/expected_ok.md"
done
case_version=3.39.0

# Headings of any level count as history that cannot be restored (deepest level here).
printf '# Changelog\n\n###### 3.38.3\n\n- thing\n' > "$fx/old_h6.md"
run_case "committed changelog with only level 6 headings fails" "$fx/old_h6.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"

# Unreleased headers in any case, or followed by punctuation or a tab, are dropped with a warning.
for punct in "," ";"; do
  p_unreleased=$(printf '\n## Unreleased%s notes\n\n- WIP' "$punct")
  printf '%s\n%s\n%s\n%s\n' "$preamble" "$p_unreleased" "$s_old3" "$s_old2" > "$fx/old_unreleased_punct.md"
  run_case "Unreleased header followed by '$punct' is dropped with a warning" "$fx/old_unreleased_punct.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"
done
colon_unreleased=$(printf '\n## Unreleased: notes\n\n- WIP')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$colon_unreleased" "$s_old3" "$s_old2" > "$fx/old_unreleased_colon.md"
run_case "Unreleased header followed by a colon is dropped with a warning" "$fx/old_unreleased_colon.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"
tabbed=$(printf '\n## Unreleased\t- 2026-11-01\n\n- WIP')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$tabbed" "$s_old3" "$s_old2" > "$fx/old_unreleased_tab.md"
run_case "tab-delimited Unreleased header is dropped with a warning" "$fx/old_unreleased_tab.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"
upper=$(printf '\n## UNRELEASED\n\n- WIP')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$upper" "$s_old3" "$s_old2" > "$fx/old_upper.md"
run_case "bare UNRELEASED header is dropped with a warning" "$fx/old_upper.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"

# A single heading that is not a title, or a tab-separated heading, is history
# that cannot be restored.
printf '# 0.9.0\n\n- old thing\n' > "$fx/old_lone.md"
run_case "committed changelog whose only heading is a version fails" "$fx/old_lone.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"
printf '# Changelog\n\n##\t0.9.0\n\n- old\n' > "$fx/old_tabhead.md"
run_case "committed changelog with a tab-separated heading fails" "$fx/old_tabhead.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"

# A trailing colon after the version in a header still identifies the section.
hdr=$(printf '\n## 3.39.0: stale\n\n- stale entry')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$hdr" "$s_old3" "$s_old2" > "$fx/old_colon.md"
run_case "header with a colon after the prepared version is replaced" "$fx/old_colon.md" "$fx/generated.md" "$fx/expected.md"

# Nothing but text, or nothing at all, leaves the generated file alone.
printf 'just some text\n' > "$fx/old_text.md"
run_case "committed changelog without headings leaves generated file untouched" "$fx/old_text.md" "$fx/generated.md" "$fx/generated.md" pass "has no '## ' sections"
: > "$fx/old_blank.md"
run_case "empty committed changelog leaves generated file untouched" "$fx/old_blank.md" "$fx/generated.md" "$fx/generated.md" pass "has no '## ' sections"
for title in "Change log" "Release notes" "History" "Changes" "Changelog  " $'\tChangelog'; do
  printf '#%s%s\n\nSome text\n' "$([ "${title:0:1}" = $'\t' ] || echo ' ')" "$title" > "$fx/old_title.md"
  run_case "bare title '${title//$'\t'/<tab>}' leaves generated file untouched" "$fx/old_title.md" "$fx/generated.md" "$fx/generated.md" pass "has no '## ' sections"
done

# Other punctuation after the version in a header
for punct in "," ";"; do
  hdr=$(printf '\n## 3.39.0%s stale\n\n- stale entry' "$punct")
  printf '%s\n%s\n%s\n%s\n' "$preamble" "$hdr" "$s_old3" "$s_old2" > "$fx/old_punct.md"
  run_case "header with '$punct' after the prepared version is replaced" "$fx/old_punct.md" "$fx/generated.md" "$fx/expected.md"
done

# Versions that merely resemble the prepared one are other releases and are kept.
s_rc=$(section 3.39.0-rc.1 2026-11-05 '### Added' '' '- rc entry')
s_lookalike=$(section 3.390.0 2026-11-06 '### Added' '' '- lookalike entry')
printf '%s\n%s\n%s\n%s\n%s\n' "$preamble" "$s_rc" "$s_lookalike" "$s_old3" "$s_old2" > "$fx/old_similar.md"
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$preamble" "$s_new" "$s_rc" "$s_lookalike" "$s_old3" "$s_old2" > "$fx/expected_similar.md"
run_case "sections of similar versions are kept" "$fx/old_similar.md" "$fx/generated.md" "$fx/expected_similar.md"

# A heading that only starts like a title is history that cannot be restored.
printf '# Changes 0.9.0\n\n- old thing\n' > "$fx/old_title_like.md"
run_case "committed changelog whose only heading starts like a title fails" "$fx/old_title_like.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"

printf '### History\n\n- old thing\n' > "$fx/old_deep_title.md"
run_case "committed changelog whose only heading is a deep History heading fails" "$fx/old_deep_title.md" "$fx/generated.md" "$fx/generated.md" fail "refusing to drop its history"

# A v-prefixed Unreleased header is dropped with a warning too.
v_unreleased=$(printf '\n## vUnreleased\n\n- WIP')
printf '%s\n%s\n%s\n%s\n' "$preamble" "$v_unreleased" "$s_old3" "$s_old2" > "$fx/old_v_unreleased.md"
run_case "vUnreleased header is dropped with a warning" "$fx/old_v_unreleased.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"
sed 's/vUnreleased/VUNRELEASED/' "$fx/old_v_unreleased.md" > "$fx/old_v_unreleased_upper.md"
run_case "VUNRELEASED header is dropped with a warning" "$fx/old_v_unreleased_upper.md" "$fx/generated.md" "$fx/expected.md" pass "Dropping the committed Unreleased section"

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
