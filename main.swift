// MagicGestures — custom gestures for the Apple Magic Mouse.
// Reads raw touches through the private MultitouchSupport framework,
// recognises taps and swipes, and runs the actions bound in the config file.

import AppKit
import ApplicationServices
import QuartzCore
import SwiftUI

// MARK: - Config

struct Action: Codable {
    var keys: String?    // "cmd+shift+t"
    var shell: String?   // any /bin/sh command
    var click: String?   // left | right | middle
    var media: String?   // playpause | next | previous | volumeup | volumedown | mute (volume keys also take "-fine")
    var stepMM: Double?  // edge slides only: finger travel per repeat (overrides edgeStepMM)
}

struct Settings: Codable {
    var tapMaxSeconds = 0.25       // a tap must start and end within this time
    var tapMaxMoveMM = 2.5         // ...and no finger may move further than this
    var swipeMinMM = 10.0          // every finger must travel this far
    var swipeWindowSeconds = 0.35  // ...within this time
    var cooldownSeconds = 0.3      // minimum gap between two gestures
    var middleZoneWidth = 0.2      // width of the "middle" zone for one-finger taps (0–1)
    var edgeZoneWidth = 0.18       // width of the left/right edge strips for edge slides (0–1)
    var edgeStepMM = 5.0           // finger travel along an edge per repeat of the action
    var edgeStartMM = 3.0          // travel needed before an edge slide starts (ignores a resting finger)
    var edgeAcceleration = 1.0     // how much faster movement counts for more (0 = strictly linear)
    var edgeMomentum = 0.15        // seconds a flick keeps coasting after the finger lifts (0 = off)
    var tapAndDrag = true          // tap, then touch again and hold, to drag

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Settings()
        tapMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .tapMaxSeconds) ?? def.tapMaxSeconds
        tapMaxMoveMM = try c.decodeIfPresent(Double.self, forKey: .tapMaxMoveMM) ?? def.tapMaxMoveMM
        swipeMinMM = try c.decodeIfPresent(Double.self, forKey: .swipeMinMM) ?? def.swipeMinMM
        swipeWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .swipeWindowSeconds) ?? def.swipeWindowSeconds
        cooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? def.cooldownSeconds
        middleZoneWidth = try c.decodeIfPresent(Double.self, forKey: .middleZoneWidth) ?? def.middleZoneWidth
        edgeZoneWidth = try c.decodeIfPresent(Double.self, forKey: .edgeZoneWidth) ?? def.edgeZoneWidth
        edgeStepMM = try c.decodeIfPresent(Double.self, forKey: .edgeStepMM) ?? def.edgeStepMM
        edgeStartMM = try c.decodeIfPresent(Double.self, forKey: .edgeStartMM) ?? def.edgeStartMM
        edgeAcceleration = try c.decodeIfPresent(Double.self, forKey: .edgeAcceleration) ?? def.edgeAcceleration
        edgeMomentum = try c.decodeIfPresent(Double.self, forKey: .edgeMomentum) ?? def.edgeMomentum
        tapAndDrag = try c.decodeIfPresent(Bool.self, forKey: .tapAndDrag) ?? def.tapAndDrag
    }
}

struct Config: Codable {
    var settings = Settings()
    var gestures: [String: Action] = [:]
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/magicgestures/config.json")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/MagicGestures.log")

let defaultConfigText = """
{
  "settings": {
    "tapMaxSeconds": 0.25,
    "tapMaxMoveMM": 2.5,
    "swipeMinMM": 10,
    "swipeWindowSeconds": 0.35,
    "cooldownSeconds": 0.3,
    "middleZoneWidth": 0.2,
    "edgeZoneWidth": 0.18,
    "edgeStepMM": 5,
    "edgeStartMM": 3,
    "edgeAcceleration": 1.0,
    "edgeMomentum": 0.15,
    "tapAndDrag": true
  },
  "gestures": {
    "edge-left-up":   { "media": "volumeup-fine", "stepMM": 2.5 },
    "edge-left-down": { "media": "volumedown-fine", "stepMM": 2.5 },
    "tap3":         { "keys": "ctrl+up" },
    "swipe3-up":    { "keys": "f11" },
    "swipe3-down":  { "keys": "ctrl+down" },
    "swipe3-left":  { "keys": "cmd+shift+[" },
    "swipe3-right": { "keys": "cmd+shift+]" }
  }
}
"""

var config = Config()
var configMTime: Date?
let debug = CommandLine.arguments.contains("--debug")

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) \(s)\n"
    if debug { print(line, terminator: "") }
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func loadConfig() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: configURL.path) {
        try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? defaultConfigText.write(to: configURL, atomically: true, encoding: .utf8)
    }
    configMTime = (try? fm.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
    do {
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
        log("config loaded: \(config.gestures.keys.sorted().joined(separator: ", "))")
    } catch {
        log("config error (keeping previous bindings): \(error)")
    }
}

// MARK: - Actions

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
    "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
    "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
    "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

func sendKeys(_ combo: String) {
    var flags: CGEventFlags = []
    var code: CGKeyCode?
    var parts = combo.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    if combo.hasSuffix("+") { parts = Array(parts.dropLast(2)) + ["+"] }  // e.g. "cmd++"
    for p in parts {
        switch p {
        case "cmd", "command": flags.insert(.maskCommand)
        case "ctrl", "control": flags.insert(.maskControl)
        case "alt", "opt", "option": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        case "fn": flags.insert(.maskSecondaryFn)
        case "+": code = 24; flags.insert(.maskShift)
        default: code = keyCodes[p]
        }
    }
    guard let key = code else { log("unknown key in \"\(combo)\""); return }
    if (123...126).contains(Int(key)) { flags.insert([.maskSecondaryFn, .maskNumericPad]) }
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
    }
}

func sendMedia(_ name: String) {
    let map = ["volumeup": 0, "volumedown": 1, "mute": 7, "playpause": 16, "play": 16, "next": 17, "previous": 18]
    // "-fine" adds Option+Shift, which makes macOS move the volume in quarter steps
    // (1/64 of the range) while still showing its own volume overlay.
    let fine = name.lowercased().hasSuffix("-fine")
    let base = fine ? String(name.lowercased().dropLast(5)) : name.lowercased()
    guard let key = map[base] else { log("unknown media key \"\(name)\""); return }
    let mods: NSEvent.ModifierFlags = fine ? [.option, .shift] : []
    for down in [true, false] {
        let state = down ? 0xa : 0xb
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)).union(mods),
                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                           data1: (key << 16) | (state << 8), data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}

