#!/usr/bin/env bats
# 06-discord.bats — Discord delivery tests

load helpers/alert-common

setup() {
	alert_common_setup
	alert_mock_setup

	# Create test payload file (Discord embed JSON)
	printf '{"embeds":[{"title":"Alert","description":"server down"}]}\n' > "$TEST_TMPDIR/payload.json"

	# Create test attachment file
	printf 'scan report content\n' > "$TEST_TMPDIR/attachment.txt"

	# Default curl mock with response support
	alert_create_curl_mock
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_discord_webhook
# ---------------------------------------------------------------------------

@test "discord_webhook: POSTs payload with Content-Type application/json" {
	echo '' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" "https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"Content-Type: application/json"* ]]
	[[ "$args" == *"-d"* ]]
	[[ "$args" == *"@$TEST_TMPDIR/payload.json"* ]]
}

@test "discord_webhook: returns 0 on empty response (HTTP 204 success)" {
	echo -n '' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" "https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 0 ]
}

@test "discord_webhook: returns 0 on JSON response with id field (message object)" {
	echo '{"id":"123456","content":"hello"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" "https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 0 ]
}

@test "discord_webhook: returns 1 on error JSON and extracts message field" {
	echo '{"message":"Invalid Webhook Token","code":50027}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" "https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Discord webhook error: Invalid Webhook Token"* ]]
}

@test "discord_webhook: invalid URL returns 1" {
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" "not-a-url"
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid or empty Discord webhook URL"* ]]
}

@test "discord_webhook: empty URL returns 1" {
	run _alert_discord_webhook "$TEST_TMPDIR/payload.json" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid or empty Discord webhook URL"* ]]
}

# ---------------------------------------------------------------------------
# _alert_discord_upload
# ---------------------------------------------------------------------------

@test "discord_upload: POSTs with -F payload_json and -F files[0]" {
	echo '{"id":"123456"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_upload "$TEST_TMPDIR/attachment.txt" "$TEST_TMPDIR/payload.json" \
		"https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"payload_json=<$TEST_TMPDIR/payload.json"* ]]
	[[ "$args" == *"files[0]=@$TEST_TMPDIR/attachment.txt"* ]]
}

@test "discord_upload: returns 0 on message object response" {
	echo '{"id":"789","attachments":[]}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_upload "$TEST_TMPDIR/attachment.txt" "$TEST_TMPDIR/payload.json" \
		"https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 0 ]
}

@test "discord_upload: file not found returns 1" {
	run _alert_discord_upload "/nonexistent/file.txt" "$TEST_TMPDIR/payload.json" \
		"https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 1 ]
	[[ "$output" == *"file not found"* ]]
}

@test "discord_upload: invalid URL returns 1" {
	run _alert_discord_upload "$TEST_TMPDIR/attachment.txt" "$TEST_TMPDIR/payload.json" "bad-url"
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid or empty Discord webhook URL"* ]]
}

@test "discord_upload: error JSON returns 1 with upload error message" {
	echo '{"message":"Request entity too large","code":40005}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_discord_upload "$TEST_TMPDIR/attachment.txt" "$TEST_TMPDIR/payload.json" \
		"https://discord.com/api/webhooks/123/abc"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Discord upload error: Request entity too large"* ]]
}

# ---------------------------------------------------------------------------
# _alert_deliver_discord
# ---------------------------------------------------------------------------

@test "deliver_discord: without attachment calls webhook (check -d in args, no -F)" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"-d"* ]]
	[[ "$args" != *"payload_json"* ]]
}

@test "deliver_discord: with attachment calls upload (check -F flags in args)" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '{"id":"123"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"payload_json"* ]]
	[[ "$args" == *"files[0]"* ]]
}

@test "deliver_discord: nonexistent attachment uses webhook path (only 1 curl call)" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	alert_create_curl_routing_mock
	echo '' > "$ALERT_MOCK_DIR/curl_response_1"
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json" "/nonexistent/file.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 1 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args_1")
	[[ "$args" == *"-d"* ]]
}

@test "deliver_discord: missing ALERT_DISCORD_WEBHOOK_URL returns 1" {
	unset ALERT_DISCORD_WEBHOOK_URL 2>/dev/null || true
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_DISCORD_WEBHOOK_URL not set"* ]]
}

@test "deliver_discord: webhook failure returns 1" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '{"message":"Unknown Webhook","code":10015}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json"
	[ "$status" -eq 1 ]
}

@test "deliver_discord: upload failure returns 1" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '{"message":"Request entity too large","code":40005}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_discord "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _alert_handle_discord + registration
# ---------------------------------------------------------------------------

@test "handle_discord: passes text_file as payload to deliver" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '' > "$ALERT_MOCK_DIR/curl_response"
	# Handler signature: subject text_file html_file [attachment]
	run _alert_handle_discord "Test Subject" "$TEST_TMPDIR/payload.json" "$TEST_TMPDIR/html.html" ""
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"@$TEST_TMPDIR/payload.json"* ]]
}

@test "handle_discord: passes attachment through" {
	export ALERT_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
	echo '{"id":"123"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_handle_discord "Subject" "$TEST_TMPDIR/payload.json" "" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"files[0]=@$TEST_TMPDIR/attachment.txt"* ]]
}

@test "handle_discord: discord channel registered at source time" {
	# Re-source the library to get fresh registrations
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	# Discord should be registered
	_alert_channel_find "discord"
	[ "$_ALERT_CHANNEL_IDX" -ge 0 ]
}

@test "handle_discord: registered but disabled by default" {
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	_alert_channel_find "discord"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

@test "handle_discord: handler function is _alert_handle_discord" {
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	_alert_channel_find "discord"
	[ "${_ALERT_CHANNEL_HANDLERS[$_ALERT_CHANNEL_IDX]}" = "_alert_handle_discord" ]
}
