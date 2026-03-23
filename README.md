# alert_lib — Multi-Channel Transactional Alerting for Bash

<p align="center">
  <a href="https://github.com/rfxn/alert_lib/actions/workflows/ci.yml"><img src="https://github.com/rfxn/alert_lib/actions/workflows/ci.yml/badge.svg?style=flat-square" alt="CI"></a>
  <a href="CHANGELOG"><img src="https://img.shields.io/badge/version-1.0.5-blue.svg?style=flat-square" alt="Version"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/bash-4.1%2B-green.svg?style=flat-square" alt="Bash"></a>
  <a href="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"><img src="https://img.shields.io/badge/license-GPL%20v2-orange.svg?style=flat-square" alt="License"></a>
</p>

**Multi-channel transactional alerting library for Bash** -- email, Slack,
Telegram, Discord with template engine, digest/spool, and SMTP relay.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com> / Licensed under GNU GPL v2

---

## Quick Start

Source `alert_lib.sh` into your Bash script and call functions directly. This
avoids fork/exec overhead — each call is a function invocation, not a subprocess.

```bash
#!/bin/bash
source /opt/myapp/lib/alert_lib.sh

# Enable channels
alert_channel_enable "email"
alert_channel_enable "slack"

# Configure via environment variables
export ALERT_EMAIL_TO="admin@example.com"
export ALERT_SLACK_MODE="webhook"
export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"

# Export template variables
export HOSTNAME
export EVENT_SUMMARY="Brute force detected from 198.51.100.10"

# Dispatch — renders per-channel templates and delivers to all enabled channels
alert_dispatch "/opt/myapp/templates" "Security Alert"
```

For each enabled channel, `alert_dispatch` resolves templates from the
template directory, renders `{{VAR}}` tokens from exported environment
variables, and calls the channel's handler function.

---

## 1. Introduction

