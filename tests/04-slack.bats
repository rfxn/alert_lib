#!/usr/bin/env bats
# 04-slack.bats — HTTP utilities and Slack delivery tests

load helpers/alert-common

setup() {
	alert_common_setup
	alert_mock_setup

	# Create test payload file (minimal Slack JSON)
	printf '{"text":"test alert"}\n' > "$TEST_TMPDIR/payload.json"

	# Create test attachment file
	printf 'scan report content\n' > "$TEST_TMPDIR/attachment.txt"

	# Default curl mock with response support
	alert_create_curl_mock
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_validate_url
# ---------------------------------------------------------------------------

@test "validate_url: http:// returns 0" {
	run _alert_validate_url "http://example.com/hook"
	[ "$status" -eq 0 ]
}

@test "validate_url: https:// returns 0" {
	run _alert_validate_url "https://hooks.slack.com/services/T/B/x"
	[ "$status" -eq 0 ]
}

@test "validate_url: ftp:// returns 1" {
	run _alert_validate_url "ftp://example.com"
	[ "$status" -eq 1 ]
}

@test "validate_url: empty string returns 1" {
	run _alert_validate_url ""
	[ "$status" -eq 1 ]
}

@test "validate_url: no protocol returns 1" {
	run _alert_validate_url "example.com"
	[ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _alert_curl_post
# ---------------------------------------------------------------------------

@test "curl_post: passes -s --connect-timeout --max-time -X POST to curl" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_curl_post "https://example.com/api" -H "Content-Type: application/json"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"-s"* ]]
	[[ "$args" == *"--connect-timeout"* ]]
	[[ "$args" == *"--max-time"* ]]
	[[ "$args" == *"-X"* ]]
	[[ "$args" == *"POST"* ]]
}

@test "curl_post: passes URL as argument to curl" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_curl_post "https://example.com/webhook"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"https://example.com/webhook"* ]]
}

@test "curl_post: passes extra flags through to curl" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_curl_post "https://example.com/api" \
		-H "Authorization: Bearer xoxb-token" \
		-d '{"text":"hello"}'
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"Authorization: Bearer xoxb-token"* ]]
	[[ "$args" == *'{"text":"hello"}'* ]]
}

@test "curl_post: returns response body on stdout" {
	echo '{"ok":true,"ts":"1234"}' > "$ALERT_MOCK_DIR/curl_response"
	local response
	response=$(_alert_curl_post "https://example.com/api")
	[[ "$response" == *'"ok":true'* ]]
}

@test "curl_post: uses ALERT_CURL_TIMEOUT and ALERT_CURL_MAX_TIME" {
	export ALERT_CURL_TIMEOUT=15
	export ALERT_CURL_MAX_TIME=60
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_curl_post "https://example.com/api"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"--connect-timeout"* ]]
	[[ "$args" == *"15"* ]]
	[[ "$args" == *"--max-time"* ]]
	[[ "$args" == *"60"* ]]
}

@test "curl_post: curl not found returns 1" {
	rm -f "$MOCK_BIN/curl"
	local saved_path="$PATH"
	export PATH="$MOCK_BIN"
	run _alert_curl_post "https://example.com/api"
	export PATH="$saved_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"curl not found"* ]]
}

@test "curl_post: curl failure returns 1 with error detail" {
	alert_create_curl_mock 7
	run _alert_curl_post "https://example.com/api"
	[ "$status" -eq 1 ]
	[[ "$output" == *"POST to https://example.com/api failed"* ]]
	[[ "$output" == *"curl exit 7"* ]]
}

@test "curl_post: error output does not contain Slack webhook token" {
	alert_create_curl_mock 7
	run _alert_curl_post "https://hooks.slack.com/services/T00000000/B00000000/xyzSecretToken"
	[ "$status" -eq 1 ]
	# Token must be redacted in error message
	[[ "$output" != *"xyzSecretToken"* ]]
	[[ "$output" == *"[REDACTED]"* ]]
}

@test "curl_post: cleans up stderr temp file on success" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	_alert_curl_post "https://example.com/api" > /dev/null
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_curl_err.*' 2>/dev/null)
	[ -z "$leftover" ]
}

