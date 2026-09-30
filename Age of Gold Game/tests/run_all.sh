#!/usr/bin/env bash
# Runs every headless SceneTree test for Age of Gold and prints a summary.
# Usage: run_all.sh            (logs go to ${TMPDIR:-/tmp}/aog-test-runs/<name>.log)
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$S/.." && pwd)"
GODOT="$HOME/Godot_v4.4-stable_linux.arm64"
TESTS=(
	combat/combat_test.gd
	griot/test_griot.gd
	age/test_age.gd
	art/test_art.gd
	conversion/test_conversion.gd
	tech/test_tech.gd
	economy/test_economy.gd
	events/test_events.gd
	buildings/test_buildings.gd
	mission1_test.gd
	rival/test_rival.gd
	units/test_units.gd
	flow/test_flow.gd
	campaign/test_campaign.gd
	audio/test_audio.gd
	showdown/test_showdown.gd
)
mkdir -p "${TMPDIR:-/tmp}/aog-test-runs"
bad=0
for t in "${TESTS[@]}"; do
	log="${TMPDIR:-/tmp}/aog-test-runs/$(echo "$t" | tr '/' '_').log"
	timeout 300 "$GODOT" --headless --fixed-fps 60 --path "$P" -s "$S/$t" > "$log" 2>&1
	code=$?
	passes=$(grep -cE '^(PASS|\[PASS\])' "$log")
	result=$(grep -E 'RESULT' "$log" | tail -n1)
	[ -z "$result" ] && result="NO RESULT LINE (exit $code)"
	printf '%-32s %3d pass  %s\n' "$t" "$passes" "$result"
	issues=$(grep -E '^(FAIL|\[FAIL\])|SCRIPT ERROR' "$log")
	if [ -n "$issues" ]; then
		echo "$issues" | sed 's/^/    /'
	fi
	if [ -n "$issues" ] || ! echo "$result" | grep -qE '\(0 failures\)'; then
		bad=$((bad + 1))
	fi
done
echo "----"
if [ "$bad" -eq 0 ]; then
	echo "ALL ${#TESTS[@]} TESTS OK"
else
	echo "$bad of ${#TESTS[@]} TESTS HAVE PROBLEMS"
fi
exit "$bad"
