#!/usr/bin/env bats
# 02-email.bats — MIME builder and email delivery tests

load helpers/alert-common

setup() {
	alert_common_setup
	alert_mock_setup

	# Create test content files
	printf 'Hello plain text\n' > "$TEST_TMPDIR/text.txt"
	printf '<html><body>Hello HTML</body></html>\n' > "$TEST_TMPDIR/html.html"

	# Default mock binaries (tests that need "missing" binaries remove them)
	alert_create_mock mail
	alert_create_mock sendmail
	alert_create_mock curl

	# Default email env vars
	export ALERT_SMTP_FROM="sender@example.com"
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_build_mime
# ---------------------------------------------------------------------------

@test "build_mime: produces MIME-Version header" {
	run _alert_build_mime "text body" "<html>html body</html>"
	[ "$status" -eq 0 ]
	[[ "$output" == *"MIME-Version: 1.0"* ]]
}

@test "build_mime: boundary starts with ALERT_ prefix" {
	run _alert_build_mime "text" "html"
	[ "$status" -eq 0 ]
	[[ "$output" == *'boundary="ALERT_'* ]]
}

@test "build_mime: contains text/plain and text/html content types" {
	run _alert_build_mime "text body" "<html>body</html>"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Content-Type: text/plain; charset=UTF-8"* ]]
	[[ "$output" == *"Content-Type: text/html; charset=UTF-8"* ]]
}

@test "build_mime: HTML part is base64-encoded" {
	run _alert_build_mime "text body" "<html>test</html>"
	[ "$status" -eq 0 ]
	# Decode the base64 portion and verify original content
	local b64
	b64=$(echo "$output" | sed -n '/Content-Type: text\/html/,/^--ALERT_/p' | grep -v 'Content-' | grep -v '^--' | grep -v '^$')
	local decoded
	decoded=$(echo "$b64" | base64 -d 2>/dev/null)
	[[ "$decoded" == *"<html>test</html>"* ]]
}

@test "build_mime: text body content is present in output" {
	run _alert_build_mime "This is the plain text body" "<html>html</html>"
	[ "$status" -eq 0 ]
	[[ "$output" == *"This is the plain text body"* ]]
}

# ---------------------------------------------------------------------------
# _alert_email_local
# ---------------------------------------------------------------------------

@test "email_local: text format calls mail with subject and recipient" {
	run _alert_email_local "user@test.com" "Test Subject" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# Verify mock mail was called
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/mail_args")
	[[ "$args" == *"-s"* ]]
	[[ "$args" == *"Test Subject"* ]]
	[[ "$args" == *"user@test.com"* ]]
}

@test "email_local: text format pipes text file content to mail" {
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/mail_stdin")
	[[ "$stdin_content" == *"Hello plain text"* ]]
}

@test "email_local: html format calls sendmail with HTML content-type" {
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Content-Type: text/html"* ]]
	[[ "$stdin_content" == *"From: sender@example.com"* ]]
}

@test "email_local: both format calls sendmail with multipart/alternative" {
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"multipart/alternative"* ]]
}

@test "email_local: html without sendmail falls back to text via mail" {
	rm -f "$MOCK_BIN/sendmail"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	# mail was called (fallback), not sendmail
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	[ ! -f "$ALERT_MOCK_DIR/sendmail_args" ]
	# stderr warns about fallback
	[[ "$output" == *"sendmail not found"* ]]
}

@test "email_local: both without sendmail falls back to text via mail" {
	rm -f "$MOCK_BIN/sendmail"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	[ ! -f "$ALERT_MOCK_DIR/sendmail_args" ]
}

@test "email_local: text without mail falls back to sendmail" {
	rm -f "$MOCK_BIN/mail"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
	[ ! -f "$ALERT_MOCK_DIR/mail_args" ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Subject: Test"* ]]
	[[ "$stdin_content" == *"Hello plain text"* ]]
}

@test "email_local: no mail or sendmail returns 1" {
	rm -f "$MOCK_BIN/mail" "$MOCK_BIN/sendmail"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 1 ]
	[[ "$output" == *"mail binary not found"* ]]
}

@test "email_local: unknown format returns 1" {
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "invalid"
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown format"* ]]
}