# ---------------------------------------------------------------------------
# _alert_slack_webhook
# ---------------------------------------------------------------------------

@test "slack_webhook: POSTs payload with Content-Type application/json" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_webhook "$TEST_TMPDIR/payload.json" "https://hooks.slack.com/services/T/B/x"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"Content-Type: application/json"* ]]
	[[ "$args" == *"https://hooks.slack.com/services/T/B/x"* ]]
}

@test "slack_webhook: returns 0 on 'ok' response" {
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_webhook "$TEST_TMPDIR/payload.json" "https://hooks.slack.com/services/T/B/x"
	[ "$status" -eq 0 ]
}

@test "slack_webhook: returns 1 on error response" {
	echo "invalid_payload" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_webhook "$TEST_TMPDIR/payload.json" "https://hooks.slack.com/services/T/B/x"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Slack webhook error"* ]]
}

@test "slack_webhook: invalid URL returns 1" {
	run _alert_slack_webhook "$TEST_TMPDIR/payload.json" "ftp://invalid"
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid or empty Slack webhook URL"* ]]
}

@test "slack_webhook: empty URL returns 1" {
	run _alert_slack_webhook "$TEST_TMPDIR/payload.json" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid or empty Slack webhook URL"* ]]
}

# ---------------------------------------------------------------------------
# _alert_slack_post_message
# ---------------------------------------------------------------------------

@test "slack_post_message: injects channel into JSON payload" {
	echo '{"ok":true,"ts":"1234"}' > "$ALERT_MOCK_DIR/curl_response"
	# Use a curl mock that captures the -d @file content
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	# Find -d argument that starts with @ and capture file content
	while [ \$# -gt 0 ]; do
		case "\$1" in
			-d)
				shift
				if [ "\${1#@}" != "\$1" ]; then
					cat "\${1#@}" > "$mock_dir/curl_payload"
				fi
				;;
		esac
		shift
	done
	cat "$mock_dir/curl_response"
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" "#general"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_payload" ]
	local payload
	payload=$(cat "$ALERT_MOCK_DIR/curl_payload")
	[[ "$payload" == *'"channel":"#general"'* ]]
}

@test "slack_post_message: includes Authorization header with token" {
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" "#general"
	[ "$status" -eq 0 ]
	local kconfig
	kconfig=$(cat "$ALERT_MOCK_DIR/curl_kconfig")
	[[ "$kconfig" == *'Authorization: Bearer xoxb-test-token'* ]]
}

@test "slack_post_message: posts to chat.postMessage API" {
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" "#general"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"chat.postMessage"* ]]
}

@test "slack_post_message: API error returns 1 with error message" {
	echo '{"ok":false,"error":"channel_not_found"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" "#nonexist"
	[ "$status" -eq 1 ]
	[[ "$output" == *"chat.postMessage error"* ]]
	[[ "$output" == *"channel_not_found"* ]]
}

@test "slack_post_message: missing token returns 1" {
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "" "#general"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Slack token is required"* ]]
}

@test "slack_post_message: missing channel returns 1" {
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"Slack channel is required"* ]]
}

@test "slack_post_message: cleans up modified payload temp file" {
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_post_message "$TEST_TMPDIR/payload.json" "xoxb-test-token" "#general"
	[ "$status" -eq 0 ]
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_slack_msg.*' 2>/dev/null)
	[ -z "$leftover" ]
}

# ---------------------------------------------------------------------------
# _alert_slack_upload
# ---------------------------------------------------------------------------

