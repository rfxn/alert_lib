#!/usr/bin/env bats
# 01-core.bats — template engine and escaping function tests

load helpers/alert-common

setup() {
	alert_common_setup
}

teardown() {
	alert_teardown
}

# ---------------------------------------------------------------------------
# _alert_tpl_render
# ---------------------------------------------------------------------------

@test "tpl_render: basic single-variable substitution" {
	printf 'Hello {{NAME}}\n' > "$TEST_TMPDIR/tpl"
	export NAME="world"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "Hello world" ]
}

@test "tpl_render: multiple variables on one line" {
	printf '{{FIRST}} and {{SECOND}}\n' > "$TEST_TMPDIR/tpl"
	export FIRST="alpha"
	export SECOND="beta"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "alpha and beta" ]
}

@test "tpl_render: multi-line template" {
	printf 'Line1: {{A}}\nLine2: {{B}}\n' > "$TEST_TMPDIR/tpl"
	export A="first"
	export B="second"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Line1: first" ]
	[ "${lines[1]}" = "Line2: second" ]
}

@test "tpl_render: adjacent variables with no separator" {
	printf '{{X}}{{Y}}\n' > "$TEST_TMPDIR/tpl"
	export X="hello"
	export Y="world"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "helloworld" ]
}

@test "tpl_render: variable at start and end of line" {
	printf '{{START}}middle{{END}}\n' > "$TEST_TMPDIR/tpl"
	export START="["
	export END="]"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "[middle]" ]
}

@test "tpl_render: unknown variable becomes empty string" {
	printf 'before{{UNKNOWN}}after\n' > "$TEST_TMPDIR/tpl"
	unset UNKNOWN 2>/dev/null || true
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "beforeafter" ]
}

@test "tpl_render: missing template file returns 1" {
	run _alert_tpl_render "$TEST_TMPDIR/nonexistent"
	[ "$status" -eq 1 ]
}

@test "tpl_render: template with no variables passes through unchanged" {
	printf 'plain text line\n' > "$TEST_TMPDIR/tpl"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "plain text line" ]
}

@test "tpl_render: empty template produces no output" {
	: > "$TEST_TMPDIR/tpl"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "tpl_render: NEGATIVE — lowercase tokens are NOT substituted" {
	printf '{{lower}}\n' > "$TEST_TMPDIR/tpl"
	export lower="should not appear"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "{{lower}}" ]
}

@test "tpl_render: NEGATIVE — digit-leading tokens are NOT substituted" {
	printf '{{1VAR}}\n' > "$TEST_TMPDIR/tpl"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	[ "$output" = "{{1VAR}}" ]
}

@test "tpl_render: NEGATIVE — shell commands are NOT executed" {
	printf '{{$(whoami)}}\n' > "$TEST_TMPDIR/tpl"
	run _alert_tpl_render "$TEST_TMPDIR/tpl"
	[ "$status" -eq 0 ]
	# output must contain the literal token, not a username
	[[ "$output" == *'$'* ]] || [[ "$output" == *'{{'* ]]
}

# ---------------------------------------------------------------------------
# _alert_tpl_resolve
# ---------------------------------------------------------------------------

@test "tpl_resolve: default path when no custom.d/ override" {
	mkdir -p "$TEST_TMPDIR/templates"
	printf 'default\n' > "$TEST_TMPDIR/templates/test.tpl"
	_alert_tpl_resolve "$TEST_TMPDIR/templates" "test.tpl"
	[ "$_ALERT_TPL_RESOLVED" = "$TEST_TMPDIR/templates/test.tpl" ]
}

@test "tpl_resolve: custom.d/ override takes precedence" {
	mkdir -p "$TEST_TMPDIR/templates/custom.d"
	printf 'default\n' > "$TEST_TMPDIR/templates/test.tpl"
	printf 'custom\n' > "$TEST_TMPDIR/templates/custom.d/test.tpl"
	_alert_tpl_resolve "$TEST_TMPDIR/templates" "test.tpl"
	[ "$_ALERT_TPL_RESOLVED" = "$TEST_TMPDIR/templates/custom.d/test.tpl" ]
}

@test "tpl_resolve: sets _ALERT_TPL_RESOLVED variable" {
	mkdir -p "$TEST_TMPDIR/templates"
	printf 'content\n' > "$TEST_TMPDIR/templates/msg.tpl"
	_ALERT_TPL_RESOLVED=""
	_alert_tpl_resolve "$TEST_TMPDIR/templates" "msg.tpl"
	[ -n "$_ALERT_TPL_RESOLVED" ]
	[[ "$_ALERT_TPL_RESOLVED" == *"/msg.tpl" ]]
}

@test "tpl_resolve: render integration — resolve then render" {
	mkdir -p "$TEST_TMPDIR/templates"
	printf 'Hello {{WHO}}\n' > "$TEST_TMPDIR/templates/greet.tpl"
	export WHO="test"
	_alert_tpl_resolve "$TEST_TMPDIR/templates" "greet.tpl"
	run _alert_tpl_render "$_ALERT_TPL_RESOLVED"
	[ "$status" -eq 0 ]
	[ "$output" = "Hello test" ]
}

# ---------------------------------------------------------------------------
# _alert_html_escape
# ---------------------------------------------------------------------------