@test "email_local: uses ALERT_SMTP_FROM for From header" {
	export ALERT_SMTP_FROM="custom@example.com"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"From: custom@example.com"* ]]
}

# ---------------------------------------------------------------------------
# _alert_email_relay
# ---------------------------------------------------------------------------

@test "email_relay: calls curl with SMTP relay URL" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"--url"* ]]
	[[ "$args" == *"smtps://smtp.example.com:465"* ]]
}

@test "email_relay: smtps:// gets --ssl-reqd" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"--ssl-reqd"* ]]
}

@test "email_relay: smtp://:587 gets --ssl-reqd" {
	export ALERT_SMTP_RELAY="smtp://smtp.example.com:587"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"--ssl-reqd"* ]]
}

@test "email_relay: smtp://:25 does NOT get --ssl-reqd" {
	export ALERT_SMTP_RELAY="smtp://relay.internal:25"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" != *"--ssl-reqd"* ]]
}

@test "email_relay: includes credentials when ALERT_SMTP_USER/PASS set" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	export ALERT_SMTP_USER="myuser"
	export ALERT_SMTP_PASS="mypass"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" == *"--user"* ]]
	[[ "$args" == *"myuser:mypass"* ]]
}

@test "email_relay: omits credentials when ALERT_SMTP_USER/PASS unset" {
	export ALERT_SMTP_RELAY="smtp://relay.internal:25"
	unset ALERT_SMTP_USER ALERT_SMTP_PASS 2>/dev/null || true
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/curl_args")
	[[ "$args" != *"--user"* ]]
}

@test "email_relay: missing ALERT_SMTP_FROM returns 1 without calling curl" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	unset ALERT_SMTP_FROM 2>/dev/null || true
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 1 ]
	[[ "$output" == *"ALERT_SMTP_FROM not set"* ]]
	[ ! -f "$ALERT_MOCK_DIR/curl_args" ]
}

# ---------------------------------------------------------------------------
# _alert_deliver_email
# ---------------------------------------------------------------------------

@test "deliver_email: routes to local MTA when ALERT_SMTP_RELAY unset" {
	unset ALERT_SMTP_RELAY 2>/dev/null || true
	run _alert_deliver_email "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# mail was called (local path), not curl
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	[ ! -f "$ALERT_MOCK_DIR/curl_args" ]
}

@test "deliver_email: routes to relay when ALERT_SMTP_RELAY set" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	run _alert_deliver_email "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# curl was called (relay path)
	[ -f "$ALERT_MOCK_DIR/curl_args" ]
}

@test "deliver_email: relay path builds RFC 822 message with headers" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	# Use a mock curl that also captures the uploaded file content
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	# Find the --upload-file argument and copy its content
	while [ \$# -gt 0 ]; do
		if [ "\$1" = "--upload-file" ]; then
			cp "\$2" "$mock_dir/curl_uploaded" 2>/dev/null
			break
		fi
		shift
	done
	exit 0
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_deliver_email "user@test.com" "Test Subject" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_uploaded" ]
	local msg
	msg=$(cat "$ALERT_MOCK_DIR/curl_uploaded")
	[[ "$msg" == *"From: sender@example.com"* ]]
	[[ "$msg" == *"To: user@test.com"* ]]
	[[ "$msg" == *"Subject: Test Subject"* ]]
	[[ "$msg" == *"MIME-Version: 1.0"* ]]
}

@test "deliver_email: local path passes format argument through" {
	unset ALERT_SMTP_RELAY 2>/dev/null || true
	run _alert_deliver_email "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	# sendmail was called (html format via local path)
	[ -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Content-Type: text/html"* ]]
}

@test "deliver_email: relay path cleans up temp msg_file" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	run _alert_deliver_email "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# No alert_relay_msg temp files should remain
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_relay_msg.*' 2>/dev/null)
	[ -z "$leftover" ]
}

# ---------------------------------------------------------------------------
# Error / negative tests
# ---------------------------------------------------------------------------

@test "email_relay: curl not found returns 1" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	rm -f "$MOCK_BIN/curl"
	# Restrict PATH so command -v curl fails; restore after run so teardown works
	local saved_path="$PATH"
	export PATH="$MOCK_BIN"
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	export PATH="$saved_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"curl not found"* ]]
}