@test "slack_upload: successful 3-step flow" {
	alert_create_curl_routing_mock
	# Step 1: getUploadURLExternal response
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123ABC"}' \
		> "$ALERT_MOCK_DIR/curl_response_1"
	# Step 2: file upload (no meaningful response needed)
	echo 'ok' > "$ALERT_MOCK_DIR/curl_response_2"
	# Step 3: completeUploadExternal response
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_3"

	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Scan Report" "xoxb-test-token" "#alerts"
	[ "$status" -eq 0 ]

	# Verify 3 curl calls were made
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 3 ]

	# Step 1 hit getUploadURLExternal
	local args1
	args1=$(cat "$ALERT_MOCK_DIR/curl_args_1")
	[[ "$args1" == *"getUploadURLExternal"* ]]
	local kconfig1
	kconfig1=$(cat "$ALERT_MOCK_DIR/curl_kconfig_1")
	[[ "$kconfig1" == *'Authorization: Bearer xoxb-test-token'* ]]

	# Step 2 uploaded to presigned URL
	local args2
	args2=$(cat "$ALERT_MOCK_DIR/curl_args_2")
	[[ "$args2" == *"https://files.slack.com/upload/v1/abc"* ]]
	[[ "$args2" == *"file=@"* ]]

	# Step 3 hit completeUploadExternal with file_id
	local args3
	args3=$(cat "$ALERT_MOCK_DIR/curl_args_3")
	[[ "$args3" == *"completeUploadExternal"* ]]
	[[ "$args3" == *"F123ABC"* ]]
}

@test "slack_upload: file not found returns 1" {
	run _alert_slack_upload "/nonexistent/file.txt" "Title" "xoxb-token" "#channel"
	[ "$status" -eq 1 ]
	[[ "$output" == *"file not found"* ]]
}

@test "slack_upload: missing token returns 1" {
	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Title" "" "#channel"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Slack token is required"* ]]
}

@test "slack_upload: step 1 curl failure returns 1" {
	alert_create_curl_mock 7
	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Title" "xoxb-token" "#channel"
	[ "$status" -eq 1 ]
}

@test "slack_upload: step 1 API error returns 1" {
	echo '{"ok":false,"error":"not_authed"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Title" "xoxb-token" "#channel"
	[ "$status" -eq 1 ]
	[[ "$output" == *"getUploadURLExternal error"* ]]
	[[ "$output" == *"not_authed"* ]]
}

@test "slack_upload: step 2 failure returns 1" {
	alert_create_curl_routing_mock
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123"}' \
		> "$ALERT_MOCK_DIR/curl_response_1"
	echo "1" > "$ALERT_MOCK_DIR/curl_exit_2"  # step 2 fails

	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Title" "xoxb-token" "#channel"
	[ "$status" -eq 1 ]
	[[ "$output" == *"upload to presigned URL failed"* ]]
}

@test "slack_upload: step 3 API error returns 1" {
	alert_create_curl_routing_mock
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123"}' \
		> "$ALERT_MOCK_DIR/curl_response_1"
	echo 'ok' > "$ALERT_MOCK_DIR/curl_response_2"
	echo '{"ok":false,"error":"invalid_channel"}' > "$ALERT_MOCK_DIR/curl_response_3"

	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" "Title" "xoxb-token" "#channel"
	[ "$status" -eq 1 ]
	[[ "$output" == *"completeUploadExternal error"* ]]
	[[ "$output" == *"invalid_channel"* ]]
}

@test "slack_upload: escapes title via _alert_json_escape" {
	alert_create_curl_routing_mock
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123"}' \
		> "$ALERT_MOCK_DIR/curl_response_1"
	echo 'ok' > "$ALERT_MOCK_DIR/curl_response_2"
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_3"

	run _alert_slack_upload "$TEST_TMPDIR/attachment.txt" 'Report "special"' "xoxb-token" "#channel"
	[ "$status" -eq 0 ]
	# Step 3 should contain escaped quotes
	local args3
	args3=$(cat "$ALERT_MOCK_DIR/curl_args_3")
	[[ "$args3" == *'Report \"special\"'* ]]
}

# ---------------------------------------------------------------------------
# _alert_deliver_slack
# ---------------------------------------------------------------------------

@test "deliver_slack: webhook mode calls _alert_slack_webhook" {
	export ALERT_SLACK_MODE="webhook"
	export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"https://hooks.slack.com/services/T/B/x"* ]]
}

