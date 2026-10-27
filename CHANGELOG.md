# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/). While the version is `0.x`, the public
interface may still change between minor releases.

## [Unreleased]

## [0.1.0] - 2026-10-27

First public release.

### Added
- MLLP server: one thread per connection, several messages per connection, size and idle
  limits, graceful shutdown on `SIGINT`/`SIGTERM`.
- HL7 v2 to JSON decoder and JSON to HL7 encoder built on `ruby-hl7`, with support for
  components, sub-components, repetitions, escape sequences, custom delimiters, custom
  `Z` segments and character sets declared in MSH-18. Round trips are lossless.
- Field names for MSH, MSA, ERR, EVN, PID, NK1, PV1, ORC, OBR, OBX, NTE, AL1 and DG1.
- Upstream HTTP client configured with `UPSTREAM_API_URL`, with optional bearer token and
  timeouts.
- Response contract for the upstream API (`ack_code`, `message`, `message_type`,
  `observations`, `segments`) and acknowledgement mapping: `AA`, `AE` for API validation
  errors, `AR` for malformed messages and unavailable APIs.
- Command line tools: `hl7-gateway`, `hl7-send`, `hl7-to-json`, `json-to-hl7`.
- Example API and sample messages, Dockerfile and docker-compose setup.
- RSpec suite (unit, TCP and end-to-end), RuboCop and a GitHub Actions workflow.

[Unreleased]: https://github.com/francogaliotti/hl7v2-gateway/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/francogaliotti/hl7v2-gateway/releases/tag/v0.1.0
