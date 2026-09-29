#!/bin/sh
# Runs the tests of the Plugin-Assistent with Lua 5.3.
#
# Uses the first available interpreter:
#   1. $LUA (if set)
#   2. lua5.3 or lua (version 5.3)
#   3. python3 with the package "lupa" (pip install lupa)
set -eu

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$TESTS_DIR/../../.." && pwd)
SAMPLES_DIR="$REPO_DIR/samples"

if [ -n "${LUA:-}" ]; then
	RUN="$LUA"
elif command -v lua5.3 >/dev/null 2>&1; then
	RUN="lua5.3"
elif command -v lua >/dev/null 2>&1 && lua -v 2>&1 | grep -q "Lua 5.3"; then
	RUN="lua"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import lupa.lua53" >/dev/null 2>&1; then
	RUN="python3 $TESTS_DIR/support/lua53.py"
else
	echo "Lua 5.3 not found. Install lua5.3 or run: pip install lupa" >&2
	exit 2
fi

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT
(cd "$SAMPLES_DIR" && find . -type f \( -name '*.lua' -o -name '*.xml' -o -name '*.xlf' -o -name '*.html' \) \
	-not -path '*/.vs/*' | sed 's|^\./||' | sort) > "$LIST"

cd "$TESTS_DIR"
# shellcheck disable=SC2086
$RUN run_tests.lua "$TESTS_DIR" "$SAMPLES_DIR" "$LIST" $(ls test_*.lua)
