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
