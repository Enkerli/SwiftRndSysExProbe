//
//  probe-main.swift
//  SwiftRndSysExProbe
//
//  What the probe concludes, checked away from a host and away from hardware.
//
//  This is the plug-in whose correctness is hardest to check, because the thing
//  it measures is a property of a *host* and this runs in no host. So what is
//  checkable is the reasoning: given these frames arriving, does it draw the
//  right conclusion — and, more importantly, does it refuse to draw one it
//  cannot?
//
//  That second half is most of this file. A probe that reported "OUT: OK"
//  because it sent something would be worse than no probe, and the JUCE build's
//  original ambiguity — every burst ending on the same seed, so an echo could be
//  a leftover — is reproduced here as a test rather than described as a lesson.
//
//  The codec itself is not checked here. It is Carrier's, it is checked against
//  frames captured off real hardware in the package's own suite, and repeating
//  that here would be repeating somebody else's test badly.
//

import Foundation
import Carrier

var failures = 0
var checks = 0

func check(_ what: String, _ passed: Bool, _ detail: String = "") {
    checks += 1
    print("  \(passed ? "PASS" : "FAIL")  \(what)\(detail.isEmpty ? "" : " — \(detail)")")
    if !passed { failures += 1 }
}

print("── what a burst is ────────────────────────────────")

var state = ProbeState()
let first = state.nextBurst()
check("a burst is the four test frames plus one", first.count == 5,
      "\(first.count) frames")
check("and every frame is a well-formed seed message",
      first.allSatisfy { if case .seed? = RND.parse($0) { return true }; return false })

let firstSeeds = first.compactMap { frame -> UInt32? in
    if case .seed(let value)? = RND.parse(frame) { return value }
    return nil
}
check("the fixed four are the fixed four",
      Array(firstSeeds.prefix(4)) == ProbeState.testSeeds,
      firstSeeds.prefix(4).map(RND.formatSeed).joined(separator: " "))
check("and they include the widest legal bytes and the hardware capture",
      ProbeState.testSeeds.contains(0xFFFFFFFF) && ProbeState.testSeeds.contains(0xAA442CE7))

let second = state.nextBurst()
let secondSeeds = second.compactMap { frame -> UInt32? in
    if case .seed(let value)? = RND.parse(frame) { return value }
    return nil
}
check("the trailing seed is different every burst",
      firstSeeds.last != secondSeeds.last,
      "\(RND.formatSeed(firstSeeds.last!)) then \(RND.formatSeed(secondSeeds.last!))")
check("which is the whole method: an echo of it cannot be a leftover",
      secondSeeds.last == ProbeState.burstSeedBase | 2,
      RND.formatSeed(secondSeeds.last!))
check("and it is not one of the fixed four",
      !ProbeState.testSeeds.contains(secondSeeds.last!))

print("\n── what it refuses to conclude ────────────────────")

var fresh = ProbeState()
check("with nothing sent and nothing seen, in is undecided",
      fresh.inboundVerdict.contains("nothing has arrived"), fresh.inboundVerdict)
check("and so is out", fresh.outboundVerdict.contains("nothing sent"),
      fresh.outboundVerdict)

_ = fresh.nextBurst()
fresh.sent = 5
check("sending alone never proves out",
      fresh.outboundVerdict.contains("not proven"), fresh.outboundVerdict)
check("and the verdict says why, rather than leaving a green light to be misread",
      fresh.outboundVerdict.contains("indistinguishable"))

// The frames going *back in* are the fixed four — which is what a device that
// was already playing 0x0FEDCBA9 would send, and what an echo of an old burst
// looks like. Neither proves this burst got out.
fresh.record(ProbeState.testSeeds.map(RND.seedMessage))
check("a fixed test seed coming back still does not prove out",
      fresh.outboundVerdict.contains("not proven"), fresh.outboundVerdict)
check("though it does prove in", fresh.inboundVerdict.contains("IN: OK"),
      fresh.inboundVerdict)

print("\n── what it does conclude ──────────────────────────")

fresh.record([RND.seedMessage(fresh.burstSeed)])
check("this burst's own seed coming back proves out",
      fresh.outboundVerdict.contains("PROVEN"), fresh.outboundVerdict)
check("and names the value, so the claim can be checked",
      fresh.outboundVerdict.contains(RND.formatSeed(fresh.burstSeed)))

print("\n── telling the two kinds of bad news apart ────────")

var damaged = ProbeState()
// Our tag, body clobbered — the finding this plug-in exists to catch.
var broken = RND.seedMessage(0xAA442CE7)
broken.removeLast(3)
broken.append(0xF7)
damaged.record([broken])
check("our tag with a broken body is called damaged",
      damaged.damaged == 1 && damaged.log.first?.kind == .damaged,
      damaged.log.first?.kind.label ?? "none")
check("and the verdict is BROKEN, not silence",
      damaged.inboundVerdict.contains("BROKEN"), damaged.inboundVerdict)

var foreign = ProbeState()
foreign.record([[0xF0, 0x41, 0x10, 0x42, 0x12, 0xF7]])
check("another vendor's intact frame is not damage",
      foreign.damaged == 0 && foreign.foreign == 1)
check("and it is good news: the path is open",
      foreign.inboundVerdict.contains("IN: OK"), foreign.inboundVerdict)
check("said as what it is, not as ours",
      foreign.inboundVerdict.contains("not ours"), foreign.inboundVerdict)
check("with the vendor named", foreign.log.first?.foreignLabel == "manufacturer 0x41 SysEx",
      foreign.log.first?.foreignLabel ?? "none")

// The distinction the whole design turns on, stated as one check.
check("a host that mangles ours is never confused with one that carries others",
      damaged.inboundVerdict != foreign.inboundVerdict)

print("\n── the log ────────────────────────────────────────")

var busy = ProbeState()
for index in 0..<(ProbeState.logLimit + 25) {
    busy.record([RND.seedMessage(UInt32(index))])
}
check("the log is bounded so an overnight session cannot grow it",
      busy.log.count == ProbeState.logLimit, "\(busy.log.count)")
check("but the counters are not — they count everything",
      busy.received == ProbeState.logLimit + 25, "\(busy.received)")
check("and the newest frame is first",
      busy.log.first?.seed == UInt32(ProbeState.logLimit + 24),
      busy.log.first.map { RND.formatSeed($0.seed ?? 0) } ?? "none")

var reset = busy
reset.reset()
check("reset clears the record", reset.received == 0 && reset.log.isEmpty)
check("and the verdicts go back to undecided rather than to OK",
      reset.inboundVerdict.contains("nothing has arrived"), reset.inboundVerdict)

print("\n── the report ─────────────────────────────────────")

var reported = ProbeState()
_ = reported.nextBurst()
reported.sent = 5
reported.truncated = 2
reported.record([RND.seedMessage(reported.burstSeed)])
let text = reported.report
check("the report carries both verdicts", text.contains("IN:") && text.contains("OUT:"))
check("and warns when a dump is shorter than the wire was",
      text.contains("WARNING") && text.contains("shorter than the wire"),
      "truncated \(reported.truncated)")
check("and includes the bytes, because the finding is often in a byte",
      text.contains("F0 6F 62 78"))

print("\n\(failures == 0 ? "all checks passed" : "\(failures) of \(checks) FAILED")")
exit(failures == 0 ? 0 : 1)
