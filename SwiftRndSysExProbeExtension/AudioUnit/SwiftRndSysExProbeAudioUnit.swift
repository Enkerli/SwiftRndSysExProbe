//
//  SwiftRndSysExProbeAudioUnit.swift
//  SwiftRndSysExProbeExtension
//
//  The probe's half of the audio unit: send a burst, drain what came back.
//
//  Sixth plug-in, and the first whose audio unit holds no musical state at all.
//  There is no sequence, no map, no curve set — nothing to commit and nothing to
//  restore. `fullState` deliberately stays the shell's, because a diagnostic
//  that remembered its previous verdict across a project reopen would be
//  reporting a fact about a host it is no longer running in.
//
//  Everything here is two calls into `Shell`: `sendSysEx` and `drainSysEx`.
//  That is the whole plug-in, and it is the point — the capability was built in
//  the foundation, with its own harness, and this is what standing on it costs.
//

import AVFoundation
import Carrier
import Shell

public final class SwiftRndSysExProbeAudioUnit: PluginAudioUnit, @unchecked Sendable {

    private let stateLock = NSLock()
    private var _state = ProbeState()

    var state: ProbeState { stateLock.withLock { _state } }

    /// Sends a burst and returns the state as it is immediately afterwards.
    ///
    /// The burst's unique trailing seed is generated here, inside the lock, so
    /// two rapid taps cannot both claim the same value — which would make the
    /// second one's echo ambiguous, and ambiguity is the exact thing this
    /// plug-in exists to remove.
    @discardableResult
    func sendBurst() -> ProbeState {
        stateLock.withLock {
            let frames = _state.nextBurst()
            let refused = sendSysEx(frames)
            _state.sent += frames.count - refused.count
            return _state
        }
    }

    /// Everything that has arrived since the last call.
    ///
    /// Polled by the view rather than pushed, because the render thread's only
    /// job here is to put bytes in a ring and it must not call anybody.
    @discardableResult
    func drain() -> ProbeState {
        let frames = drainSysEx()
        return stateLock.withLock {
            if !frames.isEmpty { _state.record(frames) }
            _state.truncated = sysExTruncatedCount
            return _state
        }
    }

    func resetCounters() -> ProbeState {
        stateLock.withLock {
            _state.reset()
            return _state
        }
    }
}
