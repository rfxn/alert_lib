#!/usr/bin/env bats
# 05-telegram.bats — Telegram delivery tests

load helpers/alert-common

setup() {
	alert_common_setup
	alert_mock_setup

	# Create test message file (MarkdownV2 content)
	printf 'Alert\\: server *down*\n' > "$TEST_TMPDIR/message.txt"

	# Create test attachment file
	printf 'scan report content\n' > "$TEST_TMPDIR/attachment.txt"

	# Default curl mock with response support
	alert_create_curl_mock
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_telegram_api — security and core behavior
# ---------------------------------------------------------------------------

@test "telegram_api: uses -K flag (token NOT in command line args)" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	# Custom curl mock that captures args and -K file content
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	# Capture -K config file content before library deletes it
	while [ \$# -gt 0 ]; do
		case "\$1" in
			-K)
				shift
				if [ -f "\$1" ]; then
					cp "\$1" "$mock_dir/curl_kfile_content"
					stat -c '%a' "\$1" > "$mock_dir/curl_kfile_perms"
				fi
				;;
		esac
		shift
	done
	cat "$mock_dir/curl_response"
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 0 ]
	# Token must NOT appear in the args (would be visible in ps)
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" != *"123456:ABC-DEF"* ]]
	# But -K flag must be present
	[[ "$args" == *"-K"* ]]
}

@test "telegram_api: bot token appears in -K config file content" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	while [ \$# -gt 0 ]; do
		case "\$1" in
			-K)
				shift
				if [ -f "\$1" ]; then
					cp "\$1" "$mock_dir/curl_kfile_content"
				fi
				;;
		esac
		shift
	done
	cat "$mock_dir/curl_response"
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_kfile_content" ]
	local content
	content=$(cat "$ALERT_MOCK_DIR/curl_kfile_content")
	[[ "$content" == *"bot123456:ABC-DEF/sendMessage"* ]]
}

@test "telegram_api: config file has chmod 600 permissions" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	while [ \$# -gt 0 ]; do
		case "\$1" in
			-K)
				shift
				if [ -f "\$1" ]; then
					stat -c '%a' "\$1" > "$mock_dir/curl_kfile_perms"
				fi
				;;
		esac
		shift
	done
	cat "$mock_dir/curl_response"
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_kfile_perms" ]
	local perms
	perms=$(cat "$ALERT_MOCK_DIR/curl_kfile_perms")
	[ "$perms" = "600" ]
}

@test "telegram_api: config file cleaned up after success" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	_alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789" > /dev/null
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_tg_curl.*' 2>/dev/null)
	[ -z "$leftover" ]
}

@test "telegram_api: config file cleaned up after curl failure" {
	alert_create_curl_mock 7
	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 1 ]
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_tg_curl.*' 2>/dev/null)
	[ -z "$leftover" ]
}

@test "telegram_api: curl not found returns 1" {
	rm -f "$MOCK_BIN/curl"
	local saved_path="$PATH"
	export PATH="$MOCK_BIN"
	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	export PATH="$saved_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"curl not found"* ]]
}

@test "telegram_api: curl failure returns 1 with exit code" {
	alert_create_curl_mock 7
	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Telegram API curl failed (exit 7)"* ]]
}

@test "telegram_api: API error returns 1 and extracts description" {
	echo '{"ok":false,"description":"Unauthorized"}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_api "sendMessage" "bad-token" -F "chat_id=789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Telegram API error: Unauthorized"* ]]
}

@test "telegram_api: API success returns 0" {
	echo '{"ok":true,"result":{"message_id":42}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" -F "chat_id=789"
	[ "$status" -eq 0 ]
}

@test "telegram_api: passes extra -F flags through to curl" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_api "sendMessage" "123456:ABC-DEF" \
		-F "chat_id=789" -F "text=hello" -F "parse_mode=MarkdownV2"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"chat_id=789"* ]]
	[[ "$args" == *"text=hello"* ]]
	[[ "$args" == *"parse_mode=MarkdownV2"* ]]
}

# ---------------------------------------------------------------------------
# _alert_telegram_message
# ---------------------------------------------------------------------------

@test "telegram_message: sends parse_mode=MarkdownV2 as form field" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_message "hello world" "123456:ABC-DEF" "789"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"parse_mode=MarkdownV2"* ]]
}

@test "telegram_message: sends chat_id as form field" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_message "hello" "123456:ABC-DEF" "-1001234567890"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"chat_id=-1001234567890"* ]]
}

@test "telegram_message: sends text as form field" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_message "Alert\\: test message" "123456:ABC-DEF" "789"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"text=Alert"* ]]
}

@test "telegram_message: missing bot_token returns 1" {
	run _alert_telegram_message "hello" "" "789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"bot token is required"* ]]
}

@test "telegram_message: missing chat_id returns 1" {
	run _alert_telegram_message "hello" "123456:ABC-DEF" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"chat_id is required"* ]]
}

@test "telegram_message: empty text returns 1" {
	run _alert_telegram_message "" "123456:ABC-DEF" "789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"text cannot be empty"* ]]
}

# ---------------------------------------------------------------------------
# _alert_telegram_document
# ---------------------------------------------------------------------------

