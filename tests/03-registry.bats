#!/usr/bin/env bats
# 03-registry.bats — channel registry, email handler, and dispatch tests

load helpers/alert-common

setup() {
	alert_common_setup
	alert_mock_setup
	# Default mock binaries for email handler tests
	alert_create_mock mail
	alert_create_mock sendmail
	export ALERT_SMTP_FROM="sender@example.com"
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# alert_channel_register
# ---------------------------------------------------------------------------

@test "register: adds channel name to _ALERT_CHANNEL_NAMES" {
	alert_channel_register "testch" "my_handler"
	[[ " ${_ALERT_CHANNEL_NAMES[*]} " == *" testch "* ]]
}

@test "register: stores handler function in _ALERT_CHANNEL_HANDLERS" {
	alert_channel_register "testch" "my_handler"
	_alert_channel_find "testch"
	[ "${_ALERT_CHANNEL_HANDLERS[$_ALERT_CHANNEL_IDX]}" = "my_handler" ]
}

@test "register: channel starts disabled" {
	alert_channel_register "testch" "my_handler"
	_alert_channel_find "testch"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

@test "register: multiple channels register correctly" {
	alert_channel_register "ch1" "handler1"
	alert_channel_register "ch2" "handler2"
	alert_channel_register "ch3" "handler3"
	[ "${#_ALERT_CHANNEL_NAMES[@]}" -eq 3 ]
	_alert_channel_find "ch2"
	[ "${_ALERT_CHANNEL_HANDLERS[$_ALERT_CHANNEL_IDX]}" = "handler2" ]
}

@test "register: duplicate name returns 1" {
	alert_channel_register "testch" "handler1"
	run alert_channel_register "testch" "handler2"
	[ "$status" -eq 1 ]
	[[ "$output" == *"already registered"* ]]
}

@test "register: empty name returns 1" {
	run alert_channel_register "" "my_handler"
	[ "$status" -eq 1 ]
	[[ "$output" == *"name cannot be empty"* ]]
}

@test "register: empty handler returns 1" {
	run alert_channel_register "testch" ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"handler function cannot be empty"* ]]
}

# ---------------------------------------------------------------------------
# alert_channel_enable / alert_channel_disable
# ---------------------------------------------------------------------------

@test "enable: sets channel enabled flag to 1" {
	alert_channel_register "testch" "my_handler"
	alert_channel_enable "testch"
	_alert_channel_find "testch"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "1" ]
}

@test "disable: sets channel enabled flag to 0" {
	alert_channel_register "testch" "my_handler"
	alert_channel_enable "testch"
	alert_channel_disable "testch"
	_alert_channel_find "testch"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

@test "enable: unknown channel returns 1" {
	run alert_channel_enable "nonexistent"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not registered"* ]]
}

@test "disable: unknown channel returns 1" {
	run alert_channel_disable "nonexistent"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not registered"* ]]
}

@test "enable: idempotent — enabling already-enabled channel succeeds" {
	alert_channel_register "testch" "my_handler"
	alert_channel_enable "testch"
	alert_channel_enable "testch"
	_alert_channel_find "testch"
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "1" ]
}

