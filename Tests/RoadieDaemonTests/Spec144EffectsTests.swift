import Foundation
import AppKit
import Testing
import TOMLKit
import RoadieCore
@testable import RoadieAX
@testable import RoadieDaemon

@Suite struct Spec144EffectsTests {
    @Test func oldConfigurationKeepsContourAndEffectsOff() throws {
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: "[fx.borders]\nenabled=true\n")
        #expect(config.fx.borders.enabled)
        #expect(config.fx.dropPreview == "contour")
        #expect(!config.fx.animations.policy(for: .move).enabled)
    }
    @Test func profilesAndActionOverridesAreIndependent() throws {
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: """
        [fx]
        drop_preview = "real"
        [fx.animations]
        enabled = true
        profile = "expressive"
        [fx.animations.move]
        duration_ms = 420
        curve = "linear"
        [fx.animations.stage]
        enabled = false
        """)
        #expect(config.fx.dropPreview == "real")
        let move = config.fx.animations.policy(for: .move)
        #expect(move.enabled && move.curve == .linear)
        #expect(abs(move.duration - 0.42) < 0.000001)
        #expect(!config.fx.animations.policy(for: .stage).enabled)
        #expect(config.fx.animations.policy(for: .rail).curve == .spring)
    }
    @Test func invalidValuesAreRejectedBeforeRuntime() {
        for raw in ["[fx]\ndrop_preview='photo'", "[fx.animations]\nprofile='unknown'", "[fx.animations]\nduration_ms=1001", "[fx.animations.move]\nstiffness=-1", "[fx.animations]\nintensity=nan"] {
            #expect(throws: (any Error).self) { try TOMLDecoder().decode(RoadieConfig.self, from: raw) }
        }
    }
    @Test func temporalCurvesHaveExactEndsAndAreMonotone() {
        for curve in [MotionCurve.linear, .easeOut, .easeInOut] {
            #expect(curve.progress(-1) == 0)
            #expect(curve.progress(1.2) == 1)
            var previous = -1.0
            for step in 0...100 {
                let value = curve.progress(Double(step) / 100)
                #expect(value >= previous && value >= 0 && value <= 1)
                previous = value
            }
        }
    }
    @Test func springRetargetPreservesVelocityAndConverges() {
        var state = MotionValue(value: 0)
        for _ in 0..<10 { state.advance(toward: 1, dt: 1.0 / 120, stiffness: 700, damping: 0.8) }
        let velocity = state.velocity
        #expect(velocity > 0)
        // Changer la cible n'efface ni valeur ni vitesse.
        let value = state.value
        state.advance(toward: -1, dt: 0, stiffness: 700, damping: 0.8)
        #expect(state.value == value && state.velocity == velocity)
        for _ in 0..<240 { state.advance(toward: -1, dt: 1.0 / 120, stiffness: 700, damping: 0.8) }
        #expect(abs(state.value + 1) < 0.00001)
        #expect(abs(state.velocity) < 0.00001)
    }
    @Test func springIsFiniteAcrossDampingRange() {
        for damping in [0.3, 0.8, 1, 1.5, 2] {
            var state = MotionValue(value: 100, velocity: 25)
            for _ in 0..<200 { state.advance(toward: -100, dt: 0.05, stiffness: 1500, damping: damping) }
            #expect(state.value.isFinite && state.velocity.isFinite)
            #expect(abs(state.value + 100) < 0.00001)
        }
    }
}

