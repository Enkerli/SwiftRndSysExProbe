# SwiftRndSysExProbe

An iOS/macOS **AUv3 MIDI processor** (`aumi SxPr`) whose only job is to answer
one question per host: **does SysEx survive the trip in and out of a plug-in?**

The sixth plug-in on [`enkerli-swift`](https://github.com/Enkerli/enkerli-swift),
and the first that is not a musical instrument at all. It exists because seeds
for a [Cymaforma RND Synth](https://www.cymaforma.com/rnd-synth) only move over
SysEx, so a host that strips or mangles it kills the whole companion plan for
that host — and it is worth knowing that *before* writing a user interface.

It is a port of the JUCE probe in
[`rnd-companion`](https://github.com/Enkerli/rnd-companion) — that one is
`aumi Rsxp` and this one is deliberately not, since a shared triple would make a
host load whichever it indexed first. Different bundle identifier too, so both
can be installed at once, which is the point of the exercise.

## Two questions, never one

Conflating these is the mistake the whole plug-in is shaped to prevent:

- **IN** — does a frame sent *to* the plug-in arrive intact? Answerable by
  anybody with a MIDI source. No hardware needed, no device needed.
- **OUT** — does a frame the plug-in emits reach anything outside it? Only
  answerable by seeing it **come back**, which means a device that echoes or a
  host loop.

Every burst is five frames: four fixed test seeds, then **a value nobody has
ever sent before**. That last one is the entire method. The JUCE probe learned
it the hard way — every burst ended on the same seed, so "the device is playing
0x0FEDCBA9" could equally mean *your frames got through* or *it was already
there from last time*, and the AUM OUT result was unprovable for that reason.

So the verdict you will usually see is:

> OUT: not proven — 5 frames sent. This is what it looks like with no device
> attached, and also what a host that drops our output looks like. The two are
> indistinguishable from in here.

That is not a failure to report; it is the report. A green light there would
mean nothing.

## Three kinds of arriving frame

- **Ours, intact** — a well-formed RND frame. IN is OK.
- **Ours, damaged** — carries the manufacturer tag `6F 62 78` and the body did
  not survive. **This is the finding.**
- **Somebody else's, intact** — not ours, but the path is open, which is good
  news and is reported as itself rather than as ours.

A host that mangles our frames and a host that carries another vendor's are
opposite results, and nothing here can report them as the same one.

## The screen is the test result

The window names the **host process** and the plug-in's own triple, so a
screenshot of it is a complete finding — you do not have to remember which host
it was taken in. The traffic log shows every frame byte for byte, because a host
that clamps the top bit or truncates at six produces frames whose *description*
looks fine.

## Verifying

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh probe      # one suite
```

| Suite | Checks |
|---|---|
| `identity` | The component triple and the bundle identifier are unique across every sibling checkout, and the documents name this plug-in's own |
| `probe` | What the plug-in **concludes**, and more importantly what it refuses to conclude. The JUCE build's original ambiguity is reproduced as a planted divergence rather than described as a lesson |
| `kernel` | The foundation package's own check. It carries the SysEx harness, and it matters more here than anywhere: a wrongly framed SysEx packet has **no musical symptom**, so that harness is the only thing between "the probe says not proven" and "the kernel mangled it on the way out" |
| `gaps` | This plug-in has a section in the shared register, or the run fails |

The thing this plug-in measures is a property of a host, and this suite runs in
no host — so it checks reasoning, not answers. That distinction is the honest
limit of what a green here means.

## Building

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

Then open `SwiftRndSysExProbe.xcodeproj` (Xcode 27+, iOS/macOS 26.0+).

## What this plug-in is, in files

| File | Lines | What it is |
|---|---:|---|
| `Probe/ProbeState.swift` | ~230 | What has been seen, and what that does and does not license |
| `UI/SwiftRndSysExProbeMainView.swift` | ~200 | One screen, which is a test result |
| `AudioUnit/` (3 files) | ~120 | Two calls into `Shell`, and no parameters |

**There is no codec in this repo.** The RND wire protocol is `Carrier`'s, ported
from `rnd-companion`'s plain C++17 and checked against frames captured off real
hardware. The SysEx path in and out is the shared kernel's.

## What has not been done

- **None of this has been run against an RND**, and the OUT half cannot be
  established without one (or a host loop). Everything here is the reasoning
  around a measurement that has not been taken with this build.
- **No direct MIDI port.** The JUCE probe can open the device itself and bypass
  host routing entirely, which is the only thing that works in Logic and Bitwig.
  That is the biggest open question about this port, not an oversight.
- **The report cannot be copied.** `ProbeState.report` builds the text and
  nothing offers it to the pasteboard yet.
- **No AU parameters,** deliberately. "Send a burst" is a momentary action, not
  a value, and automating it would mean a project that fires diagnostics at the
  DAW every time it reaches bar 17.

## The full register

The shared gaps and the strategy for which get built back live in
[GAPS.md](https://github.com/Enkerli/enkerli-swift/blob/main/GAPS.md) in the
foundation. `Scripts/verify.sh` runs its staleness check.

## Licence

Public domain, all the way down. See [LICENSE](LICENSE).