@test "email_relay: curl failure returns 1 with error on stderr" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	# Create a failing curl mock
	alert_create_mock curl 7
	run _alert_email_relay "user@test.com" "Test" "$TEST_TMPDIR/text.txt"
	[ "$status" -eq 1 ]
	[[ "$output" == *"SMTP relay to user@test.com failed"* ]]
	[[ "$output" == *"curl exit 7"* ]]
}

@test "email_local: mail failure propagates exit code" {
	alert_create_mock mail 1
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# ALERT_EMAIL_REPLY_TO header support
# ---------------------------------------------------------------------------

@test "email_local: html format includes Reply-To when ALERT_EMAIL_REPLY_TO set" {
	export ALERT_EMAIL_REPLY_TO="replyto@example.com"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Reply-To: replyto@example.com"* ]]
}

@test "email_local: both format includes Reply-To when ALERT_EMAIL_REPLY_TO set" {
	export ALERT_EMAIL_REPLY_TO="replyto@example.com"
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Reply-To: replyto@example.com"* ]]
}

@test "email_local: html format omits Reply-To when ALERT_EMAIL_REPLY_TO unset" {
	unset ALERT_EMAIL_REPLY_TO 2>/dev/null || true
	run _alert_email_local "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "html"
	[ "$status" -eq 0 ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" != *"Reply-To:"* ]]
}

@test "deliver_email: relay path includes Reply-To when ALERT_EMAIL_REPLY_TO set" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	export ALERT_EMAIL_REPLY_TO="replyto@example.com"
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	while [ \$# -gt 0 ]; do
		if [ "\$1" = "--upload-file" ]; then
			cp "\$2" "$mock_dir/curl_uploaded" 2>/dev/null
			break
		fi
		shift
	done
	exit 0
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	run _alert_deliver_email "user@test.com" "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_uploaded" ]
	local msg
	msg=$(cat "$ALERT_MOCK_DIR/curl_uploaded")
	[[ "$msg" == *"Reply-To: replyto@example.com"* ]]
}

# ---------------------------------------------------------------------------
# Subject CR/LF sanitization
# ---------------------------------------------------------------------------

@test "deliver_email: strips CR from subject" {
	unset ALERT_SMTP_RELAY 2>/dev/null || true
	local subj
	subj=$(printf 'Test\rInjected')
	run _alert_deliver_email "user@test.com" "$subj" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# Mock writes one arg per line — check subject is sanitized (CR stripped)
	grep -qF 'TestInjected' "$ALERT_MOCK_DIR/mail_args"
}

@test "deliver_email: strips LF from subject" {
	unset ALERT_SMTP_RELAY 2>/dev/null || true
	local subj
	subj=$(printf 'Test\nInjected')
	run _alert_deliver_email "user@test.com" "$subj" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "text"
	[ "$status" -eq 0 ]
	# Mock writes one arg per line — check that "TestInjected" appears as a single arg
	# (no LF embedded within the subject value)
	grep -qF 'TestInjected' "$ALERT_MOCK_DIR/mail_args"
}

@test "deliver_email: strips CR/LF from subject in relay path" {
	export ALERT_SMTP_RELAY="smtps://smtp.example.com:465"
	local mock_dir="$ALERT_MOCK_DIR"
	cat > "$MOCK_BIN/curl" <<-ENDMOCK
	#!/bin/bash
	printf '%s\n' "\$@" > "$mock_dir/curl_args"
	while [ \$# -gt 0 ]; do
		if [ "\$1" = "--upload-file" ]; then
			cp "\$2" "$mock_dir/curl_uploaded" 2>/dev/null
			break
		fi
		shift
	done
	exit 0
	ENDMOCK
	chmod +x "$MOCK_BIN/curl"

	local subj
	subj=$(printf 'Test\r\nInjected: evil')
	run _alert_deliver_email "user@test.com" "$subj" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html" "both"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/curl_uploaded" ]
	local msg
	msg=$(cat "$ALERT_MOCK_DIR/curl_uploaded")
	[[ "$msg" == *"Subject: TestInjected: evil"* ]]
	# No bare CR or LF in Subject line
	local subj_line
	subj_line=$(grep '^Subject:' "$ALERT_MOCK_DIR/curl_uploaded")
	[[ "$subj_line" != *$'\r'* ]]
}
