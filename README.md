# alert_lib — Multi-Channel Transactional Alerting for Bash

[![CI](https://github.com/rfxn/alert_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/alert_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/rfxn/alert_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A shared Bash library for multi-channel transactional alerting. Supports email,
Slack, Telegram, and Discord delivery with template engine, MIME builder, and
channel registry/dispatch.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection) and
[LMD](https://github.com/rfxn/linux-malware-detect) via source inclusion.

## Status

Under development. Full documentation will be available at first release.

## License

Copyright (C) 2002-2026, [R-fx Networks](https://www.rfxn.com)
— Ryan MacDonald <ryan@rfxn.com>

GNU General Public License v2. See the source files for the full license text.
