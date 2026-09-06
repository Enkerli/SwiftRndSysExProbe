# Working on SwiftRndSysExProbe

*Short on purpose. This is a diagnostic, not an instrument, and the rules that
follow are all about not letting it lie.*

---

## The two things that surprise everybody

**Nothing builds without the foundation checked out beside this repo.**

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

`Scripts/verify.sh` and the Xcode project both look in `$REPO/../enkerli-swift`;
override with `ENKERLI_SWIFT=...`. Without it every suite fails with that line
printed, deliberately.

**This plug-in measures a property of a *host*, and nothing here runs in one.**
So `Scripts/verify.sh probe` checks the reasoning — what the probe concludes and
what it refuses to conclude — and it cannot check the answer. Say that plainly
when reporting a green.

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh probe      # one
```

---

## Rules that are not negotiable

**The component triple is forever.** `aumi/SxPr/Enke` — not `Rsxp`, which is the
JUCE RndSysExProbe's and would collide with the AUv3 that build ships. So is the
bundle identifier: `com.enkerli.SwiftRndSysExProbe`, distinct from the JUCE
build's `com.enkerli.RndSysExProbe`. A colliding subtype makes a host load the
wrong plug-in, which is visible; a colliding bundle id makes this one *silently
not exist*, which is what happened to the Swift Serpe. `verify.sh identity`
checks both, and also checks that this file and the README name the same code
the plist does — a check that exists because two sibling repos were found
quoting a different plug-in's triple in prose.

**Never round a verdict up.** "OUT: not proven" is the honest answer with
nothing attached, and it is indistinguishable from a host that drops our output.
That indistinguishability is stated in the verdict text on purpose. If you find
yourself making a verdict friendlier, you are making a diagnostic useless.

**Every burst ends on a value never sent before.** This is the whole method: an
echo of a fixed test seed could be a leftover from an earlier burst or a device
that was already playing it, and the JUCE build's AUM result was unprovable for
exactly that reason. `Scripts/verify.sh probe` reproduces that bug as a planted
divergence. Do not make the burst seed constant, and do not count a fixed test
seed as proof of OUT.

**"Ours, damaged" and "somebody else's, intact" are opposite findings.** A host
that delivers another vendor's frame whole has proved it passes SysEx; one that
delivers ours broken has proved the opposite. Nothing may report them as the
same thing.

**Run the kernel suite after touching anything in the SysEx path.** A wrongly
framed SysEx packet has **no musical symptom** — no wrong note, no stuck note,
nothing to hear. UMP does not carry `F0`/`F7`, and a frame spans packets at six
data bytes each; get either wrong and you produce bytes that no device accepts
and a dump that looks nearly right. `Tests/Kernel/sysex-main.mm` in the
foundation covers both, and decodes from the UMP spec rather than by calling the
kernel's own reassembler.

---

## Where a change belongs

| It is | Put it |
|---|---|
| The RND wire protocol, or any device's | `enkerli-swift` → `Sources/Carrier` |
| A render-thread capability | `Sources/Kernel` **and** its harness in `Tests/Kernel` |
| A control any plug-in could use | `Sources/UI` |
| AU plumbing | `Sources/Shell` |
| About *diagnosing a host* | here |

The codec is already in `Carrier`, checked against frames captured off real
hardware. Do not reimplement it here, and do not "improve" it against a
guess — `rnd-companion/docs/PROTOCOL.md` records what is confirmed and what is
inferred, and that distinction is the most important thing about it. **Nothing
in the vocabulary is published.** A firmware update can invalidate any of it.

---

## House style

The prose in this repo explains *why*, records what was measured, and says
plainly what is not known. When you are unsure whether something works, write
that down instead of rounding up — which in this repo is not a style note but
the product requirement. The README's "What has not been done" section is the
model.
