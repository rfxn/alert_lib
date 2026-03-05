#!/bin/bash
# alert-common.bash — shared BATS helper for alert_lib tests
# Sources alert_lib.sh and provides setup/teardown functions.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/alert_lib.sh"

# Expected version from sourced library — tests use this instead of hardcoded strings
EXPECTED_VERSION="$ALERT_LIB_VERSION"
export EXPECTED_VERSION

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-support/load.bash
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-assert/load.bash
fi

alert_common_setup() {
	TEST_TMPDIR=$(mktemp -d)
	export TEST_TMPDIR

	# Reset channel registry arrays to empty
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()

	# Export all ALERT_* env vars to test defaults (short timeouts)
	export ALERT_CURL_TIMEOUT=5
	export ALERT_CURL_MAX_TIME=10
	export ALERT_TMPDIR="$TEST_TMPDIR"
}

alert_teardown() {
	rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Mock binary infrastructure — for testing delivery functions without
# actually sending email or making HTTP calls.
# ---------------------------------------------------------------------------

# alert_mock_setup — create mock binary directory and prepend to PATH
# Call from setup() in test files that need mock binaries.
# Saves original PATH for restoration in teardown.
alert_mock_setup() {
	MOCK_BIN="$TEST_TMPDIR/bin"
	mkdir -p "$MOCK_BIN"
	export ALERT_MOCK_DIR="$TEST_TMPDIR"
	# Mocks first, then real binaries (base64, hostname, date, etc.)
	export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
}

# alert_create_mock name [exit_code] — create a mock binary that captures args and stdin
# Creates $MOCK_BIN/$name that writes "$@" to $ALERT_MOCK_DIR/${name}_args
# (one arg per line) and stdin to $ALERT_MOCK_DIR/${name}_stdin.
# Optional exit_code (default 0).
alert_create_mock() {
	local name="$1" rc="${2:-0}"
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/$name" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/${name}_args"
	cat > "$mock_dir/${name}_stdin"
	exit $rc
	ENDMOCK
	chmod +x "$MOCK_BIN/$name"
}