alert_lib is a shared Bash library for multi-channel transactional alerting.
Source it into your script, enable channels, set environment variables, and
call `alert_dispatch` to render templates and deliver alerts to email, Slack,
Telegram, and Discord — all from a single call.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection) and
[LMD](https://github.com/rfxn/linux-malware-detect) via source inclusion.

- **Multi-channel delivery** — email, Slack, Telegram, and Discord out of the box
- **Channel registry** — register, enable, disable, and dispatch to channels
  by name; add custom channels with a handler function
- **Template engine** — awk-based `{{VAR}}` substitution from environment
  variables; `custom.d/` override directories for user-modified templates
- **Platform-specific escaping** — HTML entities, JSON strings, Telegram
  MarkdownV2, and Slack mrkdwn
- **MIME builder** — multipart/alternative email with base64 HTML part
- **Email delivery** — local MTA (mail/sendmail) with format-based routing
  and graceful fallback; SMTP relay via curl with TLS auto-detection
- **Slack** — incoming webhooks, Bot API (chat.postMessage), and 3-step
  file upload (getUploadURLExternal workflow)
- **Telegram** — Bot API with `-K` config file pattern keeping tokens out of
  the process listing; sendMessage (MarkdownV2) and sendDocument
- **Discord** — webhook JSON POST and single-request multipart file upload
- **Digest/spool system** — flock-based timestamped accumulation with
  age-based flush triggering and consumer-provided callback
- **Zero project-specific references** — all context via env vars and arguments
- **Bash 4.1+ compatible** — CentOS 6 floor, mawk-compatible awk

### 1.1 Supported Systems

alert_lib targets deep legacy through current production distributions:

| Distribution | Versions | Bash | Notes |
|---|---|---|---|
| CentOS | 6, 7 | 4.1, 4.2 | Bash 4.1 floor target |
| Rocky Linux | 8, 9, 10 | 4.4, 5.1, 5.2 | Primary RHEL-family targets |
| Debian | 12 | 5.2 | Primary test target |
| Ubuntu | 12.04, 14.04, 20.04, 24.04 | 4.2–5.2 | Deep legacy through current LTS |
| Slackware, Gentoo, FreeBSD | Various | 4.1+ | Functional where Bash is available |

**Minimum requirement: Bash 4.1** (ships with CentOS 6, released 2011). No
Bash 4.2+ features are used — no `${var,,}`, `mapfile -d`, `declare -n`, or
`$EPOCHSECONDS`. The `flock` command (util-linux) is required for digest/spool
functions; `curl` is required for Slack, Telegram, Discord, and SMTP relay.

## 2. Installation

alert_lib is designed to be embedded in consuming projects, not installed
standalone. Copy the library into your project tree:

```bash
cp files/alert_lib.sh /opt/myapp/lib/
chown root:root /opt/myapp/lib/alert_lib.sh
chmod 640 /opt/myapp/lib/alert_lib.sh
```

Then source it from your application:

```bash
source /opt/myapp/lib/alert_lib.sh
```

No standalone CLI — alert_lib is a pure library. All configuration comes
from environment variables set by the consuming project.

### 2.1 Prerequisites

- **Bash 4.1+** (CentOS 6 ships 4.1.2 — the minimum supported version)
- **curl** — required for Slack, Telegram, Discord, and SMTP relay delivery
- **flock** (util-linux) — required for digest/spool concurrency control
- **mail or sendmail** — required for local MTA email delivery (optional if
  using SMTP relay exclusively)

### 2.2 Integration Steps

Copy `alert_lib.sh` into your project's library directory. The file has no
external dependencies beyond the prerequisites above.

```bash
cp files/alert_lib.sh /opt/myapp/lib/alert_lib.sh
chown root:root /opt/myapp/lib/alert_lib.sh
chmod 640 /opt/myapp/lib/alert_lib.sh
```

Create a template directory and add per-channel templates. See
`examples/templates/` in this repository for working examples.

```bash
mkdir -p /opt/myapp/templates/custom.d
cp examples/templates/email.text.tpl /opt/myapp/templates/
cp examples/templates/slack.text.tpl /opt/myapp/templates/
```

Templates use `{{VAR}}` tokens replaced from exported environment variables.
Place user-modified templates in `custom.d/` to survive upgrades.

Source the library early in your script, then set environment variables and
enable channels before dispatching.

```bash
#!/bin/bash
source /opt/myapp/lib/alert_lib.sh

# Set delivery configuration
export ALERT_EMAIL_TO="admin@example.com"
export ALERT_SLACK_MODE="webhook"
export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"

# Enable desired channels
alert_channel_enable "email"
alert_channel_enable "slack"
```

Export the variables referenced in your templates, then call `alert_dispatch`.

```bash
export HOSTNAME
export EVENT_SUMMARY="Brute force detected from 198.51.100.10"
export TIMESTAMP
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

alert_dispatch "/opt/myapp/templates" "Security Alert"
```

### 2.3 Error Handling

`alert_dispatch` returns 0 on full success, 1 if any channel failed. It
continues dispatching after individual failures, so partial delivery is
possible. Check the return code and handle accordingly.

```bash
if ! alert_dispatch "/opt/myapp/templates" "Alert Subject"; then
    echo "WARNING: one or more alert channels failed" >&2
    # Log the failure, retry later, or escalate
fi
```

For per-channel error handling, call delivery functions directly instead of
using `alert_dispatch`.

### 2.4 Reference Integrations

- **BFD** — sources `alert_lib.sh` from `files/internals/`, wraps it with
  `bfd_alert.sh` for BFD-specific template variable setup and digest
  integration. See the BFD `files/internals/bfd_alert.sh` module.
- **LMD** — sources `alert_lib.sh` from `$inspath/internals/`, configures
  channels from `conf.maldet` variables, and dispatches after scan completion.

## 3. Configuration

alert_lib is configured entirely through environment variables. Set these
before calling any delivery or dispatch functions.

| Variable | Default | Purpose |
|----------|---------|---------|
| `ALERT_CURL_TIMEOUT` | `30` | curl `--connect-timeout` in seconds |
| `ALERT_CURL_MAX_TIME` | `120` | curl `--max-time` in seconds |
| `ALERT_TMPDIR` | `$TMPDIR` or `/tmp` | Temp file directory for rendered templates and curl stderr |
| `ALERT_SMTP_FROM` | `root@$(hostname)` | Email From address (relay and local sendmail) |
| `ALERT_SMTP_RELAY` | — | SMTP relay URL (e.g., `smtps://smtp.example.com:465`); unset = local MTA |
| `ALERT_SMTP_USER` | — | SMTP relay username (optional — auth-free relays omit) |
| `ALERT_SMTP_PASS` | — | SMTP relay password (optional) |
| `ALERT_EMAIL_TO` | `root` | Email recipient address |
| `ALERT_EMAIL_FORMAT` | `text` | Email format: `text`, `html`, or `both` |
| `ALERT_EMAIL_REPLY_TO` | — | Reply-To header address for email delivery (all paths) |
| `ALERT_SLACK_MODE` | `webhook` | Slack delivery mode: `webhook` or `bot` |
| `ALERT_SLACK_WEBHOOK_URL` | — | Slack incoming webhook URL (webhook mode) |
| `ALERT_SLACK_TOKEN` | — | Slack Bot API token (bot mode) |
| `ALERT_SLACK_CHANNEL` | — | Slack channel ID or name (bot mode) |
| `ALERT_TELEGRAM_BOT_TOKEN` | — | Telegram Bot API token |
| `ALERT_TELEGRAM_CHAT_ID` | — | Telegram chat/group/channel ID |
| `ALERT_DISCORD_WEBHOOK_URL` | — | Discord webhook URL |

## 4. Usage

alert_lib is a source-only library with no standalone CLI. All interaction
is through function calls after sourcing the library.

### 4.1 Dispatch Workflow

```
alert_dispatch(template_dir, subject, [channels], [attachment])
  → iterate enabled channels (optionally filtered by name)
    → resolve per-channel templates (custom.d/ override → default)
    → render templates via _alert_tpl_render (awk {{VAR}} substitution)
    → call channel handler with rendered files
    → continue on failure (fault-tolerant), return 1 if any channel failed
```

### 4.2 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Failure (missing config, delivery error, invalid arguments) |

`alert_dispatch` returns 1 if **any** channel fails but continues through all
enabled channels before returning.

## 5. Architecture

The internal structure of alert_lib and the contracts between components.

### 5.1 Channel Registry

Channels are stored in three parallel indexed arrays (not `declare -A`, which
creates locals when sourced from inside functions). Each channel has a name,
handler function, and enabled flag:

```
_ALERT_CHANNEL_NAMES=("email" "slack" "telegram" "discord")
_ALERT_CHANNEL_HANDLERS=("_alert_handle_email" "_alert_handle_slack" ...)
_ALERT_CHANNEL_ENABLED=("0" "0" "0" "0")
```

All four built-in channels are registered at source time but start disabled.
Consuming projects enable the ones they need.

### 5.2 Handler Interface

Every channel handler receives the same arguments:

```
handler_fn subject text_file html_file [attachment]
```

- `subject` — alert subject line
- `text_file` — path to rendered text template (or empty placeholder)
- `html_file` — path to rendered HTML template (or empty placeholder)
- `attachment` — optional file path for upload (Slack bot, Telegram, Discord)

### 5.3 Template Resolution

For each channel, dispatch resolves templates in this order:

1. `custom.d/$channel.text.tpl` (user override)
2. `$channel.text.tpl` (shipped default)
3. Falls back to `$channel.message.tpl` if no `.text.tpl` exists
4. `$channel.html.tpl` (optional, used by email)

Templates use `{{VAR}}` syntax — replaced by exported environment variables
via single-pass awk. Unknown tokens become empty strings.

## 6. API Reference

Public and internal function signatures for consumers who need direct
access outside the dispatch workflow.

### 6.1 Public Functions

These functions form the consumer-facing API (no underscore prefix).

**alert_channel_register(name, handler_fn)** — Register a delivery channel
with the given name and handler function. Returns 0 on success, 1 if name
is empty, handler is empty, or name already registered.

```bash
alert_channel_register "pagerduty" "_handle_pagerduty"
```

**alert_channel_enable(name)** — Enable a registered channel for dispatch.
Returns 0 on success, 1 if channel not registered.

```bash
alert_channel_enable "email"
alert_channel_enable "slack"
```

**alert_channel_disable(name)** — Disable a channel (remains registered but
skipped during dispatch). Returns 0 on success, 1 if channel not registered.

**alert_channel_enabled(name)** — Check if a channel is enabled. Returns 0
if enabled, 1 if disabled or not registered.

```bash
if alert_channel_enabled "slack"; then
    echo "Slack alerts are active"
fi
```

**alert_dispatch(template_dir, subject, [channels], [attachment])** — Render
per-channel templates and dispatch to all enabled channels. Returns 0 if all
channels succeed, 1 if any channel fails. Continues dispatching after
individual failures.

```bash
# All enabled channels
alert_dispatch "/opt/myapp/templates" "Server Alert"

# Specific channels only
alert_dispatch "/opt/myapp/templates" "Server Alert" "email,slack"

# With attachment
alert_dispatch "/opt/myapp/templates" "Scan Report" "all" "/tmp/report.txt"
```

### 6.2 Template Engine

**`_alert_tpl_render(template_file)`** — render template by replacing `{{VAR}}`
tokens with values from exported environment variables. Single-pass awk,
mawk-compatible. Unknown tokens become empty strings. Output to stdout.
Returns 1 if template file doesn't exist.

**`_alert_tpl_resolve(template_dir, template_name)`** — resolve template with
`custom.d/` override. Sets `_ALERT_TPL_RESOLVED` to the resolved path (avoids
subshell fork). Checks `$template_dir/custom.d/$template_name` first, falls
back to `$template_dir/$template_name`.

### 6.3 Escaping

All escape functions take a string argument and output the escaped result to
stdout.

**`_alert_html_escape(str)`** — escape `& < > " '` for HTML embedding. Uses
sed (safe across all bash versions including 5.2 backreference change).

**`_alert_json_escape(str)`** — escape `\ " \n \t \r` for JSON strings. Uses
parameter expansion (no `&` in replacements). Output has no trailing newline.

**`_alert_telegram_escape(str)`** — escape Telegram MarkdownV2 special
characters (19-char set per Bot API docs). Backslash-prefixed.

**`_alert_slack_escape(str)`** — escape `& < >` to `&amp; &lt; &gt;` for
Slack mrkdwn format.

### 6.4 HTTP Utilities

**`_alert_validate_url(url)`** — validate URL has `http://` or `https://`
scheme. Returns 0 if valid, 1 otherwise.

**`_alert_redact_url(url)`** — redact embedded tokens from known webhook URL
patterns. Slack webhooks (`hooks.slack.com/services/`) and Discord webhooks
(`discord.com/api/webhooks/`) have their final path segment replaced with
`[REDACTED]`. Non-secret URLs pass through unchanged.

**`_alert_curl_post(url, [curl_flags...])`** — HTTP POST via curl with
standard timeouts (`ALERT_CURL_TIMEOUT`, `ALERT_CURL_MAX_TIME`). Discovers
curl via `command -v`. Extra arguments pass through as curl flags. Returns
response body on stdout. Returns 1 on failure with error detail on stderr.

### 6.5 MIME

**`_alert_build_mime(text_body, html_body)`** — construct multipart/alternative
MIME message with text/plain and base64-encoded text/html parts. Output to
stdout. Caller adds Subject/To/From headers.

### 6.6 Email

**`_alert_email_local(recip, subject, text_file, html_file, format)`** — send
via local MTA. Format: `text` (mail), `html` (sendmail, falls back to text via
mail), `both` (sendmail MIME, falls back to text via mail).

**`_alert_email_relay(recip, subject, msg_file)`** — send via SMTP relay using
curl. TLS auto-detection: `smtps://` uses implicit TLS, port 587 requires
STARTTLS, port 25 is plaintext. Credentials optional (supports auth-free
internal relays).

**`_alert_deliver_email(recip, subject, text_file, html_file, format)`** —
router: `ALERT_SMTP_RELAY` set sends via relay path, otherwise local MTA.

**`_alert_handle_email(subject, text_file, html_file, [attachment])`** —
channel handler wrapper. Reads `ALERT_EMAIL_TO` (default: `root`) and
`ALERT_EMAIL_FORMAT` (default: `text`) from environment.

### 6.7 Slack

**`_alert_slack_webhook(payload_file, webhook_url)`** — POST JSON payload to
Slack incoming webhook. Validates URL scheme. Checks for `"ok"` response.

**`_alert_slack_post_message(payload_file, token, channel)`** — POST to
`chat.postMessage` API. Injects `"channel"` field into JSON payload.

**`_alert_slack_upload(file_path, title, token, channels)`** — 3-step file
upload: `getUploadURLExternal` → upload to presigned URL →
`completeUploadExternal`.

**`_alert_deliver_slack(payload_file, [attachment_file])`** — router:
`ALERT_SLACK_MODE=webhook` uses webhook URL, `bot` uses token + channel.
Webhook mode warns that file attachments are not supported.

**`_alert_handle_slack(subject, text_file, html_file, [attachment])`** —
channel handler. Uses `text_file` as the JSON payload (rendered from
`slack.text.tpl` or `slack.message.tpl`).

### 6.8 Telegram

**`_alert_telegram_api(endpoint, bot_token, [curl_flags...])`** — shared Bot
API helper. Uses `curl -K` (config file) to keep bot token out of the process
listing. Config file created with `chmod 600`, removed after curl returns.
Returns API response body on stdout.

**`_alert_telegram_message(text, bot_token, chat_id)`** — send text via
`sendMessage` with MarkdownV2 parse mode.

**`_alert_telegram_document(file_path, caption, bot_token, chat_id)`** — send
file via `sendDocument` with optional caption.

**`_alert_deliver_telegram(payload_file, [attachment_file])`** — reads
payload file content as message text, sends message, then optional document.
Uses `ALERT_TELEGRAM_BOT_TOKEN` and `ALERT_TELEGRAM_CHAT_ID`.

**`_alert_handle_telegram(subject, text_file, html_file, [attachment])`** —
channel handler. Passes `text_file` as payload and attachment through.

### 6.9 Discord

**`_alert_discord_webhook(payload_file, webhook_url)`** — POST JSON to Discord
webhook. Handles HTTP 204 empty-body success response.

**`_alert_discord_upload(file_path, payload_file, webhook_url)`** — single
multipart POST with `payload_json` + `files[0]`.

**`_alert_deliver_discord(payload_file, [attachment_file])`** — router: if
attachment exists, uses multipart upload; otherwise plain JSON POST. Uses
`ALERT_DISCORD_WEBHOOK_URL`.

**`_alert_handle_discord(subject, text_file, html_file, [attachment])`** —
channel handler. Passes `text_file` as payload and attachment through.

### 6.10 Digest and Spool

**`_alert_spool_append(data_file, spool_file)`** — append timestamped entries
to digest spool. Prepends current epoch to each non-blank line under exclusive
flock (10s timeout). No-op if data file is empty or missing.

**`_alert_digest_check(spool_file, interval, flush_callback)`** — check spool
age and flush if `interval` seconds have elapsed since the oldest entry.
Reads first line's epoch (optimistic, no lock needed). No-op if spool is empty.

**`_alert_digest_flush(spool_file, flush_callback)`** — force-flush spool
under exclusive flock. Strips epoch prefix, copies to temp file, truncates
spool (preserves inode). Calls callback **outside** the lock to avoid holding
flock during delivery. Callback receives path to temp file with flushed entries.

## 7. Template System

Templates control per-channel message formatting using `{{VAR}}` tokens
replaced from exported environment variables.

### 7.1 Template Naming

Each channel uses its own set of templates:

| Template | Used By | Purpose |
|----------|---------|---------|
| `email.text.tpl` | Email | Plain text body |
| `email.html.tpl` | Email | HTML body (for `html` or `both` format) |
| `slack.text.tpl` | Slack | JSON payload (Block Kit or simple `{"text":"..."}`) |
| `telegram.text.tpl` | Telegram | MarkdownV2 message text |
| `discord.text.tpl` | Discord | JSON payload (`{"content":"..."}` or embeds) |

If `$channel.text.tpl` doesn't exist, dispatch falls back to
`$channel.message.tpl` (backward compatibility).

### 7.2 Template Rendering

Templates use `{{VAR}}` tokens replaced by exported environment variables:

```
Subject: {{HOSTNAME}} — Security Alert
Date: {{ALERT_DATE}}

{{EVENT_SUMMARY}}

Source IP: {{SRC_IP}}
Failures: {{FAIL_COUNT}}
```

Single-pass awk using the `ENVIRON` array. No shell code execution, no `eval`.
Unknown or unset tokens become empty strings.

### 7.3 Custom Overrides

Place modified templates in a `custom.d/` subdirectory of the template
directory. Custom templates take priority over shipped defaults:

```
templates/
├── email.text.tpl          ← shipped default
├── email.html.tpl
├── slack.text.tpl
└── custom.d/
    └── email.text.tpl      ← user override (takes priority)
```

## 8. Digest System

The digest system accumulates alert data over time and flushes it
periodically, useful for batching frequent events into summary reports.

### 8.1 Workflow

```
_alert_spool_append    →  accumulate entries with epoch timestamps
_alert_digest_check    →  check age, trigger flush if interval elapsed
_alert_digest_flush    →  drain spool, call consumer callback
```

### 8.2 Spool Format

Each line in the spool file is prefixed with the epoch timestamp of when
it was appended:

```
1709654400|Brute force from 198.51.100.10: 15 failures
1709654460|Brute force from 203.0.113.5: 8 failures
```

The epoch prefix is stripped before delivery — the callback receives the
original data format.

### 8.3 Example

```bash
# Accumulate alerts into a spool file
_alert_spool_append "$data_file" "/opt/myapp/tmp/alert.spool"

# Periodically check and flush (e.g., every 300 seconds)
_alert_digest_check "/opt/myapp/tmp/alert.spool" "300" "my_send_digest"

# Callback receives path to temp file with accumulated entries
my_send_digest() {
    local flush_file="$1"
    mail -s "Alert Digest" admin@example.com < "$flush_file"
}
```

### 8.4 Concurrency

All spool operations use `flock` for exclusive locking (10-second timeout).
The lock is released **before** calling the flush callback, so delivery
functions are never executed while holding the spool lock.

## 9. Custom Channels

Register custom channel handlers for services not built in.

```bash
source /opt/myapp/lib/alert_lib.sh

# Define a handler matching the standard interface
_handle_pagerduty() {
    local subject="$1" text_file="$2"
    local payload
    payload=$(cat "$text_file")
    curl -s -X POST https://events.pagerduty.com/v2/enqueue \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# Register and enable
alert_channel_register "pagerduty" "_handle_pagerduty"
alert_channel_enable "pagerduty"

# Now alert_dispatch will include pagerduty alongside other enabled channels
alert_dispatch "/opt/myapp/templates" "Critical Alert"
```

Create a `pagerduty.text.tpl` in your template directory with the JSON
payload structure and `{{VAR}}` tokens for your event data.

## 10. Use Cases

Common integration patterns demonstrating alert_lib in real-world scenarios.

### 10.1 Intrusion Detection (BFD)

Detect brute-force authentication failures, format an alert with attacker
details, and dispatch to email and Slack simultaneously.

```bash
source /opt/myapp/lib/alert_lib.sh
alert_channel_enable "email"
alert_channel_enable "slack"

export ALERT_EMAIL_TO="security@example.com"
export ALERT_SLACK_MODE="webhook"
export ALERT_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"

export HOSTNAME
export EVENT_SUMMARY="SSH brute force from 198.51.100.10: 15 failures in 300s"
export SRC_IP="198.51.100.10"
export FAIL_COUNT="15"
export ACTION="Blocked via iptables for 3600 seconds"

alert_dispatch "/opt/myapp/templates" "Brute Force Alert"
```

### 10.2 Malware Detection (LMD)

Run a malware scan, build a report from the results, and send the report
as an email attachment with a Telegram notification.

```bash
source /opt/myapp/lib/alert_lib.sh
alert_channel_enable "email"
alert_channel_enable "telegram"

export ALERT_EMAIL_TO="admin@example.com"
export ALERT_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export ALERT_TELEGRAM_CHAT_ID="-1001234567890"

export HOSTNAME
export EVENT_SUMMARY="Malware scan completed: 3 hits in /home/user/public_html"
export TIMESTAMP
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

alert_dispatch "/opt/myapp/templates" "Malware Scan Report" "all" "/tmp/scan-report.txt"
```

### 10.3 Digest Batching (BFD)

Accumulate frequent events into a spool file and flush them as a
consolidated digest at a configurable interval.

```bash
source /opt/myapp/lib/alert_lib.sh

# On each event: append to spool
echo "SSH failure from ${src_ip}: ${count} attempts" > "$tmpfile"
_alert_spool_append "$tmpfile" "/opt/myapp/tmp/alert.spool"

# Periodically (e.g., from cron or main loop): check and flush
_alert_digest_check "/opt/myapp/tmp/alert.spool" "600" "send_digest"

send_digest() {
    local flush_file="$1"
    export EVENT_SUMMARY
    EVENT_SUMMARY=$(cat "$flush_file")
    alert_dispatch "/opt/myapp/templates" "Alert Digest" "email"
}
```

### 10.4 Custom Channel (PagerDuty)

Register a handler for a service not built into alert_lib. The handler
receives the same arguments as built-in channel handlers.

```bash
source /opt/myapp/lib/alert_lib.sh

_handle_pagerduty() {
    local subject="$1" text_file="$2"
    local payload
    payload=$(cat "$text_file")
    curl -s -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

alert_channel_register "pagerduty" "_handle_pagerduty"
alert_channel_enable "pagerduty"
alert_dispatch "/opt/myapp/templates" "Critical Incident"
```

Create a `pagerduty.text.tpl` in your template directory containing the
PagerDuty Events API v2 JSON structure with `{{VAR}}` tokens.

## 11. Testing

253 tests across 8 BATS files:

| File | Tests | Coverage |
|------|-------|----------|
| `00-scaffold.bats` | 3 | Library loading, version, source guard |
| `01-core.bats` | 38 | Template engine, escape functions, URL redaction, false-positive tests |
| `02-email.bats` | 40 | MIME builder, local MTA, SMTP relay, credential hiding, delivery router |
| `03-registry.bats` | 36 | Channel register/enable/disable, dispatch, template rendering |
| `04-slack.bats` | 49 | HTTP utilities, webhook, bot API, 3-step upload, error redaction |
| `05-telegram.bats` | 36 | API helper security, sendMessage, sendDocument, handler |
| `06-discord.bats` | 23 | Webhook, multipart upload, delivery router, error redaction |
| `07-digest.bats` | 28 | Spool append, digest check, flush, callback, integration |

```bash
make -C tests test              # Debian 12 (primary)
make -C tests test-rocky9       # Rocky 9
make -C tests test-centos6      # CentOS 6 (bash 4.1 floor)
make -C tests test-all          # Full 9-OS sequential matrix
make -C tests test-all-parallel # Full 9-OS parallel matrix
```

Tests run inside Docker containers via [batsman](https://github.com/rfxn/batsman).
CI runs lint + full matrix on every push via GitHub Actions.

## 12. Troubleshooting

Common issues and resolution steps for alert_lib consumers.

### 12.1 Dispatch Returns Failure

`alert_dispatch` returns 1 if any enabled channel fails, but it continues
through all channels before returning. To isolate the failing channel,
call delivery functions directly (e.g., `_alert_deliver_slack`) and check
their return codes. Verify that the channel's required environment variables
are set and exported.

### 12.2 Missing curl

Install curl on the target system. Slack, Telegram, Discord, and SMTP relay
all require curl for HTTP delivery. Local MTA email delivery (mail/sendmail)
does not require curl.

### 12.3 SMTP TLS Errors

Use `smtps://host:465` for implicit TLS (port 465). For STARTTLS on port
587, use `smtp://host:587` — curl auto-negotiates STARTTLS when the port
is 587. Port 25 is plaintext. If curl reports certificate errors, check
that the system CA bundle is current.

### 12.4 Telegram Chat ID

`ALERT_TELEGRAM_CHAT_ID` must be set to a numeric chat ID, not a username.
To get the chat ID: send a message to your bot, then query
`https://api.telegram.org/bot<TOKEN>/getUpdates` and read the `chat.id`
field from the response. Group chat IDs are negative numbers (e.g.,
`-1001234567890`).

### 12.5 Slack Channel Not Found

In bot mode (`ALERT_SLACK_MODE=bot`), `ALERT_SLACK_CHANNEL` accepts either
a channel ID (e.g., `C01ABCDEF`) or a channel name (e.g., `#alerts`).
Ensure the bot has been invited to the channel. In webhook mode, the
channel is determined by the webhook configuration and this variable is
not used.

### 12.6 Empty Template Values

Template tokens must exactly match exported environment variable names.
`{{EVENT_SUMMARY}}` renders from `$EVENT_SUMMARY` — the variable must be
both set and exported (`export EVENT_SUMMARY="..."`). Unset or unexported
variables render as empty strings. Check token names in your template
against the variables you export before calling `alert_dispatch`.

## License

Copyright (C) 2002-2026, [R-fx Networks](https://www.rfxn.com)
— Ryan MacDonald <ryan@rfxn.com>

GNU General Public License v2. See the source files for the full license text.

## Support

- **Issues:** [github.com/rfxn/alert_lib/issues](https://github.com/rfxn/alert_lib/issues)
- **Email:** proj@rfxn.com