@test "disable: idempotent — disabling already-disabled channel succeeds" {
	alert_channel_register "testch" "my_handler"
	run alert_channel_disable "testch"
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# alert_channel_enabled
# ---------------------------------------------------------------------------

@test "enabled: returns 0 for enabled channel" {
	alert_channel_register "testch" "my_handler"
	alert_channel_enable "testch"
	alert_channel_enabled "testch"
}

@test "enabled: returns 1 for disabled channel" {
	alert_channel_register "testch" "my_handler"
	run alert_channel_enabled "testch"
	[ "$status" -eq 1 ]
}

@test "enabled: returns 1 for unknown channel" {
	run alert_channel_enabled "nonexistent"
	[ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Built-in email channel registration
# ---------------------------------------------------------------------------

@test "builtin: email channel registered at source time" {
	# Re-source to get built-in registration (setup clears arrays)
	# shellcheck disable=SC1090
	unset _ALERT_LIB_LOADED
	source "$PROJECT_ROOT/files/alert_lib.sh"
	_alert_channel_find "email"
	[ "${_ALERT_CHANNEL_HANDLERS[$_ALERT_CHANNEL_IDX]}" = "_alert_handle_email" ]
	# Starts disabled
	[ "${_ALERT_CHANNEL_ENABLED[$_ALERT_CHANNEL_IDX]}" = "0" ]
}

# ---------------------------------------------------------------------------
# _alert_handle_email
# ---------------------------------------------------------------------------

@test "handle_email: calls deliver_email with ALERT_EMAIL_TO" {
	export ALERT_EMAIL_TO="user@test.com"
	export ALERT_EMAIL_FORMAT="text"
	printf 'test content\n' > "$TEST_TMPDIR/text.txt"
	printf '<html>test</html>\n' > "$TEST_TMPDIR/html.html"
	run _alert_handle_email "Test Subject" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html"
	[ "$status" -eq 0 ]
	# mail was called (text format via local MTA)
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/mail_args")
	[[ "$args" == *"user@test.com"* ]]
	[[ "$args" == *"Test Subject"* ]]
}

@test "handle_email: uses ALERT_EMAIL_FORMAT for delivery" {
	export ALERT_EMAIL_TO="user@test.com"
	export ALERT_EMAIL_FORMAT="html"
	printf 'test content\n' > "$TEST_TMPDIR/text.txt"
	printf '<html>test</html>\n' > "$TEST_TMPDIR/html.html"
	run _alert_handle_email "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html"
	[ "$status" -eq 0 ]
	# sendmail was called (html format)
	[ -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
	local stdin_content
	stdin_content=$(cat "$ALERT_MOCK_DIR/sendmail_stdin")
	[[ "$stdin_content" == *"Content-Type: text/html"* ]]
}

@test "handle_email: defaults to root when ALERT_EMAIL_TO unset" {
	unset ALERT_EMAIL_TO 2>/dev/null || true
	export ALERT_EMAIL_FORMAT="text"
	printf 'test\n' > "$TEST_TMPDIR/text.txt"
	printf '<html></html>\n' > "$TEST_TMPDIR/html.html"
	run _alert_handle_email "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html"
	[ "$status" -eq 0 ]
	local args
	args=$(cat "$ALERT_MOCK_DIR/mail_args")
	[[ "$args" == *"root"* ]]
}

@test "handle_email: defaults to text when ALERT_EMAIL_FORMAT unset" {
	export ALERT_EMAIL_TO="user@test.com"
	unset ALERT_EMAIL_FORMAT 2>/dev/null || true
	printf 'test\n' > "$TEST_TMPDIR/text.txt"
	printf '<html></html>\n' > "$TEST_TMPDIR/html.html"
	run _alert_handle_email "Test" "$TEST_TMPDIR/text.txt" "$TEST_TMPDIR/html.html"
	[ "$status" -eq 0 ]
	# mail called (text format is default)
	[ -f "$ALERT_MOCK_DIR/mail_args" ]
	[ ! -f "$ALERT_MOCK_DIR/sendmail_stdin" ]
}

# ---------------------------------------------------------------------------
# alert_dispatch
# ---------------------------------------------------------------------------

@test "dispatch: calls handler for enabled channel" {
	# Define mock handler that records its call
	mock_handler() {
		echo "called:$1" > "$ALERT_MOCK_DIR/dispatch_call"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "hello" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "TestSubj" "testch"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/dispatch_call" ]
	[[ "$(cat "$ALERT_MOCK_DIR/dispatch_call")" == "called:TestSubj" ]]
}

@test "dispatch: skips disabled channel" {
	mock_handler() {
		echo "called" > "$ALERT_MOCK_DIR/dispatch_call"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	# NOT enabled
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "hello" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "TestSubj" "testch"
	[ "$status" -eq 0 ]
	[ ! -f "$ALERT_MOCK_DIR/dispatch_call" ]
}

@test "dispatch: filters by channel name" {
	handler_a() { echo "a" > "$ALERT_MOCK_DIR/dispatch_a"; return 0; }
	handler_b() { echo "b" > "$ALERT_MOCK_DIR/dispatch_b"; return 0; }
	alert_channel_register "cha" "handler_a"
	alert_channel_register "chb" "handler_b"
	alert_channel_enable "cha"
	alert_channel_enable "chb"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "a content" > "$TEST_TMPDIR/tpl/cha.text.tpl"
	echo "b content" > "$TEST_TMPDIR/tpl/chb.text.tpl"
	# Only dispatch to cha
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "cha"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/dispatch_a" ]
	[ ! -f "$ALERT_MOCK_DIR/dispatch_b" ]
}

@test "dispatch: 'all' dispatches to all enabled channels" {
	handler_a() { echo "a" > "$ALERT_MOCK_DIR/dispatch_a"; return 0; }
	handler_b() { echo "b" > "$ALERT_MOCK_DIR/dispatch_b"; return 0; }
	alert_channel_register "cha" "handler_a"
	alert_channel_register "chb" "handler_b"
	alert_channel_enable "cha"
	alert_channel_enable "chb"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "a" > "$TEST_TMPDIR/tpl/cha.text.tpl"
	echo "b" > "$TEST_TMPDIR/tpl/chb.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "all"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/dispatch_a" ]
	[ -f "$ALERT_MOCK_DIR/dispatch_b" ]
}

@test "dispatch: renders text template with variable substitution" {
	mock_handler() {
		# Copy the rendered text file for inspection
		cp "$2" "$ALERT_MOCK_DIR/rendered_text"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "Hello {{GREET_NAME}}" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	export GREET_NAME="World"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/rendered_text" ]
	[[ "$(cat "$ALERT_MOCK_DIR/rendered_text")" == "Hello World" ]]
}

@test "dispatch: renders html template" {
	mock_handler() {
		cp "$3" "$ALERT_MOCK_DIR/rendered_html"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "text content" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	echo "<html>{{TITLE}}</html>" > "$TEST_TMPDIR/tpl/testch.html.tpl"
	export TITLE="My Title"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/rendered_html" ]
	[[ "$(cat "$ALERT_MOCK_DIR/rendered_html")" == "<html>My Title</html>" ]]
}

@test "dispatch: uses custom.d/ template override" {
	mock_handler() {
		cp "$2" "$ALERT_MOCK_DIR/rendered_text"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl/custom.d"
	echo "default content" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	echo "custom content" > "$TEST_TMPDIR/tpl/custom.d/testch.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	[[ "$(cat "$ALERT_MOCK_DIR/rendered_text")" == "custom content" ]]
}

@test "dispatch: falls back to .message.tpl when .text.tpl missing" {
	mock_handler() {
		cp "$2" "$ALERT_MOCK_DIR/rendered_text"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "message content" > "$TEST_TMPDIR/tpl/testch.message.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	[[ "$(cat "$ALERT_MOCK_DIR/rendered_text")" == "message content" ]]
}

@test "dispatch: skips channel with no templates" {
	mock_handler() {
		echo "called" > "$ALERT_MOCK_DIR/dispatch_call"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	# No templates for testch
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	[ ! -f "$ALERT_MOCK_DIR/dispatch_call" ]
	[[ "$output" == *"no templates found"* ]]
}

@test "dispatch: passes attachment to handler" {
	mock_handler() {
		echo "attach:$4" > "$ALERT_MOCK_DIR/dispatch_call"
		return 0
	}
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "text" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	echo "attachment data" > "$TEST_TMPDIR/attach.log"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch" "$TEST_TMPDIR/attach.log"
	[ "$status" -eq 0 ]
	[[ "$(cat "$ALERT_MOCK_DIR/dispatch_call")" == "attach:$TEST_TMPDIR/attach.log" ]]
}

@test "dispatch: returns 0 when all channels succeed" {
	mock_handler() { return 0; }
	alert_channel_register "ch1" "mock_handler"
	alert_channel_register "ch2" "mock_handler"
	alert_channel_enable "ch1"
	alert_channel_enable "ch2"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "a" > "$TEST_TMPDIR/tpl/ch1.text.tpl"
	echo "b" > "$TEST_TMPDIR/tpl/ch2.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "all"
	[ "$status" -eq 0 ]
}

@test "dispatch: returns 1 when handler fails" {
	fail_handler() { return 1; }
	alert_channel_register "testch" "fail_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "text" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 1 ]
	[[ "$output" == *"delivery failed"* ]]
}

@test "dispatch: continues to remaining channels after failure" {
	fail_handler() { return 1; }
	ok_handler() { echo "ok" > "$ALERT_MOCK_DIR/dispatch_ok"; return 0; }
	alert_channel_register "fail" "fail_handler"
	alert_channel_register "ok" "ok_handler"
	alert_channel_enable "fail"
	alert_channel_enable "ok"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "f" > "$TEST_TMPDIR/tpl/fail.text.tpl"
	echo "o" > "$TEST_TMPDIR/tpl/ok.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "all"
	[ "$status" -eq 1 ]
	# The ok channel still ran despite the fail channel
	[ -f "$ALERT_MOCK_DIR/dispatch_ok" ]
}

@test "dispatch: cleans up rendered temp files" {
	mock_handler() { return 0; }
	alert_channel_register "testch" "mock_handler"
	alert_channel_enable "testch"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "text" > "$TEST_TMPDIR/tpl/testch.text.tpl"
	echo "<html>html</html>" > "$TEST_TMPDIR/tpl/testch.html.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "testch"
	[ "$status" -eq 0 ]
	# No alert_testch_ temp files should remain
	local leftover
	leftover=$(find "$TEST_TMPDIR" -name 'alert_testch_*' 2>/dev/null)
	[ -z "$leftover" ]
}

@test "dispatch: comma-separated channels dispatches to listed channels only" {
	handler_a() { echo "a" > "$ALERT_MOCK_DIR/dispatch_a"; return 0; }
	handler_b() { echo "b" > "$ALERT_MOCK_DIR/dispatch_b"; return 0; }
	handler_c() { echo "c" > "$ALERT_MOCK_DIR/dispatch_c"; return 0; }
	alert_channel_register "cha" "handler_a"
	alert_channel_register "chb" "handler_b"
	alert_channel_register "chc" "handler_c"
	alert_channel_enable "cha"
	alert_channel_enable "chb"
	alert_channel_enable "chc"
	mkdir -p "$TEST_TMPDIR/tpl"
	echo "a" > "$TEST_TMPDIR/tpl/cha.text.tpl"
	echo "b" > "$TEST_TMPDIR/tpl/chb.text.tpl"
	echo "c" > "$TEST_TMPDIR/tpl/chc.text.tpl"
	run alert_dispatch "$TEST_TMPDIR/tpl" "Subj" "cha,chc"
	[ "$status" -eq 0 ]
	[ -f "$ALERT_MOCK_DIR/dispatch_a" ]
	[ ! -f "$ALERT_MOCK_DIR/dispatch_b" ]
	[ -f "$ALERT_MOCK_DIR/dispatch_c" ]
}
