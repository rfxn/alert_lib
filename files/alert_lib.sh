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