@Suite @MainActor struct Spec144AnimatorTests {
    @Test func finishesExactlyWithoutLeavingTimerOrCallback() {
        var now = 0.0
        let animator = EffectAnimator(schedulesTimer: false, clock: { now })
        var shown = -1.0, finishes = 0
        animator.animate(id: "test", from: [0], to: [100], policy: MotionPolicy(duration: 0.2)) {
            shown = $0[0]
        } completion: { finishes += 1 }
        now = 0.1; animator.tick()
        #expect(shown > 0 && shown < 100)
        now = 0.25; animator.tick()
        #expect(shown == 100 && finishes == 1 && animator.activeCount == 0 && !animator.hasTimer)
        now = 1; animator.tick()
        #expect(finishes == 1)
    }
    @Test func retargetStartsAtShownValueAndDoesNotRunOldCompletion() {
        var now = 0.0
        let animator = EffectAnimator(schedulesTimer: false, clock: { now })
        var shown = 0.0, oldFinished = false
        animator.animate(id: "test", from: [0], to: [100], policy: MotionPolicy(curve: .spring)) {
            shown = $0[0]
        } completion: { oldFinished = true }
        now = 0.05; animator.tick()
        let before = shown
        animator.animate(id: "test", from: [-1000], to: [-50], policy: MotionPolicy(curve: .spring)) { shown = $0[0] }
        #expect(shown == before)
        now = 1.1; animator.tick()
        #expect(shown == -50 && !oldFinished && animator.activeCount == 0)
    }
    @Test func disabledReplacesRunningTransitionWithExactDestination() {
        let animator = EffectAnimator(schedulesTimer: false)
        var shown = 0.0
        animator.animate(id: "test", from: [0], to: [100], policy: MotionPolicy()) { shown = $0[0] }
        animator.animate(id: "test", from: [0], to: [20], policy: MotionPolicy(enabled: false)) { shown = $0[0] }
        #expect(shown == 20 && animator.activeCount == 0 && !animator.hasTimer)
    }
}

extension Spec144AnimatorTests {
    @Test func roadieAloneControlsAnimations() {
        var config = AnimationsConfig()
        config.enabled = true
        for action in AnimationAction.allCases { #expect(config.policy(for: action).enabled) }
        config.enabled = false
        for action in AnimationAction.allCases { #expect(!config.policy(for: action).enabled) }
        config.enabled = true; config.profile = "none"
        for action in AnimationAction.allCases { #expect(!config.policy(for: action).enabled) }
    }
    @Test func realTimerIsReleasedAfterCompletion() async {
        let animator = EffectAnimator()
        animator.animate(id: "timer", from: [0], to: [1], policy: MotionPolicy(duration: 0.01)) { _ in }
        #expect(animator.hasTimer)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(animator.activeCount == 0 && !animator.hasTimer)
    }
}

extension Spec144AnimatorTests {
    @Test func durationIsIndependentOfIntensityAndAnUnchangedTargetCreatesNoTimer() {
        var now = 0.0
        let animator = EffectAnimator(schedulesTimer: false, clock: { now })
        var value = 0.0
        animator.animate(id: "duration", from: [0], to: [100], policy: MotionPolicy(duration: 0.2, intensity: 0.1)) { value = $0[0] }
        now = 0.15; animator.tick()
        #expect(value > 0 && value < 100 && animator.activeCount == 1)
        now = 0.2; animator.tick()
        #expect(value == 100 && animator.activeCount == 0)
        animator.animate(id: "still", from: [10], to: [10], policy: MotionPolicy()) { value = $0[0] }
        #expect(value == 10 && animator.activeCount == 0 && !animator.hasTimer)
    }
}

extension Spec144AnimatorTests {
    @Test func decorativePanelKeepsPassingClicksThroughDuringEffects() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 20, height: 20),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.orderOut(nil); panel.close() }
        panel.ignoresMouseEvents = true
        EffectAnimator.shared.visibility(panel, visible: true, action: .launcher, ignoresMouseEvents: true)
        #expect(panel.ignoresMouseEvents)
        EffectAnimator.shared.visibility(panel, visible: false, action: .launcher)
        #expect(panel.ignoresMouseEvents)
    }
}


extension Spec144EffectsTests {
    @Test func appearanceValuesApplyToFadesAndSpecificActionStillWins() {
        var config = AnimationsConfig(); config.enabled = true
        config.appearance.curve = "linear"; config.appearance.durationMS = 600
        config.appearance.intensity = 0.8
        let fade = config.policy(for: .launcher, usesAppearanceDefaults: true)
        #expect(fade.enabled && fade.curve == .linear && fade.duration == 0.6 && fade.intensity == 0.8)
        #expect(config.policy(for: .move).duration == 0.16)
        #expect(config.policy(for: .overview).duration == 0.16)
        config.launcher.durationMS = 250; config.launcher.curve = "ease_in_out"
        #expect(config.policy(for: .launcher, usesAppearanceDefaults: true).duration == 0.25)
        #expect(config.policy(for: .launcher, usesAppearanceDefaults: true).curve == .easeInOut)
        config.appearance.enabled = false
        #expect(!config.policy(for: .launcher, usesAppearanceDefaults: true).enabled)
        #expect(config.policy(for: .move).enabled)
    }
}