@test "html_escape: escapes all five HTML special characters" {
	run _alert_html_escape '&<>"'"'"
	[ "$status" -eq 0 ]
	[ "$output" = '&amp;&lt;&gt;&quot;&#39;' ]
}

@test "html_escape: empty input returns empty output" {
	run _alert_html_escape ""
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "html_escape: string without special chars passes through" {
	run _alert_html_escape "hello world 123"
	[ "$status" -eq 0 ]
	[ "$output" = "hello world 123" ]
}

@test "html_escape: NEGATIVE — ampersand escaped before angle brackets (no double-escape)" {
	run _alert_html_escape "&<"
	[ "$status" -eq 0 ]
	# Must be &amp;&lt; not &amp;lt;
	[ "$output" = "&amp;&lt;" ]
}

# ---------------------------------------------------------------------------
# _alert_json_escape
# ---------------------------------------------------------------------------

@test "json_escape: escapes backslash, quote, newline, tab, carriage-return" {
	local input
	input=$(printf 'a\\b"c\nd\te\r')
	run _alert_json_escape "$input"
	[ "$status" -eq 0 ]
	[ "$output" = 'a\\b\"c\nd\te\r' ]
}

@test "json_escape: empty input returns empty output" {
	run _alert_json_escape ""
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "json_escape: string without special chars passes through" {
	run _alert_json_escape "hello world 123"
	[ "$status" -eq 0 ]
	[ "$output" = "hello world 123" ]
}

@test "json_escape: NEGATIVE — backslash escaped before quote (no double-escape)" {
	# Input: literal backslash followed by quote: \"
	local input='\"'
	run _alert_json_escape "$input"
	[ "$status" -eq 0 ]
	# Must be \\\" (escaped-backslash then escaped-quote), not just \"
	[ "$output" = '\\\"' ]
}

# ---------------------------------------------------------------------------
# _alert_telegram_escape
# ---------------------------------------------------------------------------

@test "telegram_escape: escapes all MarkdownV2 special characters" {
	run _alert_telegram_escape '_*[]()~`>#+-=|{}.!'
	[ "$status" -eq 0 ]
	[ "$output" = '\_\*\[\]\(\)\~\`\>\#\+\-\=\|\{\}\.\!' ]
}

@test "telegram_escape: escapes backslash" {
	run _alert_telegram_escape '\'
	[ "$status" -eq 0 ]
	[ "$output" = '\\' ]
}

@test "telegram_escape: empty input returns empty output" {
	run _alert_telegram_escape ""
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "telegram_escape: string without special chars passes through" {
	run _alert_telegram_escape "hello world 123"
	[ "$status" -eq 0 ]
	[ "$output" = "hello world 123" ]
}

@test "telegram_escape: NEGATIVE — backslash escaped before underscore (no double-escape)" {
	# Input: literal \_ (backslash then underscore)
	run _alert_telegram_escape '\_'
	[ "$status" -eq 0 ]
	# Must be \\\_ (escaped-backslash then escaped-underscore)
	[ "$output" = '\\\_' ]
}

# ---------------------------------------------------------------------------
# _alert_slack_escape
# ---------------------------------------------------------------------------

@test "slack_escape: escapes ampersand, less-than, greater-than" {
	run _alert_slack_escape '&<>'
	[ "$status" -eq 0 ]
	[ "$output" = '&amp;&lt;&gt;' ]
}

@test "slack_escape: empty input returns empty output" {
	run _alert_slack_escape ""
	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "slack_escape: string without special chars passes through" {
	run _alert_slack_escape "hello world 123"
	[ "$status" -eq 0 ]
	[ "$output" = "hello world 123" ]
}

@test "slack_escape: NEGATIVE — ampersand escaped before angle brackets (no double-escape)" {
	run _alert_slack_escape "&<"
	[ "$status" -eq 0 ]
	# Must be &amp;&lt; not &amp;lt;
	[ "$output" = "&amp;&lt;" ]
}

# ---------------------------------------------------------------------------
# _alert_redact_url
# ---------------------------------------------------------------------------

@test "redact_url: passes non-secret Slack API URL unchanged" {
	run _alert_redact_url "https://slack.com/api/chat.postMessage"
	[ "$status" -eq 0 ]
	[ "$output" = "https://slack.com/api/chat.postMessage" ]
}

@test "redact_url: redacts Slack webhook token" {
	run _alert_redact_url "https://hooks.slack.com/services/T00000000/B00000000/xyzSecretToken"
	[ "$status" -eq 0 ]
	[ "$output" = "https://hooks.slack.com/services/T00000000/B00000000/[REDACTED]" ]
}

@test "redact_url: redacts Discord webhook token" {
	run _alert_redact_url "https://discord.com/api/webhooks/123456789/abcSecretToken"
	[ "$status" -eq 0 ]
	[ "$output" = "https://discord.com/api/webhooks/123456789/[REDACTED]" ]
}

@test "redact_url: redacts discordapp.com webhook token" {
	run _alert_redact_url "https://discordapp.com/api/webhooks/123456789/abcSecretToken"
	[ "$status" -eq 0 ]
	[ "$output" = "https://discordapp.com/api/webhooks/123456789/[REDACTED]" ]
}

@test "redact_url: passes generic HTTPS URL unchanged" {
	run _alert_redact_url "https://example.com/api/endpoint"
	[ "$status" -eq 0 ]
	[ "$output" = "https://example.com/api/endpoint" ]
}
