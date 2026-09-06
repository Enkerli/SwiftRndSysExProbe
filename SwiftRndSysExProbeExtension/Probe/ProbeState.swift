//
//  ProbeState.swift
//  SwiftRndSysExProbeExtension
//
//  What the probe has seen, and what that lets you conclude.
//
//  This plug-in answers one question per host: **does SysEx survive the trip in
//  and out of a plug-in?** Seeds only move over SysEx, so a host that strips or
//  mangles it kills the whole companion plan for that host, and it is worth
//  knowing that before writing a user interface rather than after.
//
//  The answer is two independent questions, and conflating them is the mistake
//  this file is shaped to prevent:
//
//    · **In** — does a frame sent *to* the plug-in arrive intact? Answerable by
//      anybody with a MIDI source. No hardware needed.
//    · **Out** — does a frame the plug-in emits reach anything outside it?
//      Only answerable by seeing it *come back*, which means either a device
//      that echoes or a host loop.
//
//  The JUCE probe learned that the hard way: every burst ended on the same
//  value, so "the device is playing 0x0FEDCBA9" could equally mean "your frames
//  got through" or "it was already there from last time". Each burst here ends
//  on a value nobody has ever sent, which is what turns an echo into proof.
//

import Foundation
import Carrier

/// What a received frame turned out to be.
///
/// The `damaged` case is the finding this whole plug-in exists to catch, and it
/// is deliberately separate from `foreign`: another vendor's frame arriving
/// whole proves the path is open, while ours arriving broken proves the
/// opposite. A verdict that lumped them together would report the good news and
/// the bad news as the same news.
enum FrameKind: String, Codable, Hashable, Sendable {
    case seed, dumpBegin, globals, trackEngine
    case foreign
    case damaged

    var label: String {
        switch self {
        case .seed: return "seed"
        case .dumpBegin: return "dump begin"
        case .globals: return "globals"
        case .trackEngine: return "track engine"
        case .foreign: return "other SysEx, intact"
        case .damaged: return "OUR TAG BUT DAMAGED"
        }
    }

    var isOurs: Bool { self != .foreign }
}

struct ReceivedFrame: Identifiable, Hashable, Sendable {
    let id = UUID()
    var bytes: [UInt8]
    var kind: FrameKind
    var seed: UInt32?
    /// One of the fixed test seeds — could be this burst or an earlier one.
    var matchesATestSeed = false
    /// This burst's unique trailing seed. The only thing that proves *out*.
    var matchesThisBurst = false
    var foreignLabel = ""
    var at = Date()

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var line: String {
        var parts = [kind.label]
        if let seed { parts.append(RND.formatSeed(seed)) }
        if matchesThisBurst { parts.append("← this burst") }
        else if matchesATestSeed { parts.append("← a test seed") }
        if !foreignLabel.isEmpty { parts.append(foreignLabel) }
        return parts.joined(separator: " · ") + "\n" + hex
    }
}

struct ProbeState: Hashable, Sendable {

    // MARK: - What gets sent

    /// The frames a burst carries.
    ///
    /// Chosen so that a host which clamps, reorders or truncates data bytes
    /// cannot produce them by accident: all-zero and all-ones septets (the
    /// widest legal bytes in the encoding), the seed from the hardware capture,
    /// and a walking pattern that lands on distinct septets.
    static let testSeeds: [UInt32] = [0x00000000, 0xFFFFFFFF, 0xAA442CE7, 0x0FEDCBA9]

    /// Base for the per-burst seed. Every burst ends on a value nobody has sent
    /// before, which is what makes an echo *proof* that this burst got out
    /// rather than a leftover from an earlier one.
    static let burstSeedBase: UInt32 = 0x5E5D0000

    private(set) var burstCounter: UInt32 = 0
    private(set) var burstSeed: UInt32 = 0

    /// The frames of the next burst, in order, the unique one last.
    mutating func nextBurst() -> [[UInt8]] {
        burstCounter += 1
        burstSeed = Self.burstSeedBase | burstCounter
        return (Self.testSeeds + [burstSeed]).map(RND.seedMessage)
    }