@test "deliver_slack: bot mode calls _alert_slack_post_message" {
	export ALERT_SLACK_MODE="bot"
	export ALERT_SLACK_TOKEN="xoxb-test-token"
	export ALERT_SLACK_CHANNEL="#alerts"
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"chat.postMessage"* ]]
	local kconfig
	kconfig=$(cat "$ALERT_MOCK_DIR/curl_kconfig")
	[[ "$kconfig" == *'Authorization: Bearer xoxb-test-token'* ]]
}

@test "deliver_slack: bot mode with attachment also calls _alert_slack_upload" {
	export ALERT_SLACK_MODE="bot"
	export ALERT_SLACK_TOKEN="xoxb-test-token"
	export ALERT_SLACK_CHANNEL="#alerts"
	# Need routing mock for post_message (1 call) + upload (3 calls)
	alert_create_curl_routing_mock
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_1"  # post_message
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123"}' \
		> "$ALERT_MOCK_DIR/curl_response_2"  # getUploadURL
	echo 'ok' > "$ALERT_MOCK_DIR/curl_response_3"  # file upload
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_4"  # completeUpload

	run _alert_deliver_slack "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 4 ]
}

@test "deliver_slack: webhook mode with attachment warns but succeeds" {
	export ALERT_SLACK_MODE="webhook"
	export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	[[ "$output" == *"webhooks cannot upload files"* ]]
}

@test "deliver_slack: missing webhook URL returns 1" {
	export ALERT_SLACK_MODE="webhook"
	unset ALERT_SLACK_WEBHOOK_URL 2>/dev/null || true
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_SLACK_WEBHOOK_URL not set"* ]]
}

@test "deliver_slack: unknown mode returns 1" {
	export ALERT_SLACK_MODE="pigeon"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown ALERT_SLACK_MODE"* ]]
}

@test "deliver_slack: defaults to webhook mode" {
	unset ALERT_SLACK_MODE 2>/dev/null || true
	export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"https://hooks.slack.com/services/T/B/x"* ]]
}

@test "deliver_slack: bot mode missing token returns 1" {
	export ALERT_SLACK_MODE="bot"
	unset ALERT_SLACK_TOKEN 2>/dev/null || true
	export ALERT_SLACK_CHANNEL="#alerts"
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_SLACK_TOKEN not set"* ]]
}

@test "deliver_slack: bot mode missing channel returns 1" {
	export ALERT_SLACK_MODE="bot"
	export ALERT_SLACK_TOKEN="xoxb-test-token"
	unset ALERT_SLACK_CHANNEL 2>/dev/null || true
	run _alert_deliver_slack "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_SLACK_CHANNEL not set"* ]]
}

# ---------------------------------------------------------------------------
# _alert_handle_slack + registration
# ---------------------------------------------------------------------------

@test "handle_slack: passes text_file as payload to _alert_deliver_slack" {
	export ALERT_SLACK_MODE="webhook"
	export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
	echo "ok" > "$ALERT_MOCK_DIR/curl_response"
	# Handler signature: subject text_file html_file [attachment]
	run _alert_handle_slack "Test Subject" "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/html.html" ""
	[ "$status" -eq 0 ]
	# Verify curl was called with webhook URL (payload went through)
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"hooks.slack.com"* ]]
}

@test "handle_slack: slack channel registered at source time" {
	# Re-source the library to get fresh registrations
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	# Slack should be registered
	_alert_channel_find "slack"
	[ "$_ALERT_CHANNEL_IDX" -ge 0 ]
	# But disabled by default
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

@test "handle_slack: passes attachment through to deliver" {
	export ALERT_SLACK_MODE="bot"
	export ALERT_SLACK_TOKEN="xoxb-test-token"
	export ALERT_SLACK_CHANNEL="#alerts"
	# Need routing mock for post_message + upload
	alert_create_curl_routing_mock
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_1"
	echo '{"ok":true,"upload_url":"https://files.slack.com/upload/v1/abc","file_id":"F123"}' \
		> "$ALERT_MOCK_DIR/curl_response_2"
	echo 'ok' > "$ALERT_MOCK_DIR/curl_response_3"
	echo '{"ok":true}' > "$ALERT_MOCK_DIR/curl_response_4"

	run _alert_handle_slack "Subject" "$TEST_TMPDIR/payload.json" "" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 4 ]
}
