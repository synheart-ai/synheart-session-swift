# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-10-02

Minor bump, not a patch: a new `SessionMode` case breaks an exhaustive
`switch` over it.

### Added

- `SessionMode.typing` (`"typing"`).

### Fixed

- The podspec pointed `:tag` at `0.2.0`, but the release tags are
  `v`-prefixed; it now resolves `v#{spec.version}`.

## [0.2.1] - 2026-05-23

### Changed

- `SessionEngine` is now `SynheartSession`.
- `startSession(config:) throws -> AsyncStream<SessionEvent>` replaces
  `start(config:callback:)`; the stream buffers events emitted before the
  consumer starts iterating.
- Events are a typed `SessionEvent` enum instead of `[String: Any]`
  (`SessionEvent.toDictionary()` keeps the wire shape); `getStatus()`
  returns a `SessionStatus`.
- `stop(sessionId:)` is now `stopSession(sessionId:)`;
  `ingestHsiMetrics(sessionId:hsiMetrics:)` takes a session ID and is a
  no-op when it does not match the active session.

### Added

- `dispose()` for a symmetric lifecycle.

### Fixed

- watchOS minimum raised from v6 to v8. The `SynheartSessionHealthKit` and
  `SynheartSessionWear` targets depend on synheart-wear-swift, which
  declares watchOS 8, so SwiftPM refused the package on a real watchOS
  target.
- Session timers run on `RunLoop.main`, so they fire under async tests.

### CI

- All workflows opt into Node 24.

## [0.2.0] - 2026-05-15

Initial open-source release of the Synheart Session SDK for iOS.

The SDK runs a timer-driven session engine that consumes a
`BiosignalProvider` (mock, BLE HRM, HealthKit, or your own
implementation) and an optional `BehaviorProvider`, then emits typed
session events: `session_started`, `biosignal_frame`, `session_frame`,
`session_summary`, `session_error`.

### Public surface
- `SessionEngine` with pluggable `BiosignalProvider` and optional
  `BehaviorProvider`. `MockBiosignalProvider` (1 Hz sinusoidal) and
  `MockBehaviorProvider` ship for local development.
- `WearBiosignalProvider` — bridges synheart-wear-swift
  `BleHrmProvider` for real BLE HR streaming.
- `HealthKitBiosignalProvider` — wraps `SynheartWear` HealthKit
  streaming via the Combine `streamHR()` publisher.
- `BehaviorSdkProvider` — wraps `SynheartBehavior.getCurrentStats()`
  from synheart-behavior-swift.
- `SampleRingBuffer` — thread-safe (`NSLock`) sliding window buffer
  with configurable window.
- HR/HRV computation: mean HR is computed locally; SDNN/RMSSD/pNN50
  are ingested via `ingestHsiMetrics()` from the upstream runtime.
- `SessionError` enum with 5 cases (permissionDenied,
  sensorUnavailable, invalidState, lowBattery, osTerminated).

### Distribution
- Swift Package Manager — products: `SynheartSession`,
  `SynheartSessionWear`, `SynheartSessionHealthKit`,
  `SynheartSessionBehavior`.
- CocoaPods — `pod 'SynheartSession', '~> 0.2.0'`.

[Unreleased]: https://github.com/synheart-ai/synheart-session-swift/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/synheart-ai/synheart-session-swift/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/synheart-ai/synheart-session-swift/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/synheart-ai/synheart-session-swift/releases/tag/v0.2.0
