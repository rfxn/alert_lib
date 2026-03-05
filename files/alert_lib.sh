#!/bin/bash
# alert_lib.sh — shared library for multi-channel transactional alerting
# Provides channel registry, template engine, MIME builder, and multi-channel
# delivery (email, Slack, Telegram, Discord).
# Consumed by BFD and LMD via source inclusion.
#
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
#                         Ryan MacDonald <ryan@rfxn.com>
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# Source guard — prevent double-sourcing
[[ -n "${_ALERT_LIB_LOADED:-}" ]] && return 0 2>/dev/null
_ALERT_LIB_LOADED=1

# shellcheck disable=SC2034
ALERT_LIB_VERSION="1.0.0"

# Channel registry — consuming projects populate via alert_channel_register()
# Uses parallel indexed arrays instead of declare -A to avoid scope issues
# when sourced from inside a function (e.g., BATS load, wrapper functions).
# Simple array assignment creates globals; declare -A creates locals in functions.
_ALERT_CHANNEL_NAMES=()
_ALERT_CHANNEL_HANDLERS=()
_ALERT_CHANNEL_ENABLED=()

# Configurable defaults — consuming projects override via environment
ALERT_CURL_TIMEOUT="${ALERT_CURL_TIMEOUT:-30}"
ALERT_CURL_MAX_TIME="${ALERT_CURL_MAX_TIME:-120}"
ALERT_TMPDIR="${ALERT_TMPDIR:-${TMPDIR:-/tmp}}"

# ---------------------------------------------------------------------------
# Template Engine
# ---------------------------------------------------------------------------

# _alert_tpl_render template_file — render template by replacing {{VAR}} tokens
# with values from exported environment variables. Single-pass awk using
# ENVIRON array. Unknown/unset tokens become empty strings.
# Safe: no shell code execution, no eval, mawk-compatible.
# Output goes to stdout.
_alert_tpl_render() {
	local template_file="$1"
	if [ ! -f "$template_file" ]; then
		return 1
	fi
	awk '{
		line = $0
		while (match(line, /\{\{[A-Z_][A-Z0-9_]*\}\}/)) {
			token = substr(line, RSTART + 2, RLENGTH - 4)
			val = ENVIRON[token]
			line = substr(line, 1, RSTART - 1) val substr(line, RSTART + RLENGTH)
		}
		print line
	}' "$template_file"
}

# _alert_tpl_resolve template_dir template_name — resolve template with custom.d/ override
# If $template_dir/custom.d/$template_name exists, uses that path (user override).
# Otherwise uses $template_dir/$template_name (shipped default).
# Sets _ALERT_TPL_RESOLVED (avoids subshell fork from stdout return).
_alert_tpl_resolve() {
	local template_dir="$1" template_name="$2"
	_ALERT_TPL_RESOLVED="$template_dir/$template_name"
	if [ -f "$template_dir/custom.d/$template_name" ]; then
		_ALERT_TPL_RESOLVED="$template_dir/custom.d/$template_name"
	fi
}

# ---------------------------------------------------------------------------
# Escaping Functions
# ---------------------------------------------------------------------------

# _alert_html_escape str — escape HTML special characters for safe embedding
# Handles: & < > " ' (& first to avoid double-escaping)
# Uses sed for portable behavior across bash versions (bash 5.2 changed
# & semantics in ${var//pat/rep} to act as a backreference).
# Output goes to stdout.
_alert_html_escape() {
	if [ -z "$1" ]; then
		echo ""
		return 0
	fi
	printf '%s\n' "$1" | sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g' \
		-e 's/"/\&quot;/g' \
		-e "s/'/\\&#39;/g"
}

# _alert_json_escape str — escape special characters for safe JSON string embedding
# Handles: \ " newline tab carriage-return (\ first to avoid double-escaping)
# Uses ${var//} parameter expansion — no & in replacements, safe on all bash versions.
# Output goes to stdout (no trailing newline).
_alert_json_escape() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//$'\n'/\\n}"
	s="${s//$'\t'/\\t}"
	s="${s//$'\r'/\\r}"
	printf '%s' "$s"
}

# _alert_telegram_escape str — escape Telegram MarkdownV2 special characters
# Handles: \ _ * [ ] ( ) ~ ` > # + - = | { } . ! (\ first to avoid double-escaping)
# Character list per Telegram Bot API: https://core.telegram.org/bots/api#markdownv2-style
# Uses sed for consistent escaping approach across all alert_lib escape functions.
# Output goes to stdout.
_alert_telegram_escape() {
	if [ -z "$1" ]; then
		printf ''
		return 0
	fi
	# Escape backslash first, then all MarkdownV2 special chars via BRE character class.
	# Class layout: ] first (BRE literal), [ next, remaining chars, - last (BRE literal).
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/[][_*()~`>#+=|{}.!-]/\\&/g'
}

# _alert_slack_escape str — escape Slack mrkdwn special characters
# Handles: & < > → &amp; &lt; &gt; (& first to avoid double-escaping)
# Uses sed because replacement strings contain & (bash 5.2 backreference issue).
# Output goes to stdout.
_alert_slack_escape() {
	if [ -z "$1" ]; then
		printf ''
		return 0
	fi
	printf '%s' "$1" | sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g'
}
