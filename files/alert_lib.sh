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
# Channel Registry
# ---------------------------------------------------------------------------

# _alert_channel_find name — locate channel index by name
# Linear scan of _ALERT_CHANNEL_NAMES. Sets _ALERT_CHANNEL_IDX on success
# (avoids subshell fork from stdout return, same pattern as _ALERT_TPL_RESOLVED).
# Returns 0 if found, 1 if not found.
_alert_channel_find() {
	local name="$1"
	local i
	_ALERT_CHANNEL_IDX=-1
	for i in "${!_ALERT_CHANNEL_NAMES[@]}"; do
		if [ "${_ALERT_CHANNEL_NAMES[$i]}" = "$name" ]; then
			_ALERT_CHANNEL_IDX=$i
			return 0
		fi
	done
	return 1
}

# alert_channel_register name handler_fn — register a delivery channel
# Appends to parallel indexed arrays. Channel starts disabled (enabled=0).
# Returns 1 if name is empty, handler_fn is empty, or name already registered.
alert_channel_register() {
	local name="$1" handler_fn="$2"
	if [ -z "$name" ]; then
		echo "alert_lib: channel name cannot be empty." >&2
		return 1
	fi
	if [ -z "$handler_fn" ]; then
		echo "alert_lib: handler function cannot be empty for channel '$name'." >&2
		return 1
	fi
	if _alert_channel_find "$name"; then
		echo "alert_lib: channel '$name' already registered." >&2
		return 1
	fi
	_ALERT_CHANNEL_NAMES+=("$name")
	_ALERT_CHANNEL_HANDLERS+=("$handler_fn")
	_ALERT_CHANNEL_ENABLED+=("0")
	return 0
}

# alert_channel_enable name — mark channel as active
# Returns 1 if channel not registered.
alert_channel_enable() {
	local name="$1"
	if ! _alert_channel_find "$name"; then
		echo "alert_lib: channel '$name' not registered." >&2
		return 1
	fi
	_ALERT_CHANNEL_ENABLED[_ALERT_CHANNEL_IDX]=1
	return 0
}

# alert_channel_disable name — mark channel as inactive
# Returns 1 if channel not registered.
alert_channel_disable() {
	local name="$1"
	if ! _alert_channel_find "$name"; then
		echo "alert_lib: channel '$name' not registered." >&2
		return 1
	fi
	_ALERT_CHANNEL_ENABLED[_ALERT_CHANNEL_IDX]=0
	return 0
}

# alert_channel_enabled name — check if channel is active
# Returns 0 if enabled, 1 if disabled or not found.
alert_channel_enabled() {
	local name="$1"
	if ! _alert_channel_find "$name"; then
		return 1
	fi
	[ "${_ALERT_CHANNEL_ENABLED[_ALERT_CHANNEL_IDX]}" = "1" ]
}

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

# ---------------------------------------------------------------------------
# MIME Builder
# ---------------------------------------------------------------------------

# _alert_build_mime text_body html_body — construct multipart/alternative MIME message
# Writes MIME headers and both text and HTML parts to stdout.
# Caller is responsible for adding Subject/To/From headers before this output.
# The boundary uses epoch+PID for uniqueness (sufficient for email context).
_alert_build_mime() {
	local text_body="$1" html_body="$2"
	local boundary
	boundary="ALERT_$(date +%s)_$$"

	echo "MIME-Version: 1.0"
	echo "Content-Type: multipart/alternative; boundary=\"$boundary\""
	echo ""
	echo "--$boundary"
	echo "Content-Type: text/plain; charset=UTF-8"
	echo "Content-Transfer-Encoding: 8bit"
	echo ""
	echo "$text_body"
	echo ""
	echo "--$boundary"
	echo "Content-Type: text/html; charset=UTF-8"
	echo "Content-Transfer-Encoding: base64"
	echo ""
	# base64 wraps at 76 chars, satisfying RFC 5321 998-char line limit
	printf '%s\n' "$html_body" | base64
	echo ""
	echo "--${boundary}--"
}

# ---------------------------------------------------------------------------
# Email Delivery
# ---------------------------------------------------------------------------

