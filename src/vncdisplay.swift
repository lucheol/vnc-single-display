// vnc-single-display - give screen-sharing clients a single display
// Copyright (C) 2026 Lucio Oliveira
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

import CoreGraphics
import Foundation

// vncdisplay - collapse a multi-display Mac to a single display, and restore it.
//
// Mirroring every secondary display onto the main one puts all of them at the
// same origin, which leaves a screen-sharing client with a single, normally
// sized desktop instead of a sparse bounding box spanning every monitor. No
// windows are lost: mirroring merges the desktops rather than disabling one.
//
// It also sidesteps a macOS defect. The screen-sharing agent builds its capture
// framebuffer from the union of all active displays, but never converts a
// secondary display's origin from point space to backing-pixel space when that
// display has no horizontally adjacent neighbour to chain from. The union then
// mixes the two coordinate spaces, the daemon and its agent disagree on the
// tile grid, every frame read fails, and the viewer is dropped a couple of
// seconds after authenticating. A single origin removes the conversion, and
// with it the failure.

let NULL_DISPLAY: CGDirectDisplayID = 0

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

func mirrored() -> Bool {
    let main = CGMainDisplayID()
    return onlineDisplays().contains { $0 != main && CGDisplayMirrorsDisplay($0) != NULL_DISPLAY }
}

func status() {
    let main = CGMainDisplayID()
    print(mirrored() ? "state: MIRRORED" : "state: extended")
    for id in onlineDisplays() {
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        let points = mode.map { "\($0.width)x\($0.height)" } ?? "?"
        let pixels = mode.map { "\($0.pixelWidth)x\($0.pixelHeight)" } ?? "?"
        let scale = mode.map { Double($0.pixelWidth) / Double($0.width) } ?? 0
        print(String(format: "id=%-4u %@ origin=(%5d,%6d) pt=%-12@ px=%-12@ scale=%.1f mirrorsDisplay=%u",
                     id,
                     id == main ? "MAIN     " : "secondary",
                     Int(bounds.origin.x), Int(bounds.origin.y),
                     points as NSString, pixels as NSString,
                     scale, CGDisplayMirrorsDisplay(id)))
    }
}

func fail(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func setMirroring(_ on: Bool) -> Bool {
    let main = CGMainDisplayID()
    let others = onlineDisplays().filter { $0 != main }
    guard !others.isEmpty else {
        fail("single display; nothing to do")
        return true
    }
    // A transaction that asks for the state the displays are already in is
    // rejected with kCGErrorIllegalArgument, so unmirroring an extended layout
    // would report a failure for a layout that is already correct. Requesting
    // nothing is the success case: there is nothing left to change.
    let target: CGDirectDisplayID = on ? main : NULL_DISPLAY
    let pending = others.filter { CGDisplayMirrorsDisplay($0) != target }
    guard !pending.isEmpty else { return true }

    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else {
        fail("CGBeginDisplayConfiguration failed")
        return false
    }
    for id in pending {
        let staged = CGConfigureDisplayMirrorOfDisplay(config, id, target)
        guard staged == .success else {
            // Completing a transaction that staged nothing succeeds, so a
            // discarded error here would be reported as a reconfiguration that
            // worked while the layout never moved.
            fail("CGConfigureDisplayMirrorOfDisplay failed for display \(id): \(staged.rawValue)")
            CGCancelDisplayConfiguration(config)
            return false
        }
    }
    let result = CGCompleteDisplayConfiguration(config, .permanently)
    guard result == .success else {
        fail("CGCompleteDisplayConfiguration failed: \(result.rawValue)")
        return false
    }
    return true
}

switch CommandLine.arguments.dropFirst().first {
case "status", nil:
    status()
case "mirror":
    exit(setMirroring(true) ? 0 : 1)
case "unmirror":
    exit(setMirroring(false) ? 0 : 1)
case "is-mirrored":
    exit(mirrored() ? 0 : 1)
default:
    fail("usage: vncdisplay [status|mirror|unmirror|is-mirrored]")
    exit(2)
}
