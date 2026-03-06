#!/usr/bin/env bats
# 07-digest.bats — Digest/spool system tests

load helpers/alert-common

# Callback mock: copies flush file content to a known location
_test_flush_callback() {
	cp "$1" "$TEST_TMPDIR/flushed_data"
	echo "$1" > "$TEST_TMPDIR/callback_arg"
	return 0
}

# Callback mock that fails
_test_flush_callback_fail() {
	return 1
}

setup() {
	alert_common_setup

	# Create test data files
	printf 'alert line 1\n' > "$TEST_TMPDIR/data1.txt"
	printf 'alert line 2\nalert line 3\n' > "$TEST_TMPDIR/data2.txt"

	# Spool file path (not created yet — functions create on append)
	SPOOL_FILE="$TEST_TMPDIR/test.spool"
	export SPOOL_FILE
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_spool_append
# ---------------------------------------------------------------------------

@test "spool_append: appends timestamped entries to spool file" {
	run _alert_spool_append "$TEST_TMPDIR/data1.txt" "$SPOOL_FILE"
	[ "$status" -eq 0 ]
	[ -f "$SPOOL_FILE" ]
	local line
	line=$(cat "$SPOOL_FILE")
	# Should match pattern: EPOCH|alert line 1
	local epoch_pat='^[0-9]{10,}[|]alert line 1$'
	[[ "$line" =~ $epoch_pat ]]
}

@test "spool_append: multiple appends accumulate entries" {
	_alert_spool_append "$TEST_TMPDIR/data1.txt" "$SPOOL_FILE"
	_alert_spool_append "$TEST_TMPDIR/data2.txt" "$SPOOL_FILE"
	local count
	count=$(wc -l < "$SPOOL_FILE")
	[ "$count" -eq 3 ]
}

@test "spool_append: skips blank lines in data file" {
	printf 'line1\n\nline2\n\n\nline3\n' > "$TEST_TMPDIR/blanks.txt"
	run _alert_spool_append "$TEST_TMPDIR/blanks.txt" "$SPOOL_FILE"
	[ "$status" -eq 0 ]
	local count
	count=$(wc -l < "$SPOOL_FILE")
	[ "$count" -eq 3 ]
}

@test "spool_append: empty data file is no-op (returns 0)" {
	: > "$TEST_TMPDIR/empty.txt"
	run _alert_spool_append "$TEST_TMPDIR/empty.txt" "$SPOOL_FILE"
	[ "$status" -eq 0 ]
	[ ! -f "$SPOOL_FILE" ]
}

@test "spool_append: missing data file is no-op (returns 0)" {
	run _alert_spool_append "/nonexistent/data.txt" "$SPOOL_FILE"
	[ "$status" -eq 0 ]
	[ ! -f "$SPOOL_FILE" ]
}

@test "spool_append: empty spool_file argument returns 1" {
	run _alert_spool_append "$TEST_TMPDIR/data1.txt" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"spool_file argument is required"* ]]
}

@test "spool_append: flock not found returns 1" {
	local saved_path="$PATH"
	# PATH with only basic utilities but no flock
	export PATH="/usr/bin:/bin"
	# Verify flock is actually gone from this PATH (skip if it's in /usr/bin)
	if command -v flock > /dev/null 2>&1; then
		export PATH="$saved_path"
		skip "flock found in /usr/bin, cannot test missing flock"
	fi
	run _alert_spool_append "$TEST_TMPDIR/data1.txt" "$SPOOL_FILE"
	export PATH="$saved_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"flock not found"* ]]
}

# ---------------------------------------------------------------------------
# _alert_digest_check
# ---------------------------------------------------------------------------