    // MARK: - Counters

    var sent = 0
    var received = 0
    var ourFramesIntact = 0
    var damaged = 0
    var foreign = 0
    var thisBurstEchoed = 0
    /// Frames the kernel's ring could not hold whole. Not zero means every byte
    /// dump on screen is shorter than the wire was.
    var truncated: UInt64 = 0

    var log: [ReceivedFrame] = []
    /// Bounded, because a host left running overnight should not grow this.
    static let logLimit = 200

    mutating func record(_ frames: [[UInt8]]) {
        for bytes in frames {
            var frame = ReceivedFrame(bytes: bytes, kind: .foreign)
            if let message = RND.parse(bytes) {
                switch message {
                case .seed(let value):
                    frame.kind = .seed
                    frame.seed = value
                    frame.matchesATestSeed = Self.testSeeds.contains(value)
                    frame.matchesThisBurst = value == burstSeed && value != 0
                    if frame.matchesThisBurst { thisBurstEchoed += 1 }
                case .dumpBegin: frame.kind = .dumpBegin
                case .globals: frame.kind = .globals
                case .trackEngine: frame.kind = .trackEngine
                }
                ourFramesIntact += 1
            } else if RND.hasManufacturerTag(bytes) {
                // Our tag, contents did not survive. The finding.
                frame.kind = .damaged
                damaged += 1
            } else {
                frame.kind = .foreign
                frame.foreignLabel = RND.describeForeign(bytes)
                foreign += 1
            }
            received += 1
            log.insert(frame, at: 0)
        }
        if log.count > Self.logLimit { log.removeLast(log.count - Self.logLimit) }
    }

    mutating func reset() {
        sent = 0
        received = 0
        ourFramesIntact = 0
        damaged = 0
        foreign = 0
        thisBurstEchoed = 0
        truncated = 0
        log.removeAll()
    }

    // MARK: - The verdict

    /// What can be concluded about SysEx *into* the plug-in.
    ///
    /// Deliberately three-valued. "Nothing has arrived" is not the same claim as
    /// "nothing survives", and a probe that reported the first as the second
    /// would condemn a host for not being wired up.
    var inboundVerdict: String {
        if damaged > 0 {
            return "IN: BROKEN — \(damaged) frame\(damaged == 1 ? "" : "s") "
                 + "carried our tag and did not survive"
        }
        if ourFramesIntact > 0 {
            return "IN: OK — \(ourFramesIntact) of our frames arrived byte-exact"
        }
        if foreign > 0 {
            return "IN: OK — \(foreign) other SysEx frame\(foreign == 1 ? "" : "s") "
                 + "arrived whole (not ours, but the path is open)"
        }
        return "IN: nothing has arrived yet — this says nothing about the host"
    }

    /// What can be concluded about SysEx *out of* the plug-in.
    ///
    /// The honest answer is almost always "not proven", and saying so is the
    /// point: out cannot be established from inside the plug-in. Something has
    /// to send this burst's unique seed back.
    var outboundVerdict: String {
        if sent == 0 {
            return "OUT: nothing sent yet"
        }
        if thisBurstEchoed > 0 {
            return "OUT: PROVEN — \(RND.formatSeed(burstSeed)) came back, and "
                 + "nothing has ever sent that value before"
        }
        return "OUT: not proven — \(sent) frames sent. This is what it looks like "
             + "with no device attached, and also what a host that drops our "
             + "output looks like. The two are indistinguishable from in here."
    }

    /// The one line worth putting in a bug report, with everything needed to
    /// know what was and was not established.
    var report: String {
        var lines = [
            inboundVerdict,
            outboundVerdict,
            "sent \(sent) · received \(received) · ours intact \(ourFramesIntact) "
            + "· damaged \(damaged) · foreign \(foreign)"
        ]
        if truncated > 0 {
            lines.append("WARNING: \(truncated) frame(s) were longer than the "
                       + "kernel's slot. Every dump below is shorter than the wire was.")
        }
        lines.append(contentsOf: log.prefix(40).map(\.line))
        return lines.joined(separator: "\n")
    }
}