var lastTapClick = (time: 0.0, pos: CGPoint.zero, count: 0)
var lastSyntheticClick = 0.0

/// Clicks at the pointer. Left clicks made in quick succession on the same spot count
/// up as double and triple clicks, the way physical clicks do.
func sendClick(_ name: String) {
    let types: (CGEventType, CGEventType, CGMouseButton)
    switch name.lowercased() {
    case "left": types = (.leftMouseDown, .leftMouseUp, .left)
    case "right": types = (.rightMouseDown, .rightMouseUp, .right)
    case "middle": types = (.otherMouseDown, .otherMouseUp, .center)
    default: log("unknown click \"\(name)\""); return
    }
    let pos = CGEvent(source: nil)?.location ?? .zero
    let now = CACurrentMediaTime()
    var count = 1
    if types.2 == .left {
        let near = hypot(pos.x - lastTapClick.pos.x, pos.y - lastTapClick.pos.y) < 6
        if near, now - lastTapClick.time < NSEvent.doubleClickInterval { count = min(lastTapClick.count + 1, 3) }
        lastTapClick = (now, pos, count)
    }
    lastSyntheticClick = now
    let src = CGEventSource(stateID: .combinedSessionState)   // carries held modifier keys, e.g. Cmd-click
    for type in [types.0, types.1] {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: pos, mouseButton: types.2)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        e?.post(tap: .cghidEventTap)
    }
}

// Tap and drag: tap once (a left click), then touch again and keep the finger down.
// The left button is held for as long as the finger stays on the mouse, so moving the
// mouse drags; lifting the finger drops.
var dragCandidate = false    // second touch after a tap-click; becomes a drag if it stays down
var dragActive = false
var dragTap: CFMachPort?
var dragWatch: Timer?

/// While we hold the button down, the mouse still reports plain "moved" events;
/// apps only drag on "dragged" events, so they are converted here.
let dragTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if dragActive, let t = dragTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if dragActive, type == .mouseMoved { event.type = .leftMouseDragged }
    return Unmanaged.passUnretained(event)
}

func postLeftButton(_ type: CGEventType) {
    let pos = CGEvent(source: nil)?.location ?? .zero
    let e = CGEvent(mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: type,
                    mouseCursorPosition: pos, mouseButton: .left)
    e?.setIntegerValueField(.mouseEventClickState, value: 1)
    e?.post(tap: .cghidEventTap)
    lastSyntheticClick = CACurrentMediaTime()
}

func beginDrag() {
    dragCandidate = false
    guard !dragActive, let tap = dragTap else { return }
    dragActive = true
    sessionFired = true      // this touch is a drag, not a tap or swipe
    edgeSide = nil
    postLeftButton(.leftMouseDown)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("drag started")
    onGesture?("tap-and-drag", true)
    // Safety net: never leave the button held if the mouse stops reporting (e.g. it disconnects).
    dragWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        if CACurrentMediaTime() - lastFrameWall > 2 { endDrag() }
    }
}

func endDrag() {
    guard dragActive else { return }
    dragActive = false
    dragWatch?.invalidate(); dragWatch = nil
    if let t = dragTap { CGEvent.tapEnable(tap: t, enable: false) }
    postLeftButton(.leftMouseUp)
    lastTapClick.time = 0    // the next tap starts fresh, not as a double-click
    log("drag ended")
}

func run(_ a: Action) {
    if let k = a.keys { sendKeys(k) }
    if let m = a.media { sendMedia(m) }
    if let c = a.click { sendClick(c) }
    if let s = a.shell {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", s]
        try? p.run()
    }
}

// MARK: - Gesture recognition

struct Touch { var id: Int32; var state: Int32; var x: Double; var y: Double; var size: Double = 1 }  // x, y in mm
var onTouches: (([Touch]) -> Void)?

struct Track {
    var origin: CGPoint   // where the finger first landed
    var base: CGPoint     // reference point for swipe distance
    var baseTime: Double
    var last: CGPoint
}

var paused = false
var tracks: [Int32: Track] = [:]
var sessionStart: Double?
var sessionFired = false
var sessionClicked = false
var sessionMaxFingers = 0
var sessionMaxMove = 0.0
var sessionFirstX = 0.5      // normalised x of the first finger, for tap zones
var lastCount = 0
var lastFrameTime = 0.0
var lastFireTime = 0.0
var surfaceWidthMM = 51.5
var onGesture: ((String, Bool) -> Void)?

func mouseButtonActive() -> Bool {
    if dragActive { return false }   // the held button is ours
    if CGEventSource.buttonState(.combinedSessionState, button: .left) { return true }
    if CGEventSource.buttonState(.combinedSessionState, button: .right) { return true }
    // A click we sent ourselves for a tap must not make the next tap look like a physical click.
    if CACurrentMediaTime() - lastSyntheticClick < 0.6 { return false }
    let l = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
    let r = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
    return min(l, r) < 0.4
}

func fire(_ names: [String], at ts: Double) {
    let bound = names.first { config.gestures[$0] != nil }
    // Taps bound to a click skip the cooldown, so a double-tap is a double-click.
    let isClick = bound.flatMap { config.gestures[$0]?.click } != nil
    guard isClick || ts - lastFireTime >= config.settings.cooldownSeconds else { return }
    lastFireTime = ts
    sessionFired = true
    log("gesture \(names[0])" + (bound == nil ? " (unbound)" : " -> \(bound!)"))
    onGesture?(names[0], bound != nil)
    if let capture = captureGesture { capture(names[0]); return }
    if !paused, let b = bound, let a = config.gestures[b] { run(a) }
}

// Edge slide: one finger sliding along the left or right edge strip. Unlike other
// gestures it repeats, firing once per `edgeStepMM` of travel, and blocks scrolling.
var edgeSide: String?        // "left" / "right" while a slide may be in progress
var edgeAnchorY = 0.0
var edgeUsed = false
var edgeEngaged = false      // true once the finger has moved far enough to count as a slide
var edgeLastY = 0.0, edgeLastT = 0.0
var edgeVel = 0.0            // smoothed finger speed along the edge, mm/s (+ = toward the front)
var edgeAccum = 0.0          // effective travel not yet turned into steps, mm
var momentumTimer: Timer?

