#!/usr/bin/env bats
# 00-scaffold.bats — validate project skeleton

load helpers/alert-common

setup() {
	alert_common_setup
}

teardown() {
	alert_teardown
}

@test "ALERT_LIB_VERSION is set and follows semver" {
	[[ -n "$EXPECTED_VERSION" ]]
	local semver_pat='^[0-9]+\.[0-9]+\.[0-9]+$'
	[[ "$EXPECTED_VERSION" =~ $semver_pat ]]
}

@test "source guard prevents double-sourcing side effects" {
	# Record version, re-source, verify no change
	local ver_before="$ALERT_LIB_VERSION"
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	[[ "$ALERT_LIB_VERSION" == "$ver_before" ]]
}

@test "channel registry arrays initialized empty" {
	[[ ${#_ALERT_CHANNEL_NAMES[@]} -eq 0 ]]
	[[ ${#_ALERT_CHANNEL_HANDLERS[@]} -eq 0 ]]
	[[ ${#_ALERT_CHANNEL_ENABLED[@]} -eq 0 ]]
}
