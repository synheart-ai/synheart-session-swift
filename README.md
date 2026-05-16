# SynheartSession

[![iOS 13.0+](https://img.shields.io/badge/iOS-13.0+-blue.svg)](https://developer.apple.com/ios/)
[![watchOS 6.0+](https://img.shields.io/badge/watchOS-6.0+-blue.svg)](https://developer.apple.com/watchos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

> **Source-available.** This repository is open for reading, auditing, and
> filing issues. We do **not** accept pull requests — see
> [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and how to contribute
> via issues. Security reports go through [SECURITY.md](SECURITY.md).

Standalone Swift SDK for Synheart Session — real-time session capture with on-device HR metrics and behavioral signal fusion.

## Features

- Pluggable `BiosignalProvider` for HR sources (mock, BLE HRM via synheart-wear, Apple HealthKit)
- Optional `BehaviorProvider` for behavioral signal fusion (typing, scrolling, taps, app switches)
- HRV metrics (SDNN, RMSSD, pNN50) from the runtime; mean HR computed locally
- Thread-safe sliding window buffer (`NSLock`) with configurable window size
- Built-in mock provider for local development and testing (no wearable required)
- Typed session events: `session_started`, `session_frame`, `biosignal_frame`, `session_summary`, `session_error`
- Configurable compute profile (window size, emit interval)
- Error enum with 5 cases (permissionDenied, sensorUnavailable, invalidState, lowBattery, osTerminated)
- Raw biosignal streaming via `includeRawSamples` opt-in
- Modular SPM targets: core, wear, HealthKit, behavior

## Installation

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/synheart-ai/synheart-session-swift.git", from: "0.2.0")
]
```

The package provides four library products:

| Product | Description |
|---------|-------------|
| `SynheartSession` | Core session engine, types, and mock provider (zero external deps) |
| `SynheartSessionWear` | Adds `WearBiosignalProvider` for real BLE HR streaming (depends on `SynheartWear`) |
| `SynheartSessionHealthKit` | Adds `HealthKitBiosignalProvider` — wraps `SynheartWear` HealthKit streaming (depends on `SynheartWear`) |
| `SynheartSessionBehavior` | Adds `BehaviorSdkProvider` — wraps `SynheartBehavior` from `synheart-behavior-swift` (depends on `SynheartBehavior`) |

Add only the target you need:

```swift
.target(name: "MyApp", dependencies: [
    "SynheartSession",              // core only
    // "SynheartSessionWear",       // add for real BLE wearable data
    // "SynheartSessionHealthKit",  // add for Apple HealthKit data
    // "SynheartSessionBehavior",   // add for behavioral signals
])
```

Or in Xcode: **File > Add Package Dependencies** and enter the repository URL.

### CocoaPods

```ruby
pod 'SynheartSession', '~> 0.2.0'
```

## Quick Start

### Default (mock provider — no wearable needed)

```swift
import SynheartSession

let config = SessionConfig(
    sessionId: UUID().uuidString,
    mode: .focus,
    durationSec: 300,
    profile: ComputeProfile(windowSec: 60, emitIntervalSec: 5)
)

let engine = SessionEngine()
try engine.start(config: config) { event in
    switch event["type"] as? String {
    case "session_started":
        print("Session started")
    case "session_frame":
        let metrics = event["metrics"] as? [String: Any]
        print("Metrics: \(metrics ?? [:])")
    case "session_summary":
        print("Session complete")
    case "session_error":
        print("Error: \(event["message"] ?? "")")
    default:
        break
    }
}

// Stop early (optional)
try engine.stop(sessionId: config.sessionId)

// Query status
if let status = engine.getStatus() {
    print("Active: \(status["active"] ?? false)")
}
```

## SDK Usage

### Real BLE heart rate data (via synheart-wear)

```swift
import SynheartSession
import SynheartSessionWear
import SynheartWear

// Connect to a BLE HRM (Polar, Wahoo, WHOOP broadcast, etc.)
let bleHrm = BleHrmProvider()
let devices = try await bleHrm.scan(timeoutMs: 10000)
try await bleHrm.connect(deviceId: devices.first!.deviceId)

// Wire it into the session engine
let provider = WearBiosignalProvider(bleHrmProvider: bleHrm)
let engine = SessionEngine(provider: provider)

try engine.start(config: config) { event in
    // Same event handling — metrics are now computed from real HR data
}
```

### Apple HealthKit heart rate data (via synheart-wear)

```swift
import SynheartSession
import SynheartSessionHealthKit
import SynheartWear

// 1. Set up SynheartWear with the platform-native health adapter
let wear = SynheartWear(
    config: SynheartWearConfig(enabledAdapters: [.platformHealth])
)
try await wear.initialize()

// 2. Wrap it as a BiosignalProvider
let provider = HealthKitBiosignalProvider(wear: wear)
let engine = SessionEngine(provider: provider)

try engine.start(config: config) { event in
    // Metrics are computed from HealthKit HR data
    // (Apple Watch, workout apps, or any HealthKit-writing source)
}
```

### Behavioral signals (via synheart-behavior)

```swift
import SynheartSession
import SynheartSessionBehavior
import SynheartBehavior

// 1. Initialize the behavior SDK
let behaviorSdk = SynheartBehavior()
try behaviorSdk.initialize()

// 2. Wrap it as a BehaviorProvider
let behaviorProvider = BehaviorSdkProvider(sdk: behaviorSdk)

// 3. Pass both providers to the engine
let engine = SessionEngine(behaviorProvider: behaviorProvider)

try engine.start(config: config) { event in
    // session_frame events now include a "behavior" key
    if let behavior = event["behavior"] as? [String: Any] {
        print("Stability: \(behavior["stability_index"] ?? "")")
    }
}
```

### Custom provider

Any type conforming to `BiosignalProvider` can drive the session engine:

```swift
class MyProvider: BiosignalProvider {
    var isAvailable: Bool { true }
    var name: String { "my_source" }

    func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        // Push BiosignalSample values into the callback
    }

    func stopStreaming() { }
}

let engine = SessionEngine(provider: MyProvider())
```

## Architecture

```
SessionEngine(provider: BiosignalProvider, behaviorProvider: BehaviorProvider?)
  │
  ├── BiosignalProvider              (protocol)
  │     ├── MockBiosignalProvider     (sinusoidal mock, 1 Hz)
  │     ├── WearBiosignalProvider     (wraps synheart-wear BLE HRM)
  │     └── HealthKitBiosignalProvider (wraps synheart-wear HealthKit streaming)
  │
  ├── BehaviorProvider               (protocol, pull-based)
  │     ├── MockBehaviorProvider      (stable mid-range values)
  │     └── BehaviorSdkProvider       (wraps synheart-behavior SynheartBehavior)
  │
  ├── SampleRingBuffer           (thread-safe sliding window)
  │
  ├── computeMetrics()           (mean HR local + HRV from the runtime)         
  ├── Types                      (SessionConfig, SessionMode, ComputeProfile)
  └── SessionError               (error enum with 5 cases)
```

### Data Flow

```
BiosignalProvider.startStreaming()
  → BiosignalSample (timestampMs, bpm, rrIntervalsMs, deviceId, source)
    → SampleRingBuffer (windowed)
      → emitFrame() reads buffer → computeMetrics() → session_frame event
      → emitBiosignalFrame() reads buffer → biosignal_frame event (raw samples)
```

### BiosignalSample

| Field | Type | Description |
|-------|------|-------------|
| `timestampMs` | `Int64` | Sample timestamp (ms since epoch) |
| `bpm` | `Double` | Heart rate in beats per minute |
| `rrIntervalsMs` | `[Double]?` | RR intervals from BLE HRM or HealthKit |
| `deviceId` | `String?` | Source device identifier |
| `source` | `String` | One of the canonical wear sources — `apple_healthkit`, `health_connect`, `ble_hrm`, `whoop`, `garmin`, `garmin_sdk`, `fitbit`, `oura` — plus the test value `mock`. (Cloud-vs-BLE flavor is recorded in `meta.source_type`.) |

### Session Frame Output

Each `session_frame` event contains a flat `metrics` map with:

| Field | Description |
|-------|-------------|
| `hr_mean_bpm` | Mean heart rate (BPM) |
| `hr_sdnn_ms` | SDNN of RR intervals (ms) |
| `rmssd_ms` | RMSSD approximation (ms) |
| `sample_count` | Number of HR samples in window |
| `start_ms` | Window start timestamp (ms) |
| `end_ms` | Window end timestamp (ms) |
| `motion_rms_g` | RMS acceleration in g-force (optional, when accelerometer available) |
| `motion_sample_count` | Number of accelerometer samples in interval (optional) |
| `active_energy_kcal` | Cumulative active energy burned in kcal (optional, iOS only) |

### Biosignal Frame Output

When `includeRawSamples: true` is set in `SessionConfig`, `biosignal_frame` events are emitted containing the raw samples in the current buffer window. Each sample includes `timestamp_ms`, `bpm`, `source`, and optionally `rr_intervals_ms` and `device_id`.

### Error Types

```swift
SessionError.permissionDenied("...")   // HR permission not granted
SessionError.sensorUnavailable("...")  // No HR sensor available
SessionError.invalidState("...")       // Duplicate session, etc.
SessionError.lowBattery("...")         // Device battery too low
SessionError.osTerminated("...")       // Session killed by OS
```

If the provider fails to start (e.g., BLE HRM not connected), the engine emits a `session_error` event with `error_code: "sensor_unavailable"` instead of throwing.

## Privacy & Security

- **Session-Based Only**: No passive or background HR tracking
- **On-Device Processing**: All metrics computation happens locally on the device
- **No Raw HR Transmission**: Raw heart rate samples stay on device unless explicitly enabled via `includeRawSamples`
- **No Network Calls**: The SDK makes zero network calls — you control what gets persisted or transmitted
- **No Data Retention**: Raw biometric data is not retained after processing
- **Not a Medical Device**: This library is for wellness and research purposes only

## Testing

```bash
# Run tests
swift test

# Build
swift build
```

## Standalone vs Core SDK

**With Synheart Core SDK:** HRV metrics (SDNN, RMSSD, pNN50) are automatically piped from the native session runtime via `ingestHsiMetrics()`. No action needed — the core SDK wires this up during session lifecycle.

**Standalone (without core SDK):** Your app must call `engine.ingestHsiMetrics(metrics)` with pre-computed HRV values. If not called, HRV metrics default to `0.0` — mean HR is still computed locally from the sample buffer.

```swift
// Standalone usage: manually provide HRV
engine.ingestHsiMetrics([
    "hrv.sdnn_ms": 42.5,
    "hrv.rmssd_ms": 38.1,
    "hrv.pnn50": 21.3,
])
```

## Backward Compatibility

`SessionEngine()` with no arguments uses `MockBiosignalProvider` by default. All existing code continues to work without changes.

## Watch Companion App

The Session SDK is designed to work with a watchOS companion app that unlocks real-time biometric streaming. Due to HealthKit API limitations, real-time HR/HRV data requires an active `HKWorkoutSession` on the watch — the Session SDK handles this lifecycle automatically.

- [synheart-edge-watch-ios](https://github.com/synheart-ai/synheart-edge-watch-ios) — watchOS companion app (HKWorkoutSession, HKLiveWorkoutBuilder, WCSession relay)

When a session starts on the phone, the companion app starts a workout session on the watch, enabling continuous HR, HRV, and accelerometer streaming back to the phone SDK.

## Related

| Package | Platform | Description |
|---------|----------|-------------|
| [synheart-session-flutter](https://github.com/synheart-ai/synheart-session-flutter) | Flutter | Flutter plugin (wraps this SDK via platform channels) |
| [synheart-session-kotlin](https://github.com/synheart-ai/synheart-session-kotlin) | Android | Kotlin SDK |
| [synheart-wear-swift](https://github.com/synheart-ai/synheart-wear-swift) | iOS | Wearable SDK (BLE HRM, HealthKit, WHOOP, Garmin) |
| [synheart-behavior-swift](https://github.com/synheart-ai/synheart-behavior-swift) | iOS | Behavioral signals SDK (typing, scrolling, taps, app switching) |

## Documentation

Full reference docs live at **[docs.synheart.ai/synheart-session/swift](https://docs.synheart.ai/synheart-session/swift)** — provider catalog, lifecycle, watch protocol, error reference, and the cross-platform overview.

## Links

- **Source of Truth**: [synheart-session](https://github.com/synheart-ai/synheart-session) — RFCs, protocol definitions, and cross-platform examples

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.