# _alert_email_local recip subject text_file html_file format
# Send alert via local MTA (mail/sendmail). Format: text, html, or both.
# Returns 0 on success, 1 on failure.
_alert_email_local() {
	local recip="$1" subject="$2" text_file="$3" html_file="$4" format="${5:-text}"
	local from="${ALERT_SMTP_FROM:-root@$(hostname -f 2>/dev/null || hostname)}"
	local sendmail_bin mail_bin
	sendmail_bin=$(command -v sendmail 2>/dev/null || true)
	mail_bin=$(command -v mail 2>/dev/null || true)

	case "$format" in
		text)
			if [ -z "$mail_bin" ]; then
				echo "alert_lib: mail binary not found, cannot send alert to $recip." >&2
				return 1
			fi
			"$mail_bin" -s "$subject" "$recip" < "$text_file"
			return $?
			;;
		html)
			if [ -n "$sendmail_bin" ]; then
				{
					echo "From: $from"
					echo "To: $recip"
					echo "Subject: $subject"
					echo "Content-Type: text/html; charset=UTF-8"
					echo "Content-Transfer-Encoding: base64"
					echo ""
					# base64 wraps at 76 chars, satisfying RFC 5321 998-char line limit
					base64 < "$html_file"
				} | "$sendmail_bin" -t -oi
				return $?
			fi
			# sendmail not available — fall back to text via mail
			echo "alert_lib: warning: sendmail not found, falling back to text-only alert for $recip." >&2
			if [ -z "$mail_bin" ]; then
				echo "alert_lib: mail binary not found, cannot send alert to $recip." >&2
				return 1
			fi
			"$mail_bin" -s "$subject" "$recip" < "$text_file"
			return $?
			;;
		both)
			if [ -n "$sendmail_bin" ]; then
				local text_body html_body
				text_body=$(cat "$text_file")
				html_body=$(cat "$html_file")
				{
					echo "From: $from"
					echo "To: $recip"
					echo "Subject: $subject"
					_alert_build_mime "$text_body" "$html_body"
				} | "$sendmail_bin" -t -oi
				return $?
			fi
			# sendmail not available — fall back to text via mail
			echo "alert_lib: warning: sendmail not found, falling back to text-only alert for $recip." >&2
			if [ -z "$mail_bin" ]; then
				echo "alert_lib: mail binary not found, cannot send alert to $recip." >&2
				return 1
			fi
			"$mail_bin" -s "$subject" "$recip" < "$text_file"
			return $?
			;;
		*)
			echo "alert_lib: unknown format '$format', cannot send alert." >&2
			return 1
			;;
	esac
}

# _alert_email_relay recip subject msg_file — send via authenticated SMTP relay
# msg_file must be a complete RFC 822 message (headers + body).
# TLS handling: smtps:// always uses implicit TLS; smtp://:587 requires STARTTLS;
# smtp://:25 connects plaintext (for internal relays). Credentials are optional
# to support auth-free internal relays.
# Returns 0 on success, 1 on failure.
_alert_email_relay() {
	local recip="$1" subject="$2" msg_file="$3"

	if [ -z "${ALERT_SMTP_FROM:-}" ]; then
		echo "alert_lib: ALERT_SMTP_FROM not set, cannot send relay alert to $recip." >&2
		return 1
	fi
	local curl_bin
	curl_bin=$(command -v curl 2>/dev/null || true)
	if [ -z "$curl_bin" ]; then
		echo "alert_lib: curl not found, cannot send relay alert to $recip." >&2
		return 1
	fi

	# build curl arguments
	local -a curl_args=("--url" "$ALERT_SMTP_RELAY")

	# TLS: smtps:// and smtp://:587 require TLS; smtp://:25 is plain
	case "$ALERT_SMTP_RELAY" in
		smtps://*|smtp://*:587|smtp://*:587/*) curl_args+=("--ssl-reqd") ;;
		smtp://*:25|smtp://*:25/*) ;;  # plain — no TLS for internal relays
		*) curl_args+=("--ssl-reqd") ;;  # default: require TLS for safety
	esac

	curl_args+=("--mail-from" "$ALERT_SMTP_FROM" "--mail-rcpt" "$recip")

	# credentials are optional — auth-free internal relays omit them
	if [ -n "${ALERT_SMTP_USER:-}" ] && [ -n "${ALERT_SMTP_PASS:-}" ]; then
		curl_args+=("--user" "$ALERT_SMTP_USER:$ALERT_SMTP_PASS")
	fi

	curl_args+=("--upload-file" "$msg_file")

	local rc=0 curl_stderr
	curl_stderr=$(mktemp "${ALERT_TMPDIR}/alert_curl_err.XXXXXX")
	"$curl_bin" "${curl_args[@]}" 2>"$curl_stderr" || rc=$?
	if [ "$rc" -ne 0 ]; then
		local _err_detail
		_err_detail=$(head -5 "$curl_stderr" | tr '\n' ' ')
		echo "alert_lib: SMTP relay to $recip failed (curl exit $rc): $_err_detail" >&2
		rm -f "$curl_stderr"
		return 1
	fi
	rm -f "$curl_stderr"
	return 0
}

# _alert_deliver_email recip subject text_file html_file format
# Router: ALERT_SMTP_RELAY set → relay path, else → local MTA.
# Returns 0 on success, 1 on failure.
_alert_deliver_email() {
	local recip="$1" subject="$2" text_file="$3" html_file="$4" format="${5:-text}"

	if [ -n "${ALERT_SMTP_RELAY:-}" ]; then
		# relay path: always build full multipart MIME message
		local from="${ALERT_SMTP_FROM:-root@$(hostname -f 2>/dev/null || hostname)}"
		local text_body html_body
		text_body=$(cat "$text_file")
		html_body=$(cat "$html_file")
		local msg_file
		msg_file=$(mktemp "${ALERT_TMPDIR}/alert_relay_msg.XXXXXX")
		{
			echo "From: $from"
			echo "To: $recip"
			echo "Subject: $subject"
			echo "Date: $(date -R 2>/dev/null || date)"
			_alert_build_mime "$text_body" "$html_body"
		} > "$msg_file"
		_alert_email_relay "$recip" "$subject" "$msg_file"
		local rc=$?
		rm -f "$msg_file"
		return $rc
	fi

	# local MTA path
	_alert_email_local "$recip" "$subject" "$text_file" "$html_file" "$format"
}