/// Faster movement counts for more: 1x when slow, up to 3x on a hard flick.
func edgeGain(_ speed: Double) -> Double {
    min(3, 1 + config.settings.edgeAcceleration * pow(speed / 200, 1.5))
}

/// Turns accumulated travel into repeats of the bound action (a few per frame at most,
/// so a burst is spread out instead of landing all at once).
func emitEdgeSteps(_ side: String) {
    let up = "edge-\(side)-up", down = "edge-\(side)-down"
    let step = max(0.5, config.gestures[up]?.stepMM ?? config.gestures[down]?.stepMM ?? config.settings.edgeStepMM)
    edgeAccum = min(step * 24, max(-step * 24, edgeAccum))
    var n = 0
    while edgeAccum >= step, n < 4 { edgeAccum -= step; n += 1; fireRepeat(up) }
    while edgeAccum <= -step, n < 4 { edgeAccum += step; n += 1; fireRepeat(down) }
}

func stopMomentum() { momentumTimer?.invalidate(); momentumTimer = nil }

/// After a flick, keeps going and slows down smoothly, like scrolling does.
func startMomentum(_ side: String, velocity: Double) {
    stopMomentum()
    let tau = config.settings.edgeMomentum
    guard tau > 0 else { return }
    var v = velocity, last = CACurrentMediaTime()
    momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        let now = CACurrentMediaTime(), dt = now - last
        last = now
        v *= exp(-dt / tau)
        edgeAccum += v * dt
        emitEdgeSteps(side)
        if abs(v) < 20 { stopMomentum() }
    }
}
var lastFrameWall = 0.0
var momentumBlockUntil = 0.0

func fireRepeat(_ name: String) {
    if !edgeUsed, momentumTimer == nil { log("gesture \(name) (repeats while sliding)") }
    edgeUsed = true
    sessionFired = true
    onGesture?(name, config.gestures[name] != nil)
    if let capture = captureGesture { capture(name); return }
    if let a = config.gestures[name] { run(a) }
}

/// Drops scroll events while an edge slide is in progress, plus the momentum that follows it.
let scrollTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = scrollTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let now = CACurrentMediaTime()
    if edgeSide != nil, now - lastFrameWall < 0.3 { return nil }
    if now < momentumBlockUntil, event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return nil }
    return Unmanaged.passUnretained(event)
}
var scrollTap: CFMachPort?

/// Needs Accessibility access, so this is retried until it succeeds.
func installScrollTap() {
    guard scrollTap == nil, AXIsProcessTrusted() else { return }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                                      callback: scrollTapCallback, userInfo: nil) else { return }
    scrollTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("scroll blocking for edge slides is active")
    if let d = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                 eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                                 callback: dragTapCallback, userInfo: nil) {
        dragTap = d
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, d, 0), .commonModes)
        CGEvent.tapEnable(tap: d, enable: false)   // only switched on during a drag
    }
}

func endSession(at ts: Double) {
    endDrag()   // lifting the finger drops whatever was being dragged
    defer {
        dragCandidate = false
        if edgeUsed { momentumBlockUntil = CACurrentMediaTime() + 1.5 }
        // A finger that was still moving when it lifted is a flick: coast on.
        if let side = edgeSide, edgeEngaged, ts - edgeLastT < 0.06, abs(edgeVel) > 60 {
            log(String(format: "flick %.0f mm/s", edgeVel))
            startMomentum(side, velocity: edgeVel)
        }
        edgeSide = nil; edgeUsed = false
        sessionStart = nil; tracks.removeAll(); lastCount = 0
    }
    guard let start = sessionStart, !sessionFired, !sessionClicked else { return }
    let s = config.settings
    guard ts - start <= s.tapMaxSeconds, sessionMaxMove <= s.tapMaxMoveMM, !mouseButtonActive() else { return }
    if sessionMaxFingers == 1 {
        let half = s.middleZoneWidth / 2
        let zone = sessionFirstX < 0.5 - half ? "left" : (sessionFirstX > 0.5 + half ? "right" : "middle")
        fire(["tap1-\(zone)", "tap1"], at: ts)
    } else {
        fire(["tap\(sessionMaxFingers)"], at: ts)
    }
}

