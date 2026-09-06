//
//  SwiftRndSysExProbeMainView.swift
//  SwiftRndSysExProbeExtension
//
//  One screen, and it is a test result.
//
//  Deliberately self-documenting: the window names the host process and the
//  plug-in's own identity, so a **screenshot of it is a complete finding** — you
//  do not have to remember which host it was taken in or what build. The JUCE
//  probe made the same choice for the same reason and it is the single most
//  useful thing about it.
//
//  The two verdicts are shown separately and neither is ever rounded up. "OUT:
//  not proven" is the honest answer with nothing attached, and it looks
//  identical to a host that drops our output — the plug-in says so in as many
//  words rather than letting a hopeful reader draw the wrong conclusion from a
//  green light.
//

import SwiftUI
import Carrier
import Shell
import UI
import Combine

struct SwiftRndSysExProbeMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: SwiftRndSysExProbeAudioUnit?

    @State private var state = ProbeState()
    @State private var logEverything = false
    @Environment(\.colorScheme) private var colorScheme

    /// Ten a second. The render thread never calls anybody — it puts frames in a
    /// ring — so somebody has to look, and a diagnostic you have to wait a
    /// second for feels broken even when it is not.
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var theme: MelGenTheme { colorScheme == .dark ? .dark : .light }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                identity
                verdicts
                controls
                counters
                log
            }
            .padding(MelGenMetrics.space3)
        }
        .background(theme.background)
        .onAppear { state = audioUnit?.drain() ?? state }
        .onReceive(tick) { _ in
            if let audioUnit { state = audioUnit.drain() }
        }
    }

    // MARK: - What is running, and where

    /// The host's process name and this plug-in's triple.
    ///
    /// Reading `ProcessInfo.processName` from inside an extension gives the
    /// *host* — AUM, Logic, GarageBand — because an AUv3 runs in the host's
    /// process or in an extension process named after it. That is exactly the
    /// fact a SysEx passthrough result is about, and it is the one thing nobody
    /// remembers to write down beside a screenshot.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: "SysEx probe", theme: theme)
            Text(ProcessInfo.processInfo.processName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.text)
            Text("aumi SxPr Enke · \(Bundle.main.bundleIdentifier ?? "?")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textMuted)
            Text("Does SysEx survive a plug-in, in and out? Two questions, "
                 + "answered separately.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - The findings

    private var verdicts: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            verdict(state.inboundVerdict, bad: state.damaged > 0)
            verdict(state.outboundVerdict, bad: false)
            if state.truncated > 0 {
                verdict("\(state.truncated) frame(s) were longer than the kernel's "
                        + "slot — every dump below is shorter than the wire was",
                        bad: true)
            }
        }
    }

    private func verdict(_ text: String, bad: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(bad ? theme.warning : theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MelGenMetrics.space2)
            .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.raised))
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    // MARK: - Doing something

    private var controls: some View {
        HStack(spacing: MelGenMetrics.space2) {
            Button {
                if let audioUnit { state = audioUnit.sendBurst() }
            } label: {
                Label("Send test burst", systemImage: "paperplane.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: MelGenMetrics.controlHeight)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accentText)
            .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .fill(theme.accent))
            .accessibilityHint("Sends five frames, the last one a value never sent before")

            Button {
                if let audioUnit { state = audioUnit.resetCounters() }
            } label: {
                Text("Reset")
                    .font(.system(size: 13))
                    .frame(minHeight: MelGenMetrics.controlHeight)
                    .padding(.horizontal, MelGenMetrics.space3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text)
            .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                .stroke(theme.border))
        }
    }

    // MARK: - The numbers

    private var counters: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("sent", "\(state.sent)")
            row("received", "\(state.received)")
            row("ours, intact", "\(state.ourFramesIntact)")
            row("ours, damaged", "\(state.damaged)", bad: state.damaged > 0)
            row("other vendors, intact", "\(state.foreign)")
            row("this burst echoed", "\(state.thisBurstEchoed)")
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func row(_ name: String, _ value: String, bad: Bool = false) -> some View {
        HStack {
            Text(name).foregroundStyle(theme.textMuted)
            Spacer(minLength: MelGenMetrics.space2)
            Text(value).foregroundStyle(bad ? theme.warning : theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(value)")
    }

    // MARK: - The traffic

    /// Every frame, byte for byte, newest first.
    ///
    /// Bytes rather than a summary, because the finding is often in a byte: a
    /// host that clamps the top bit, or truncates at six, produces frames whose
    /// *description* looks fine.
    private var log: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack {
                Eyebrow(text: "Traffic", theme: theme)
                Spacer(minLength: 0)
                ToggleChip(title: "All SysEx",
                           systemImage: "line.3.horizontal.decrease",
                           isOn: $logEverything,
                           theme: theme)
            }

            if state.log.isEmpty {
                Text("Nothing has arrived. Send a burst with a device or a loop "
                     + "attached, or play SysEx into this plug-in from anywhere.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            ForEach(shownFrames) { frame in
                VStack(alignment: .leading, spacing: 1) {
                    Text(frame.line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(frame.kind == .damaged ? theme.warning : theme.text)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MelGenMetrics.space2)
                .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                    .fill(theme.sunken))
            }
        }
    }

    /// Ours only, unless asked. Another vendor's traffic is evidence the path is
    /// open and is also most of what a busy MIDI setup carries, so it is off by
    /// default and one tap away.
    private var shownFrames: [ReceivedFrame] {
        logEverything ? state.log : state.log.filter(\.kind.isOurs)
    }
}