# ---------------------------------------------------------------------------
# Email Channel Handler
# ---------------------------------------------------------------------------

# _alert_handle_email subject text_file html_file [attachment]
# Standardized handler wrapper for the email channel. Reads delivery config
# from environment variables and delegates to _alert_deliver_email.
# ALERT_EMAIL_TO: recipient address (default: root)
# ALERT_EMAIL_FORMAT: text, html, or both (default: text)
_alert_handle_email() {
	local subject="$1" text_file="$2" html_file="$3"
	local recip="${ALERT_EMAIL_TO:-root}"
	local format="${ALERT_EMAIL_FORMAT:-text}"
	_alert_deliver_email "$recip" "$subject" "$text_file" "$html_file" "$format"
}

# ---------------------------------------------------------------------------
# Multi-Channel Dispatch
# ---------------------------------------------------------------------------

# alert_dispatch template_dir subject [channels] [attachment_file]
# Render per-channel templates and dispatch to all enabled channels.
# channels: comma-separated channel names or "all" (default: "all").
# For each enabled channel, resolves $channel.text.tpl (falling back to
# $channel.message.tpl) and $channel.html.tpl from template_dir, renders
# via _alert_tpl_render, then calls the channel handler with:
#   handler_fn subject text_file html_file [attachment]
# Channels with no matching templates are skipped with a warning.
# Returns 0 if all dispatched channels succeed, 1 if any fail.
# Continues dispatching after individual channel failures.
alert_dispatch() {
	local template_dir="$1" subject="$2" channels="${3:-all}" attachment="${4:-}"
	local rc=0
	local i name handler enabled
	local text_file html_file

	for i in "${!_ALERT_CHANNEL_NAMES[@]}"; do
		name="${_ALERT_CHANNEL_NAMES[$i]}"
		handler="${_ALERT_CHANNEL_HANDLERS[$i]}"
		enabled="${_ALERT_CHANNEL_ENABLED[$i]}"

		# Skip disabled channels
		[ "$enabled" = "1" ] || continue

		# Filter by channel name (unless "all")
		if [ "$channels" != "all" ]; then
			case ",$channels," in
				*",$name,"*) ;;
				*) continue ;;
			esac
		fi

		# Resolve text template: try $channel.text.tpl, fall back to $channel.message.tpl
		text_file=""
		_alert_tpl_resolve "$template_dir" "${name}.text.tpl"
		if [ -f "$_ALERT_TPL_RESOLVED" ]; then
			text_file=$(mktemp "${ALERT_TMPDIR}/alert_${name}_text.XXXXXX")
			_alert_tpl_render "$_ALERT_TPL_RESOLVED" > "$text_file"
		else
			_alert_tpl_resolve "$template_dir" "${name}.message.tpl"
			if [ -f "$_ALERT_TPL_RESOLVED" ]; then
				text_file=$(mktemp "${ALERT_TMPDIR}/alert_${name}_text.XXXXXX")
				_alert_tpl_render "$_ALERT_TPL_RESOLVED" > "$text_file"
			fi
		fi

		# Resolve html template (optional)
		html_file=""
		_alert_tpl_resolve "$template_dir" "${name}.html.tpl"
		if [ -f "$_ALERT_TPL_RESOLVED" ]; then
			html_file=$(mktemp "${ALERT_TMPDIR}/alert_${name}_html.XXXXXX")
			_alert_tpl_render "$_ALERT_TPL_RESOLVED" > "$html_file"
		fi

		# Skip channels with no templates
		if [ -z "$text_file" ] && [ -z "$html_file" ]; then
			echo "alert_lib: no templates found for channel '$name', skipping." >&2
			continue
		fi

		# Create empty placeholders for missing variants so handlers get valid paths
		if [ -z "$text_file" ]; then
			text_file=$(mktemp "${ALERT_TMPDIR}/alert_${name}_text.XXXXXX")
		fi
		if [ -z "$html_file" ]; then
			html_file=$(mktemp "${ALERT_TMPDIR}/alert_${name}_html.XXXXXX")
		fi

		# Call handler
		if ! "$handler" "$subject" "$text_file" "$html_file" "$attachment"; then
			echo "alert_lib: channel '$name' delivery failed." >&2
			rc=1
		fi

		# Clean up rendered temp files
		rm -f "$text_file" "$html_file"
	done

	return $rc
}

# ---------------------------------------------------------------------------
# Built-in Channel Registration
# ---------------------------------------------------------------------------

# Register email channel — consumers enable via alert_channel_enable "email"
# Other built-in channels (slack, telegram, discord) registered in their
# respective delivery sections.
alert_channel_register "email" "_alert_handle_email"