func process(_ touches: [Touch], _ ts: Double) {
    let s = config.settings
    onTouches?(touches)
    if sessionStart != nil, ts - lastFrameTime > 0.3 { endSession(at: lastFrameTime) }
    lastFrameTime = ts
    lastFrameWall = CACurrentMediaTime()

    let active = touches.filter { $0.state == 4 }
    if debug, !touches.isEmpty {
        print(touches.map { String(format: "[id=%d st=%d x=%.1f y=%.1f]", $0.id, $0.state, $0.x, $0.y) }.joined(separator: " "))
    }
    if active.isEmpty {
        if sessionStart != nil { endSession(at: ts) }
        return
    }
    if sessionStart == nil {
        sessionStart = ts; sessionFired = false; sessionClicked = false
        sessionMaxFingers = 0; sessionMaxMove = 0
        sessionFirstX = active[0].x / surfaceWidthMM
        edgeSide = nil; edgeUsed = false; edgeEngaged = false
        stopMomentum()   // touching the mouse again stops a coasting flick
        edgeLastY = active[0].y; edgeLastT = ts; edgeVel = 0; edgeAccum = 0
        // A touch right after a tap-click, with the pointer still on the same spot, may be a drag.
        dragCandidate = false
        let pointer = CGEvent(source: nil)?.location ?? .zero
        if s.tapAndDrag, !paused, captureGesture == nil, active.count == 1,
           CACurrentMediaTime() - lastTapClick.time < 0.4,
           hypot(pointer.x - lastTapClick.pos.x, pointer.y - lastTapClick.pos.y) < 6 {
            dragCandidate = true
            // Frames normally decide this, but make sure a perfectly still finger still starts the drag.
            DispatchQueue.main.asyncAfter(deadline: .now() + s.tapMaxSeconds + 0.03) {
                if dragCandidate, sessionStart == ts { beginDrag() }
            }
        }
        if !paused, active.count == 1 {
            func bound(_ side: String) -> Bool {
                config.gestures["edge-\(side)-up"] != nil || config.gestures["edge-\(side)-down"] != nil
            }
            if sessionFirstX < s.edgeZoneWidth, bound("left") { edgeSide = "left" }
            else if sessionFirstX > 1 - s.edgeZoneWidth, bound("right") { edgeSide = "right" }
            edgeAnchorY = active[0].y
        }
    }
    if mouseButtonActive() { sessionClicked = true }

    let ids = Set(active.map { $0.id })
    for id in tracks.keys where !ids.contains(id) { tracks[id] = nil }
    for t in active {
        let p = CGPoint(x: t.x, y: t.y)
        if var tr = tracks[t.id] {
            tr.last = p
            sessionMaxMove = max(sessionMaxMove, hypot(p.x - tr.origin.x, p.y - tr.origin.y))
            // Slide the reference point forward if the finger has been slow, so a
            // swipe has to cover the distance within the time window.
            if ts - tr.baseTime > s.swipeWindowSeconds { tr.base = p; tr.baseTime = ts }
            tracks[t.id] = tr
        } else {
            tracks[t.id] = Track(origin: p, base: p, baseTime: ts, last: p)
        }
    }
    if active.count != lastCount {
        for id in tracks.keys { tracks[id]!.base = tracks[id]!.last; tracks[id]!.baseTime = ts }
        lastCount = active.count
    }
    sessionMaxFingers = max(sessionMaxFingers, active.count)

    if dragCandidate {
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let pointerMoved = hypot(pointer.x - lastTapClick.pos.x, pointer.y - lastTapClick.pos.y) > 4
        if active.count != 1 || sessionClicked || sessionMaxMove > s.tapMaxMoveMM {
            dragCandidate = false   // a click, a second finger, or a scroll: not a drag
        } else if ts - (sessionStart ?? ts) > s.tapMaxSeconds || pointerMoved {
            beginDrag()             // held past tap time, or the mouse started moving
        }
    }
    if dragActive { return }

    if let side = edgeSide {
        let t = active[0]
        let nx = t.x / surfaceWidthMM, limit = s.edgeZoneWidth * 1.8   // some sideways drift is fine
        let inStrip = side == "left" ? nx < limit : nx > 1 - limit
        if active.count != 1 || sessionMaxFingers > 1 || sessionClicked || !inStrip {
            edgeSide = nil   // not an edge slide after all; scrolling resumes
        } else {
            let dt = max(ts - edgeLastT, 0.002), dy = t.y - edgeLastY
            edgeLastY = t.y; edgeLastT = ts
            edgeVel = edgeVel * 0.6 + (dy / dt) * 0.4
            if !edgeEngaged {
                guard abs(t.y - edgeAnchorY) >= s.edgeStartMM else { return }
                edgeEngaged = true
            }
            edgeAccum += dy * edgeGain(abs(edgeVel))
            emitEdgeSteps(side)
            return
        }
    }

    guard !sessionFired, !sessionClicked, active.count >= 2, active.count == sessionMaxFingers else { return }
    var dir: String?
    for tr in tracks.values {
        let dx = tr.last.x - tr.base.x, dy = tr.last.y - tr.base.y
        guard hypot(dx, dy) >= s.swipeMinMM else { return }
        let d: String
        if abs(dx) > abs(dy) * 1.3 { d = dx > 0 ? "right" : "left" }
        else if abs(dy) > abs(dx) * 1.3 { d = dy > 0 ? "up" : "down" }
        else { return }
        if dir != nil && dir != d { return }
        dir = d
    }
    if let d = dir { fire(["swipe\(active.count)-\(d)"], at: ts) }
}

// MARK: - MultitouchSupport (private framework)