@test "telegram_document: sends document=@file as form field" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_document "$TEST_TMPDIR/attachment.txt" "" "123456:ABC-DEF" "789"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"document=@$TEST_TMPDIR/attachment.txt"* ]]
}

@test "telegram_document: sends chat_id as form field" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_document "$TEST_TMPDIR/attachment.txt" "" "123456:ABC-DEF" "-1001234567890"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"chat_id=-1001234567890"* ]]
}

@test "telegram_document: sends caption when provided" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_document "$TEST_TMPDIR/attachment.txt" "Scan Report" "123456:ABC-DEF" "789"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"caption=Scan Report"* ]]
}

@test "telegram_document: omits caption when empty" {
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_telegram_document "$TEST_TMPDIR/attachment.txt" "" "123456:ABC-DEF" "789"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" != *"caption="* ]]
}

@test "telegram_document: file not found returns 1" {
	run _alert_telegram_document "/nonexistent/file.txt" "" "123456:ABC-DEF" "789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"file not found"* ]]
}

@test "telegram_document: missing bot_token returns 1" {
	run _alert_telegram_document "$TEST_TMPDIR/attachment.txt" "" "" "789"
	[ "$status" -eq 1 ]
	[[ "$output" == *"bot token is required"* ]]
}

# ---------------------------------------------------------------------------
# _alert_deliver_telegram
# ---------------------------------------------------------------------------

@test "deliver_telegram: sends message from payload file content" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	# The text content from the file should be passed as a form field
	[[ "$args" == *"text="* ]]
}

@test "deliver_telegram: with attachment sends message + document" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_1"
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_2"

	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 2 ]

	# Call 1 should be sendMessage
	local args1
	args1=$(cat "$ALERT_MOCK_DIR/curl_args_1")
	[[ "$args1" == *"text="* ]]

	# Call 2 should be sendDocument
	local args2
	args2=$(cat "$ALERT_MOCK_DIR/curl_args_2")
	[[ "$args2" == *"document=@"* ]]
}

@test "deliver_telegram: without attachment only 1 curl call" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_1"

	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 1 ]
}

@test "deliver_telegram: nonexistent attachment only 1 curl call" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_1"

	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt" "/nonexistent/file.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 1 ]
}

@test "deliver_telegram: missing ALERT_TELEGRAM_BOT_TOKEN returns 1" {
	unset ALERT_TELEGRAM_BOT_TOKEN 2>/dev/null || true
	export ALERT_TELEGRAM_CHAT_ID="789"
	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_TELEGRAM_BOT_TOKEN not set"* ]]
}

@test "deliver_telegram: missing ALERT_TELEGRAM_CHAT_ID returns 1" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	unset ALERT_TELEGRAM_CHAT_ID 2>/dev/null || true
	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_TELEGRAM_CHAT_ID not set"* ]]
}

@test "deliver_telegram: message failure returns 1 without attempting document" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":false,"description":"Bad Request"}' > "$ALERT_MOCK_DIR/curl_response_1"

	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 1 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 1 ]
}

@test "deliver_telegram: document failure returns 1 even after message success" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_1"
	echo '{"ok":false,"description":"file too large"}' > "$ALERT_MOCK_DIR/curl_response_2"

	run _alert_deliver_telegram "$TEST_TMPDIR/message.txt" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _alert_handle_telegram + registration
# ---------------------------------------------------------------------------

@test "handle_telegram: passes text_file as payload to deliver" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response"
	# Handler signature: subject text_file html_file [attachment]
	run _alert_handle_telegram "Test Subject" "$TEST_TMPDIR/message.txt" "$TEST_TMPDIR/html.html" ""
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"text="* ]]
}

@test "handle_telegram: passes attachment through" {
	export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF"
	export ALERT_TELEGRAM_CHAT_ID="789"
	alert_create_curl_routing_mock
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_1"
	echo '{"ok":true,"result":{}}' > "$ALERT_MOCK_DIR/curl_response_2"

	run _alert_handle_telegram "Subject" "$TEST_TMPDIR/message.txt" "" "$TEST_TMPDIR/attachment.txt"
	[ "$status" -eq 0 ]
	local count
	count=$(cat "$ALERT_MOCK_DIR/curl_call_count")
	[ "$count" -eq 2 ]
}

@test "handle_telegram: telegram channel registered at source time" {
	# Re-source the library to get fresh registrations
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	# Telegram should be registered
	_alert_channel_find "telegram"
	[ "$_ALERT_CHANNEL_IDX" -ge 0 ]
}

@test "handle_telegram: registered but disabled by default" {
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	_alert_channel_find "telegram"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

@test "handle_telegram: handler function is _alert_handle_telegram" {
	unset _ALERT_LIB_LOADED
	_ALERT_CHANNEL_NAMES=()
	_ALERT_CHANNEL_HANDLERS=()
	_ALERT_CHANNEL_ENABLED=()
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/alert_lib.sh"
	_alert_channel_find "telegram"
	[ "${_ALERT_CHANNEL_HANDLERS[$_ALERT_CHANNEL_IDX]}" = "_alert_handle_telegram" ]
}