@test "digest_check: calls flush when spool age >= interval" {
	# Create spool with old epoch (1 hour ago)
	local old_epoch
	old_epoch=$(( $(date +%s) - 3600 ))
	echo "${old_epoch}|old alert data" > "$SPOOL_FILE"
	run _alert_digest_check "$SPOOL_FILE" "60" "_test_flush_callback"
	[ "$status" -eq 0 ]
	# Callback should have been invoked — flushed_data file exists
	[ -f "$TEST_TMPDIR/flushed_data" ]
	local flushed
	flushed=$(cat "$TEST_TMPDIR/flushed_data")
	[ "$flushed" = "old alert data" ]
}

@test "digest_check: does NOT flush when spool age < interval" {
	# Create spool with current epoch
	local now
	now=$(date +%s)
	echo "${now}|recent alert" > "$SPOOL_FILE"
	run _alert_digest_check "$SPOOL_FILE" "9999" "_test_flush_callback"
	[ "$status" -eq 0 ]
	# Callback should NOT have been invoked
	[ ! -f "$TEST_TMPDIR/flushed_data" ]
	# Spool should still contain data
	[ -s "$SPOOL_FILE" ]
}

@test "digest_check: empty spool returns 0 (no-op)" {
	: > "$SPOOL_FILE"
	run _alert_digest_check "$SPOOL_FILE" "60" "_test_flush_callback"
	[ "$status" -eq 0 ]
	[ ! -f "$TEST_TMPDIR/flushed_data" ]
}

@test "digest_check: non-existent spool file returns 0" {
	run _alert_digest_check "/nonexistent/spool" "60" "_test_flush_callback"
	[ "$status" -eq 0 ]
}

@test "digest_check: empty spool_file argument returns 1" {
	run _alert_digest_check "" "60" "_test_flush_callback"
	[ "$status" -eq 1 ]
	[[ "$output" == *"spool_file argument is required"* ]]
}

@test "digest_check: empty interval or callback returns 1" {
	echo "123|data" > "$SPOOL_FILE"
	run _alert_digest_check "$SPOOL_FILE" "" "_test_flush_callback"
	[ "$status" -eq 1 ]
	[[ "$output" == *"interval argument is required"* ]]

	run _alert_digest_check "$SPOOL_FILE" "60" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"flush_callback argument is required"* ]]
}

# ---------------------------------------------------------------------------
# _alert_digest_flush
# ---------------------------------------------------------------------------

@test "digest_flush: strips epoch prefix from flushed entries" {
	echo "1234567890|alert data here" > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ "$status" -eq 0 ]
	[ -f "$TEST_TMPDIR/flushed_data" ]
	local flushed
	flushed=$(cat "$TEST_TMPDIR/flushed_data")
	[ "$flushed" = "alert data here" ]
}

@test "digest_flush: preserves pipe characters in data" {
	echo "1234567890|field1|field2|field3" > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ "$status" -eq 0 ]
	local flushed
	flushed=$(cat "$TEST_TMPDIR/flushed_data")
	[ "$flushed" = "field1|field2|field3" ]
}

@test "digest_flush: passes flush file path to callback" {
	echo "1234567890|data" > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ "$status" -eq 0 ]
	[ -f "$TEST_TMPDIR/callback_arg" ]
	local arg
	arg=$(cat "$TEST_TMPDIR/callback_arg")
	# Callback arg should be a temp file path
	[[ "$arg" == *"alert_digest_flush"* ]]
}

@test "digest_flush: callback receives all accumulated entries" {
	printf '1111111111|line one\n2222222222|line two\n3333333333|line three\n' > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ "$status" -eq 0 ]
	local count
	count=$(wc -l < "$TEST_TMPDIR/flushed_data")
	[ "$count" -eq 3 ]
	# Verify content
	local first last
	first=$(head -1 "$TEST_TMPDIR/flushed_data")
	last=$(tail -1 "$TEST_TMPDIR/flushed_data")
	[ "$first" = "line one" ]
	[ "$last" = "line three" ]
}

@test "digest_flush: truncates spool after flush" {
	echo "1234567890|data" > "$SPOOL_FILE"
	_alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	# Spool should exist but be empty
	[ -f "$SPOOL_FILE" ]
	[ ! -s "$SPOOL_FILE" ]
}

