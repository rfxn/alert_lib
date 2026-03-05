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