extension Spec144AnimatorTests {
    @Test func turningEffectsOffFinishesActiveTargetsWithoutRetiling() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        var retiles = 0
        let controller = SettingsLiveApplyController(configService: f.configService, stageStore: f.store,
            events: EventLog(path: f.directory.appendingPathComponent("live.jsonl").path), onLayoutChange: { _ in retiles += 1 })
        let before = f.store.state()
        let id = "144-cut-active"
        defer { EffectAnimator.shared.cancel(id) }
        var shown = 0.0
        EffectAnimator.shared.animate(id: id, from: [0], to: [100], policy: MotionPolicy(duration: 1)) { shown = $0[0] }
        #expect(EffectAnimator.shared.hasTimer)
        try "[fx.animations]\nenabled=false\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        controller.applyChange(configPath: path, settingID: "animations.enabled")
        #expect(shown == 100 && EffectAnimator.shared.activeCount == 0 && !EffectAnimator.shared.hasTimer)
        #expect(retiles == 0 && f.store.state() == before)
    }
}


extension Spec144EffectsTests {
    @Test func onlyAnActionlessRootContainerMayActAsAnElectronTitle() {
        let frame = CGRect(x: 100, y: 100, width: 900, height: 700)
        #expect(WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: frame, windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: ["AXShowMenu"], frame: frame, windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: CGRect(x: 100,y: 100,width: 160,height: 90), windowFrame: frame))
        for role in ["AXButton", "AXTabGroup", "AXTextField", "AXWebArea"] {
            #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: role, actions: [], frame: frame, windowFrame: frame))
        }
    }
}


extension Spec144EffectsTests {
    @Test func titleQualificationUsesTheSameFullBandAsTheDropDetector() {
        let frame = CGRect(x: 100, y: 100, width: 900, height: 700)
        for y in [8.0, 21.3, 33.305, 39, 43, 44] {
            #expect(WindowTitleDragAccess.isInTitleBand(CGPoint(x: 400, y: 100+y), frame: frame))
        }
        for point in [CGPoint(x: 179, y: 120), CGPoint(x: 994,y:120), CGPoint(x:400,y:107), CGPoint(x:400,y:145)] {
            #expect(!WindowTitleDragAccess.isInTitleBand(point, frame: frame))
        }
    }
}

extension Spec144AnimatorTests {
    @Test func dragQualificationPublishesWithoutWaitingForTheMainActor() throws {
        let window = powerWindow(42, x: 100, y: 100, width: 900, height: 700)
        let point = CGPoint(x: 400, y: 133.3)
        let state = WindowDragQualification(window: window, point: point)
        #expect(state.result == nil)
        let published = DispatchSemaphore(value: 0)
        Task.detached { state.complete(true); published.signal() }
        #expect(published.wait(timeout: .now() + 1) == .success)
        #expect(state.result == true && state.matches(window: window, point: point))
        var other = window; other.pid += 1
        #expect(!state.matches(window: other, point: point))
        other = window; other.frame.x += 9
        #expect(!state.matches(window: other, point: point))
        #expect(!state.matches(window: window, point: CGPoint(x: 500,y:133.3)))
    }
}


extension Spec144EffectsTests {
    @Test func aChromeTitleBandMustBeWideShallowAndAttachedToTheTop() {
        let frame = CGRect(x: 100, y: 100, width: 900, height: 700)
        let header = CGRect(x: 214, y: 100, width: 494, height: 41)
        #expect(WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: header, windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: ["AXPress"], frame: header, windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: header.offsetBy(dx: 0,dy: 50), windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: CGRect(x: 214,y:100,width:60,height:41), windowFrame: frame))
        #expect(!WindowTitleDragAccess.acceptsWindowContainer(role: "AXGroup", actions: [], frame: header.offsetBy(dx: 500,dy:0), windowFrame: frame))
    }
}
