//
//  Parameters.swift
//  SwiftRndSysExProbeExtension
//
//  No parameters, and for once that is not a gap.
//
//  A diagnostic has one control — "send a burst" — and it is a *momentary*
//  action, not a value. An AU parameter is a value a host can automate, record
//  and recall; automating "send a burst" would mean a project that fires
//  diagnostics at the DAW every time it reaches bar 17.
//
//  The three the kernel offers — playMelody, playbackDirection, hostSync — all
//  act on a sequence, and this plug-in never commits one. Declaring them would
//  put three controls in a host's automation lane that do nothing at all, which
//  is the bug GAPS.md draws a line under: a missing control is a gap, a control
//  that lies is a bug.
//

import AudioToolbox
import Foundation
import Kernel
import Shell

// A quantizer has no transport, so it declares no transport parameters.
//
// This tree held `playMelody`, `playbackDirection` and `hostSync` until
// 2026-09, inherited by being scaffolded from a plug-in that schedules notes.
// The kernel acts on all three inside `processMelody`, and this plug-in never
// commits a sequence — so a host showed three automatable controls that did
// nothing at all. A missing control is a gap; a control that lies is a bug, and
// GAPS.md in the foundation draws that line.
//
// Empty rather than replaced. Making "fold on/off" host-automatable is a real
// feature and is listed as one; inventing it here to avoid an empty tree would
// be exactly the overload the MVP strategy exists to prevent.
let SwiftRndSysExProbeParameterSpecs = ParameterTreeSpec {
    ParameterGroupSpec(identifier: "global", name: "Global") {
    }
}

extension ParameterSpec {
    init(
        address: PluginParameterAddress,
        identifier: String,
        name: String,
        units: AudioUnitParameterUnit,
        valueRange: ClosedRange<AUValue>,
        defaultValue: AUValue,
        unitName: String? = nil,
        flags: AudioUnitParameterOptions = [AudioUnitParameterOptions.flag_IsWritable, AudioUnitParameterOptions.flag_IsReadable],
        valueStrings: [String]? = nil,
        dependentParameters: [NSNumber]? = nil
    ) {
        self.init(address: address.rawValue,
                  identifier: identifier,
                  name: name,
                  units: units,
                  valueRange: valueRange,
                  defaultValue: defaultValue,
                  unitName: unitName,
                  flags: flags,
                  valueStrings: valueStrings,
                  dependentParameters: dependentParameters)
    }
}
