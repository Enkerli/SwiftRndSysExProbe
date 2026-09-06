//
//  AudioUnitViewController.swift
//  SwiftRndSysExProbeExtension
//
//  The probe's principal class: the three things a plug-in tells the shell.
//
//  Info.plist names `$(PRODUCT_MODULE_NAME).AudioUnitViewController` as both the
//  principal class and the factory function, so this type keeps that name.
//

import CoreAudioKit
import SwiftUI
import Shell

@MainActor
public final class AudioUnitViewController: PluginViewController {

    public override func makeAudioUnit(componentDescription: AudioComponentDescription) throws -> PluginAudioUnit {
        try SwiftRndSysExProbeAudioUnit(componentDescription: componentDescription, options: [])
    }

    public override var parameterTreeSpec: ParameterTreeSpec { SwiftRndSysExProbeParameterSpecs }

    public override func makeRootView(parameterTree: ObservableAUParameterGroup,
                                      audioUnit: PluginAudioUnit) -> AnyView {
        AnyView(SwiftRndSysExProbeMainView(parameterTree: parameterTree,
                                           audioUnit: audioUnit as? SwiftRndSysExProbeAudioUnit))
    }
}