@test "digest_flush: spool file preserved (not deleted)" {
	echo "1234567890|data" > "$SPOOL_FILE"
	local inode_before
	inode_before=$(stat -c '%i' "$SPOOL_FILE")
	_alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ -f "$SPOOL_FILE" ]
	local inode_after
	inode_after=$(stat -c '%i' "$SPOOL_FILE")
	[ "$inode_before" = "$inode_after" ]
}

@test "digest_flush: empty spool returns 0 (no callback)" {
	: > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	[ "$status" -eq 0 ]
	[ ! -f "$TEST_TMPDIR/flushed_data" ]
}

@test "digest_flush: missing spool returns 0 (no callback)" {
	run _alert_digest_flush "/nonexistent/spool" "_test_flush_callback"
	[ "$status" -eq 0 ]
	[ ! -f "$TEST_TMPDIR/flushed_data" ]
}

@test "digest_flush: empty spool_file argument returns 1" {
	run _alert_digest_flush "" "_test_flush_callback"
	[ "$status" -eq 1 ]
	[[ "$output" == *"spool_file argument is required"* ]]
}

@test "digest_flush: empty flush_callback argument returns 1" {
	echo "1234567890|data" > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"flush_callback argument is required"* ]]
}

@test "digest_flush: callback failure returns non-zero" {
	echo "1234567890|data" > "$SPOOL_FILE"
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback_fail"
	[ "$status" -eq 1 ]
}

@test "digest_flush: cleans up flush temp file" {
	echo "1234567890|data" > "$SPOOL_FILE"
	_alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_digest_flush.*' 2>/dev/null)
	[ -z "$leftover" ]
}

@test "digest_flush: flock not found returns 1" {
	echo "1234567890|data" > "$SPOOL_FILE"
	local saved_path="$PATH"
	export PATH="/usr/bin:/bin"
	if command -v flock > /dev/null 2>&1; then
		export PATH="$saved_path"
		skip "flock found in /usr/bin, cannot test missing flock"
	fi
	run _alert_digest_flush "$SPOOL_FILE" "_test_flush_callback"
	export PATH="$saved_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"flock not found"* ]]
}

# ---------------------------------------------------------------------------
# Integration
# ---------------------------------------------------------------------------

@test "integration: full cycle append → check → flush" {
	# Append data
	_alert_spool_append "$TEST_TMPDIR/data1.txt" "$SPOOL_FILE"
	_alert_spool_append "$TEST_TMPDIR/data2.txt" "$SPOOL_FILE"
	[ -s "$SPOOL_FILE" ]
	local count_before
	count_before=$(wc -l < "$SPOOL_FILE")
	[ "$count_before" -eq 3 ]

	# Use interval=0 so age check always triggers flush
	run _alert_digest_check "$SPOOL_FILE" "0" "_test_flush_callback"
	[ "$status" -eq 0 ]

	# Callback should have received all 3 lines with epoch stripped
	[ -f "$TEST_TMPDIR/flushed_data" ]
	local flushed_count
	flushed_count=$(wc -l < "$TEST_TMPDIR/flushed_data")
	[ "$flushed_count" -eq 3 ]

	# Verify epoch prefixes are stripped — original data present
	local first_line
	first_line=$(head -1 "$TEST_TMPDIR/flushed_data")
	[ "$first_line" = "alert line 1" ]

	# Spool should be empty after flush
	[ ! -s "$SPOOL_FILE" ]
}

@test "integration: check with young spool does not flush" {
	_alert_spool_append "$TEST_TMPDIR/data1.txt" "$SPOOL_FILE"
	[ -s "$SPOOL_FILE" ]

	# Large interval — spool is too young
	run _alert_digest_check "$SPOOL_FILE" "99999" "_test_flush_callback"
	[ "$status" -eq 0 ]

	# No flush should have occurred
	[ ! -f "$TEST_TMPDIR/flushed_data" ]
	[ -s "$SPOOL_FILE" ]
}