typealias MTDev = UnsafeMutableRawPointer
typealias MTFrameCallback = @convention(c) (MTDev, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
func mtSym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let p = dlsym(mt, name) else { return nil }
    return unsafeBitCast(p, to: type)
}
let MTDeviceCreateList = mtSym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>?).self)
let MTDeviceIsBuiltIn = mtSym("MTDeviceIsBuiltIn", (@convention(c) (MTDev) -> Bool).self)
let MTDeviceGetDeviceID = mtSym("MTDeviceGetDeviceID", (@convention(c) (MTDev, UnsafeMutablePointer<UInt64>) -> Int32).self)
let MTDeviceGetSensorSurfaceDimensions = mtSym("MTDeviceGetSensorSurfaceDimensions", (@convention(c) (MTDev, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self)
let MTRegisterContactFrameCallback = mtSym("MTRegisterContactFrameCallback", (@convention(c) (MTDev, MTFrameCallback) -> Void).self)
let MTUnregisterContactFrameCallback = mtSym("MTUnregisterContactFrameCallback", (@convention(c) (MTDev, MTFrameCallback) -> Void).self)
let MTDeviceStart = mtSym("MTDeviceStart", (@convention(c) (MTDev, Int32) -> Int32).self)
let MTDeviceStop = mtSym("MTDeviceStop", (@convention(c) (MTDev) -> Int32).self)

var surfaceMM = (w: 51.5, h: 90.5)

// Layout of one touch record (96 bytes): identifier @16, state @20, normalised x @32, y @36.
let frameCallback: MTFrameCallback = { _, data, n, ts, _ in
    var touches: [Touch] = []
    if let d = data {
        for i in 0..<Int(n) {
            let p = d + i * 96
            touches.append(Touch(id: p.load(fromByteOffset: 16, as: Int32.self),
                                 state: p.load(fromByteOffset: 20, as: Int32.self),
                                 x: Double(p.load(fromByteOffset: 32, as: Float.self)) * surfaceMM.w,
                                 y: Double(p.load(fromByteOffset: 36, as: Float.self)) * surfaceMM.h,
                                 size: Double(p.load(fromByteOffset: 48, as: Float.self))))
        }
    }
    DispatchQueue.main.async { process(touches, ts) }
    return 0
}

var devices: [AnyObject] = []   // keeps the registered devices alive
var deviceIDs: Set<UInt64> = []

/// Finds Magic Mice (external devices with a portrait sensor) and (re)registers when the set changes.
func scanDevices() {
    guard let create = MTDeviceCreateList, let reg = MTRegisterContactFrameCallback, let start = MTDeviceStart,
          let list = create()?.takeRetainedValue() as? [AnyObject] else { return }
    var found: [(AnyObject, UInt64)] = []
    for d in list {
        let dev = Unmanaged.passUnretained(d).toOpaque()
        var w: Int32 = 0, h: Int32 = 0, id: UInt64 = 0
        _ = MTDeviceGetSensorSurfaceDimensions?(dev, &w, &h)
        _ = MTDeviceGetDeviceID?(dev, &id)
        if MTDeviceIsBuiltIn?(dev) == false, h > w {
            found.append((d, id))
            surfaceMM = (Double(w) / 100, Double(h) / 100)
            surfaceWidthMM = surfaceMM.w
        }
    }
    let ids = Set(found.map { $0.1 })
    guard ids != deviceIDs || found.count != devices.count else { return }
    for d in devices {
        let dev = Unmanaged.passUnretained(d).toOpaque()
        MTUnregisterContactFrameCallback?(dev, frameCallback)
        _ = MTDeviceStop?(dev)
    }
    devices = found.map { $0.0 }
    deviceIDs = ids
    for d in devices {
        let dev = Unmanaged.passUnretained(d).toOpaque()
        reg(dev, frameCallback)
        _ = start(dev, 0)
    }
    log(devices.isEmpty ? "no Magic Mouse connected" : "listening to \(devices.count) Magic Mouse device(s)")
    onDevicesChanged?(devices.count)
}
var onDevicesChanged: ((Int) -> Void)?

// MARK: - Live touch viewer

/// Draws a top-down Magic Mouse and the fingers currently on it.
final class TouchView: NSView {
    var touches: [Touch] = []
    var trails: [Int32: [CGPoint]] = [:]
    var gesture = ""
    var gestureTime = Date.distantPast
    var lastUpdate = Date.distantPast
    let bodyMM = (w: 57.0, h: 113.0)   // physical mouse, seen from above

    let edgeMM = 2.5                   // finger centres stop about this far short of the physical edge

    // Self-calibrating outline. The sensor reports a plain rectangle, but the mouse has
    // rounded ends, so the true shape is learned: it starts as a conservative rounded
    // shape and grows to include every position a finger has actually touched
    // (kept as a convex hull in normalised sensor coordinates).
    var hull: [CGPoint] = TouchView.loadHull()
    var hullDirty = false

    static func defaultHull() -> [CGPoint] {
        let ry = 28.5 / 113.0, sx = 1 - 5.0 / 57.0, sy = 1 - 5.0 / 113.0
        return (0..<48).map { k in
            let a = 2 * Double.pi * Double(k) / 48
            let x = 0.5 + 0.5 * cos(a), y = (sin(a) >= 0 ? 1 - ry : ry) + ry * sin(a)
            return CGPoint(x: 0.5 + (x - 0.5) * sx, y: 0.5 + (y - 0.5) * sy)
        }
    }
    static func loadHull() -> [CGPoint] {
        guard let a = UserDefaults.standard.array(forKey: "hullShape") as? [Double], a.count >= 6, a.count % 2 == 0
        else { return defaultHull() }
        return stride(from: 0, to: a.count, by: 2).map { CGPoint(x: a[$0], y: a[$0 + 1]) }
    }
    func resetHull() {
        hull = TouchView.defaultHull()
        UserDefaults.standard.removeObject(forKey: "hullShape")
        needsDisplay = true
    }
    static func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
    /// Andrew's monotone chain; returns the hull counter-clockwise.
    static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let p = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard p.count > 2 else { return p }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for q in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
    static func contains(_ h: [CGPoint], _ q: CGPoint) -> Bool {
        guard h.count > 2 else { return false }
        for i in 0..<h.count where cross(h[i], h[(i + 1) % h.count], q) < -1e-6 { return false }
        return true
    }

    func update(_ t: [Touch]) {
        touches = t
        lastUpdate = Date()
        for x in t where x.state == 4 {
            let p = CGPoint(x: x.x / surfaceMM.w, y: x.y / surfaceMM.h)
            if !TouchView.contains(hull, p) {
                hull = TouchView.convexHull(hull + [p])
                hullDirty = true
            }
        }
        let ids = Set(t.map { $0.id })
        for id in trails.keys where !ids.contains(id) { trails[id] = nil }
        for x in t where x.state == 4 {
            trails[x.id, default: []].append(CGPoint(x: x.x, y: x.y))
            if trails[x.id]!.count > 25 { trails[x.id]!.removeFirst() }
        }
        needsDisplay = true
    }

    /// Clears fingers left on screen if the mouse stops reporting.
    func clearIfStale() {
        if !touches.isEmpty, Date().timeIntervalSince(lastUpdate) > 0.25 { update([]) }
        if hullDirty, touches.isEmpty {
            hullDirty = false
            UserDefaults.standard.set(hull.flatMap { [Double($0.x), Double($0.y)] }, forKey: "hullShape")
            log("viewer outline updated: \(hull.count) points")
        }
        if !gesture.isEmpty, Date().timeIntervalSince(gestureTime) > 1.5 { gesture = ""; needsDisplay = true }
    }

    override func draw(_ dirty: NSRect) {
        let footer = 56.0
        let area = NSRect(x: 24, y: footer, width: bounds.width - 48, height: bounds.height - footer - 24)
        let scale = min(area.width / bodyMM.w, area.height / bodyMM.h)
        let body = NSRect(x: area.midX - bodyMM.w * scale / 2, y: area.midY - bodyMM.h * scale / 2,
                          width: bodyMM.w * scale, height: bodyMM.h * scale)
        // Finger positions fill the body minus a small rim, since a fingertip's centre
        // can't sit exactly on the physical edge.
        let inner = body.insetBy(dx: edgeMM * scale, dy: edgeMM * scale)
        func mapX(_ n: Double) -> Double { inner.minX + n * inner.width }
        func norm(_ p: CGPoint) -> CGPoint { CGPoint(x: mapX(p.x), y: inner.minY + p.y * inner.height) }
        func point(_ p: CGPoint) -> CGPoint { norm(CGPoint(x: p.x / surfaceMM.w, y: p.y / surfaceMM.h)) }

        // Mouse body: the learned outline, pushed out by the rim and smoothed.
        let centre = CGPoint(x: inner.midX, y: inner.midY)
        let pts: [CGPoint] = hull.map { h in
            let p = norm(h), dx = p.x - centre.x, dy = p.y - centre.y, d = max(hypot(dx, dy), 0.001)
            return CGPoint(x: p.x + dx / d * edgeMM * scale, y: p.y + dy / d * edgeMM * scale)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let shell = NSBezierPath()
        var cur = mid(pts[pts.count - 1], pts[0])
        shell.move(to: cur)
        for i in 0..<pts.count {
            let ctrl = pts[i], end = mid(pts[i], pts[(i + 1) % pts.count])
            shell.curve(to: end,
                        controlPoint1: CGPoint(x: cur.x + (ctrl.x - cur.x) * 2 / 3, y: cur.y + (ctrl.y - cur.y) * 2 / 3),
                        controlPoint2: CGPoint(x: end.x + (ctrl.x - end.x) * 2 / 3, y: end.y + (ctrl.y - end.y) * 2 / 3))
            cur = end
        }
        shell.close()
        NSColor.controlBackgroundColor.setFill(); shell.fill()
        NSColor.tertiaryLabelColor.setStroke(); shell.lineWidth = 2; shell.stroke()

        // Tap zones for one-finger taps
        NSGraphicsContext.saveGraphicsState()
        shell.addClip()
        // Edge strips that have a slide gesture bound
        let zone = config.settings.edgeZoneWidth
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        if config.gestures["edge-left-up"] != nil || config.gestures["edge-left-down"] != nil {
            NSRect(x: body.minX - 20, y: body.minY - 20, width: mapX(zone) - body.minX + 20, height: body.height + 40).fill()
        }
        if config.gestures["edge-right-up"] != nil || config.gestures["edge-right-down"] != nil {
            NSRect(x: mapX(1 - zone), y: body.minY - 20, width: body.maxX - mapX(1 - zone) + 20, height: body.height + 40).fill()
        }
        let half = config.settings.middleZoneWidth / 2
        NSColor.quaternaryLabelColor.setStroke()
        for f in [0.5 - half, 0.5 + half] {
            let x = mapX(f)
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: body.minY)); line.line(to: CGPoint(x: x, y: body.maxY))
            line.setLineDash([4, 5], count: 2, phase: 0); line.lineWidth = 1; line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Trails, then fingers
        let accent = NSColor.controlAccentColor
        for trail in trails.values where trail.count > 1 {
            let path = NSBezierPath()
            path.move(to: point(trail[0]))
            for p in trail.dropFirst() { path.line(to: point(p)) }
            path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round
            accent.withAlphaComponent(0.35).setStroke(); path.stroke()
        }
        for t in touches {
            let c = point(CGPoint(x: t.x, y: t.y))
            let r = max(9, min(26, 8 + t.size * 9))
            let dot = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            if t.state == 4 {
                accent.withAlphaComponent(0.55).setFill(); dot.fill()
                accent.setStroke(); dot.lineWidth = 2; dot.stroke()
            } else {   // hovering or lifting
                NSColor.secondaryLabelColor.setStroke()
                dot.setLineDash([3, 3], count: 2, phase: 0); dot.lineWidth = 1.5; dot.stroke()
            }
        }

        // Footer text
        let n = touches.filter { $0.state == 4 }.count
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let count = n == 0 ? "No fingers on the mouse" : "\(n) finger\(n == 1 ? "" : "s")"
        count.draw(in: NSRect(x: 0, y: 28, width: bounds.width, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para])
        gesture.draw(in: NSRect(x: 0, y: 6, width: bounds.width, height: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: accent, .paragraphStyle: para])
    }
}

// MARK: - Settings window

let gestureCatalog: [(id: String, label: String)] = [
    ("tap1-left", "One-finger tap, left side"),
    ("tap1-middle", "One-finger tap, middle"),
    ("tap1-right", "One-finger tap, right side"),
    ("tap1", "One-finger tap, anywhere"),
    ("tap2", "Two-finger tap"),
    ("tap3", "Three-finger tap"),
    ("swipe2-up", "Two-finger swipe up"),
    ("swipe2-down", "Two-finger swipe down"),
    ("swipe2-left", "Two-finger swipe left"),
    ("swipe2-right", "Two-finger swipe right"),
    ("swipe3-up", "Three-finger swipe up"),
    ("swipe3-down", "Three-finger swipe down"),
    ("swipe3-left", "Three-finger swipe left"),
    ("swipe3-right", "Three-finger swipe right"),
    ("edge-left-up", "Left edge, slide up"),
    ("edge-left-down", "Left edge, slide down"),
    ("edge-right-up", "Right edge, slide up"),
    ("edge-right-down", "Right edge, slide down"),
]
func gestureLabel(_ id: String) -> String { gestureCatalog.first { $0.id == id }?.label ?? id }
func gestureOrder(_ id: String) -> Int { gestureCatalog.firstIndex { $0.id == id } ?? gestureCatalog.count }
func gestureNote(_ id: String) -> String? {
    if id.hasPrefix("edge-") { return "Repeats as you slide. Scrolling is blocked on that edge strip." }
    if id.hasPrefix("tap1") { return "One-finger taps are the easiest to trigger by accident." }
    if id == "tap2" { return "Also fires on the first tap of the system's two-finger double-tap." }
    if id == "swipe2-up" || id == "swipe2-down" { return "Two-finger vertical swipes also scroll the page." }
    if id == "swipe2-left" || id == "swipe2-right" { return "Overlaps with the system's two-finger swipe between pages." }
    return nil
}

let mediaOptions: [(id: String, label: String)] = [
    ("playpause", "Play / Pause"), ("next", "Next Track"), ("previous", "Previous Track"),
    ("volumeup", "Volume Up"), ("volumedown", "Volume Down"),
    ("volumeup-fine", "Volume Up (fine)"), ("volumedown-fine", "Volume Down (fine)"), ("mute", "Mute"),
]

func actionSummary(_ a: Action) -> String {
    var parts: [String] = []
    if let k = a.keys { parts.append("Shortcut: \(k)") }
    if let m = a.media { parts.append(mediaOptions.first { $0.id == m.lowercased() }?.label ?? "Media: \(m)") }
    if let s = a.shell { parts.append("Run: \(s)") }
    if let c = a.click { parts.append("\(c.capitalized) click") }
    return parts.isEmpty ? "No action" : parts.joined(separator: " + ")
}

/// Set while the editor waits for the user to perform a gesture on the mouse.
var captureGesture: ((String) -> Void)?

/// "cmd+shift+t" style text for a pressed key, or nil if the key isn't supported.
func comboString(for e: NSEvent) -> String? {
    let preferred: Set<String> = ["return", "delete", "escape"]
    var name: String?
    for (k, code) in keyCodes where code == e.keyCode {
        if name == nil || preferred.contains(k) { name = k }
    }
    guard let key = name else { return nil }
    var parts: [String] = []
    if e.modifierFlags.contains(.control) { parts.append("ctrl") }
    if e.modifierFlags.contains(.option) { parts.append("opt") }
    if e.modifierFlags.contains(.shift) { parts.append("shift") }
    if e.modifierFlags.contains(.command) { parts.append("cmd") }
    return (parts + [key]).joined(separator: "+")
}

final class SettingsModel: ObservableObject {
    @Published var gestures: [String: Action] = config.gestures
    @Published var settings: Settings = config.settings

    func refresh() { gestures = config.gestures; settings = config.settings }

    func save() {
        config.gestures = gestures
        config.settings = settings
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try enc.encode(config).write(to: configURL, options: .atomic)
            loadConfig()
        } catch {
            log("could not save config: \(error)")
        }
    }
}

enum ActionKind: String, CaseIterable, Identifiable {
    case keys = "Shortcut", media = "Media Key", shell = "Command", click = "Mouse Click"
    var id: String { rawValue }
}

struct EditorState: Identifiable {
    let id = UUID()
    var original: String?          // gesture being edited, nil when adding
    var gesture = "tap3"
    var kind = ActionKind.keys
    var keys = ""
    var media = "playpause"
    var shell = ""
    var click = "left"
    var stepMM = 2.5

    init(adding used: Set<String>) {
        gesture = gestureCatalog.first { !used.contains($0.id) }?.id ?? "tap3"
    }
    init(editing id: String, _ a: Action) {
        original = id; gesture = id
        if let k = a.keys { kind = .keys; keys = k }
        else if let m = a.media { kind = .media; media = m.lowercased() }
        else if let s = a.shell { kind = .shell; shell = s }
        else if let c = a.click { kind = .click; click = c.lowercased() }
        stepMM = a.stepMM ?? config.settings.edgeStepMM
    }

    var isEdge: Bool { gesture.hasPrefix("edge-") }
    var keysValid: Bool {
        guard let last = keys.lowercased().split(separator: "+").last else { return false }
        return keyCodes[String(last)] != nil || keys.hasSuffix("+")
    }
    var valid: Bool {
        switch kind {
        case .keys: return keysValid
        case .shell: return !shell.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
    var action: Action {
        var a = Action()
        switch kind {
        case .keys: a.keys = keys.lowercased()
        case .media: a.media = media
        case .shell: a.shell = shell
        case .click: a.click = click
        }
        if isEdge { a.stepMM = stepMM }
        return a
    }
}

struct EditorView: View {
    @State var s: EditorState
    let used: Set<String>
    let onSave: (EditorState) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detecting = false
    @State private var recording = false
    @State private var keyMonitor: Any?

    var replaces: Bool { used.contains(s.gesture) && s.gesture != s.original }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.original == nil ? "Add Gesture" : "Edit Gesture").font(.headline).padding([.top, .horizontal], 20)
            Form {
                Section("Gesture") {
                    Picker("Gesture", selection: $s.gesture) {
                        ForEach(gestureCatalog, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    HStack {
                        Button(detecting ? "Perform the gesture on the mouse…" : "Detect from Mouse") { toggleDetect() }
                        if detecting { ProgressView().controlSize(.small) }
                    }
                    if let note = gestureNote(s.gesture) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if replaces {
                        Text("This gesture already has an action. Saving replaces it.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Action") {
                    Picker("Type", selection: $s.kind) {
                        ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch s.kind {
                    case .keys:
                        HStack {
                            TextField("Shortcut", text: $s.keys, prompt: Text("e.g. cmd+shift+t"))
                            Button(recording ? "Press keys…" : "Record") { toggleRecord() }
                        }
                        if !s.keys.isEmpty && !s.keysValid {
                            Text("Unknown key. Use names like cmd+shift+t, ctrl+up, f11, space.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    case .media:
                        Picker("Key", selection: $s.media) {
                            ForEach(mediaOptions, id: \.id) { Text($0.label).tag($0.id) }
                        }
                    case .shell:
                        TextField("Command", text: $s.shell, prompt: Text("e.g. open -a Safari"))
                    case .click:
                        Picker("Button", selection: $s.click) {
                            Text("Left click").tag("left")
                            Text("Right click").tag("right")
                            Text("Middle click").tag("middle")
                        }
                        Text("Clicks at the pointer. Quick repeated left clicks count as double-clicks.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if s.isEdge {
                        HStack {
                            Text("Repeat every")
                            Slider(value: $s.stepMM, in: 1...15, step: 0.5)
                            Text(String(format: "%.1f mm", s.stepMM)).monospacedDigit().frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(s); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(!s.valid)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 460)
        .onDisappear { stopDetect(); stopRecord() }
    }

    func toggleDetect() {
        if detecting { stopDetect(); return }
        detecting = true
        captureGesture = { name in
            if gestureCatalog.contains(where: { $0.id == name }) { s.gesture = name }
            stopDetect()
        }
    }
    func stopDetect() { detecting = false; captureGesture = nil }

    func toggleRecord() {
        if recording { stopRecord(); return }
        recording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let plainEscape = e.keyCode == 53 && e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if !plainEscape, let combo = comboString(for: e) { s.keys = combo }
            stopRecord()
            return nil
        }
    }
    func stopRecord() {
        recording = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}

struct TuningRow: View {
    let title: String, help: String
    @Binding var value: Double
    let range: ClosedRange<Double>, step: Double, format: String
    let commit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step) { editing in if !editing { commit() } }
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var editor: EditorState?

    var ids: [String] { model.gestures.keys.sorted { (gestureOrder($0), $0) < (gestureOrder($1), $1) } }

    var body: some View {
        TabView {
            gesturesTab.tabItem { Label("Gestures", systemImage: "hand.tap") }
            tuningTab.tabItem { Label("Tuning", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .sheet(item: $editor) { st in
            EditorView(s: st, used: Set(model.gestures.keys)) { result in
                if let old = result.original, old != result.gesture { model.gestures[old] = nil }
                model.gestures[result.gesture] = result.action
                model.save()
            }
        }
    }

    var gesturesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ids.isEmpty {
                Spacer()
                Text("No gestures yet. Add one to get started.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(ids, id: \.self) { id in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gestureLabel(id))
                                Text(actionSummary(model.gestures[id] ?? Action()))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Edit") { editor = EditorState(editing: id, model.gestures[id] ?? Action()) }
                            Button(role: .destructive) {
                                model.gestures[id] = nil
                                model.save()
                            } label: { Image(systemName: "trash") }
                            .help("Remove this gesture")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            HStack {
                Button { editor = EditorState(adding: Set(model.gestures.keys)) } label: {
                    Label("Add Gesture…", systemImage: "plus")
                }
                Spacer()
                Text("Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    var tuningTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            TuningRow(title: "Edge strip width", help: "How much of each side counts as the edge for slide gestures.",
                      value: $model.settings.edgeZoneWidth, range: 0.08...0.35, step: 0.01, format: "%.2f", commit: model.save)
            TuningRow(title: "Slide acceleration", help: "How much faster movement counts for more. 0 is strictly linear.",
                      value: $model.settings.edgeAcceleration, range: 0...3, step: 0.1, format: "%.1f", commit: model.save)
            TuningRow(title: "Flick coasting", help: "How long a slide keeps going after a flick. 0 turns it off.",
                      value: $model.settings.edgeMomentum, range: 0...0.5, step: 0.01, format: "%.2f s", commit: model.save)
            TuningRow(title: "Slide start distance", help: "Movement needed before an edge slide begins.",
                      value: $model.settings.edgeStartMM, range: 0...8, step: 0.5, format: "%.1f mm", commit: model.save)
            TuningRow(title: "Swipe distance", help: "How far fingers must travel for a two- or three-finger swipe.",
                      value: $model.settings.swipeMinMM, range: 5...25, step: 0.5, format: "%.1f mm", commit: model.save)
            TuningRow(title: "Tap time", help: "The longest a touch can last and still count as a tap.",
                      value: $model.settings.tapMaxSeconds, range: 0.1...0.5, step: 0.01, format: "%.2f s", commit: model.save)
            Toggle(isOn: Binding(get: { model.settings.tapAndDrag },
                                 set: { model.settings.tapAndDrag = $0; model.save() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap and drag")
                    Text("Tap, then touch again and keep the finger down to drag. Lift to drop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Restore Defaults") { model.settings = Settings(); model.save() }
        }
        .padding(.top, 12).padding(.horizontal, 4)
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewerWindow: NSWindow?
    let touchView = TouchView(frame: NSRect(x: 0, y: 0, width: 300, height: 540))

    @objc func resetOutline() { touchView.resetHull() }

    var settingsWindow: NSWindow?
    let settingsModel = SettingsModel()

    @objc func showSettings() {
        settingsModel.refresh()
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settingsModel)))
            w.title = "MagicGestures Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A menu-bar-only app has no Edit menu, and without one Cmd+C/V/X/A don't work in text fields.
    func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        let holder = NSMenuItem()
        holder.submenu = edit
        main.addItem(holder)
        NSApp.mainMenu = main
    }

    @objc func showViewer() {
        if viewerWindow == nil {
            let w = NSWindow(contentRect: touchView.frame, styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Magic Mouse Touches"
            w.contentView = touchView
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.contentMinSize = NSSize(width: 200, height: 360)
            w.center()
            viewerWindow = w
            onTouches = { [weak self] t in
                guard let s = self, s.viewerWindow?.isVisible == true else { return }
                s.touchView.update(t)
            }
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.touchView.clearIfStale() }
        }
        viewerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var item: NSStatusItem!
    let statusLine = NSMenuItem(title: "No Magic Mouse connected", action: nil, keyEquivalent: "")
    let lastLine = NSMenuItem(title: "Last gesture: none yet", action: nil, keyEquivalent: "")
    let accessLine = NSMenuItem(title: "", action: #selector(openAccessibility), keyEquivalent: "")
    let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")

    func applicationWillTerminate(_ n: Notification) { endDrag() }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "MagicGestures")
        let menu = NSMenu()
        for i in [statusLine, lastLine, accessLine, .separator(),
                  NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","),
                  NSMenuItem(title: "Show Touch Viewer", action: #selector(showViewer), keyEquivalent: ""),
                  NSMenuItem(title: "Reset Viewer Outline", action: #selector(resetOutline), keyEquivalent: ""),
                  pauseItem,
                  NSMenuItem(title: "Edit Config…", action: #selector(editConfig), keyEquivalent: ""),
                  NSMenuItem(title: "Reload Config", action: #selector(reload), keyEquivalent: ""),
                  .separator(),
                  NSMenuItem(title: "Quit MagicGestures", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")] {
            if i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
            menu.addItem(i)
        }
        item.menu = menu

        onGesture = { [weak self] name, bound in
            self?.lastLine.title = "Last gesture: \(name)" + (bound ? "" : " (unbound)")
            self?.touchView.gesture = name
            self?.touchView.gestureTime = Date()
            self?.touchView.needsDisplay = true
        }
        if CommandLine.arguments.contains("--viewer") { showViewer() }
        installEditMenu()
        if CommandLine.arguments.contains("--settings") { showSettings() }
        onDevicesChanged = { [weak self] n in
            self?.statusLine.title = n == 0 ? "No Magic Mouse connected" : "Magic Mouse connected"
        }
        loadConfig()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        scanDevices()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            scanDevices()
            let m = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
            if m != configMTime { loadConfig(); self?.settingsModel.refresh() }
            self?.refreshAccess()
            installScrollTap()
        }
        log("accessibility access: \(AXIsProcessTrusted() ? "granted" : "MISSING")")
        installScrollTap()
        refreshAccess()
    }

    func refreshAccess() {
        let ok = AXIsProcessTrusted()
        accessLine.isHidden = ok
        accessLine.title = "⚠︎ Grant Accessibility access to send keys…"
    }
    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func togglePause() {
        paused.toggle()
        endDrag()
        pauseItem.title = paused ? "Resume" : "Pause"
        item.button?.appearsDisabled = paused
    }
    @objc func editConfig() {
        NSWorkspace.shared.open([configURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func reload() { loadConfig() }
}

setvbuf(stdout, nil, _IOLBF, 0)
guard mt != nil else { log("could not load MultitouchSupport"); exit(1) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
