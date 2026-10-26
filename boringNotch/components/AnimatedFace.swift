//
//  AnimatedFace.swift
//  boringNotch
//
//  Created by Harsh Vardhan Goswami on 04/08/24.
//  Updated with cursor tracking and music groove dancing on 26/10/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class EyeTrackingViewModel: ObservableObject {
    @Published var isBlinking: Bool = false
    @Published var isLeftWinking: Bool = false
    @Published var isRightWinking: Bool = false
    @Published var isHappySquint: Bool = false
    @Published var grooveRotation: Double = 0
    @Published var leftOffset: CGSize = .zero
    @Published var rightOffset: CGSize = .zero

    private var timer: Timer?
    private var lastMouseLocation: NSPoint = .zero
    private var lastMovementTime: Date = Date()
    private var isIdleGlancing: Bool = false
    private var nextBlinkTime: Date = Date()
    private var screenUUID: String? = nil
    private var isMusicPlaying: Bool = false

    // Music groove states
    private var grooveStep: Double = 0
    private var lastBeatIndex: Int = 0
    private var nextExpressionBeat: Int = 8

    // Pending expression tasks (use Task instead of DispatchWorkItem for @MainActor safety)
    private var blinkTask: Task<Void, Never>?
    private var expressionTask: Task<Void, Never>?

    func start(
        eyeSpacing: CGFloat,
        maxOffset: CGFloat,
        screenUUID: String? = nil,
        isMusicPlaying: Bool = false
    ) {
        stop()
        self.screenUUID = screenUUID
        self.isMusicPlaying = isMusicPlaying
        lastMovementTime = Date()
        scheduleNextBlinkTime()
        grooveStep = 0
        lastBeatIndex = 0
        nextExpressionBeat = Int.random(in: 6...12)

        // Run at ~30 FPS on .common mode — MainActor.assumeIsolated is safe
        // because this timer is scheduled on RunLoop.main.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update(eyeSpacing: eyeSpacing, maxOffset: maxOffset)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        blinkTask?.cancel()
        blinkTask = nil
        expressionTask?.cancel()
        expressionTask = nil
        isHappySquint = false
        isLeftWinking = false
        isRightWinking = false
        isBlinking = false
        grooveRotation = 0
    }

    func setMusicPlaying(_ playing: Bool) {
        guard isMusicPlaying != playing else { return }
        isMusicPlaying = playing
        if !playing {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                grooveRotation = 0
                isHappySquint = false
                isLeftWinking = false
                isRightWinking = false
            }
        }
    }

    func setScreenUUID(_ uuid: String?) {
        guard screenUUID != uuid else { return }
        screenUUID = uuid
    }

    private func scheduleNextBlinkTime() {
        let interval = isMusicPlaying ? Double.random(in: 1.8...3.5) : Double.random(in: 2.8...5.5)
        nextBlinkTime = Date().addingTimeInterval(interval)
    }

    private func update(eyeSpacing: CGFloat, maxOffset: CGFloat) {
        let now = Date()

        // Check blink trigger
        if now >= nextBlinkTime && !isBlinking && !isLeftWinking && !isRightWinking {
            triggerBlink()
        }

        // Current mouse location in AppKit screen coordinates
        let mouseLoc = NSEvent.mouseLocation
        let deltaMove = hypot(mouseLoc.x - lastMouseLocation.x, mouseLoc.y - lastMouseLocation.y)

        if deltaMove > 0.5 {
            lastMouseLocation = mouseLoc
            lastMovementTime = now
            isIdleGlancing = false
        }

        // Target screen reference
        let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
            ?? NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let notchCenterX = screenFrame.midX
        let notchCenterY = screenFrame.maxY - 16

        // Compute base gaze vector towards cursor
        let leftEyePos = CGPoint(x: notchCenterX - (eyeSpacing / 2), y: notchCenterY)
        let gazeLeft = calculateEyeOffset(from: leftEyePos, to: mouseLoc, maxOffset: maxOffset)

        let rightEyePos = CGPoint(x: notchCenterX + (eyeSpacing / 2), y: notchCenterY)
        let gazeRight = calculateEyeOffset(from: rightEyePos, to: mouseLoc, maxOffset: maxOffset)

        if isMusicPlaying {
            // MARK: - Music Groove / Dancing Mode
            let tempoHz = 2.0
            grooveStep += (1.0 / 30.0) * tempoHz * (2.0 * .pi)

            // Head bop bounce
            let bounceY = -abs(sin(grooveStep)) * (maxOffset * 0.75)

            // Side sway and head tilt
            let swayX = sin(grooveStep * 0.5) * (maxOffset * 0.45)
            let tilt = sin(grooveStep * 0.5) * 4.2

            withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.8)) {
                self.grooveRotation = tilt
            }

            // Check beat transitions for musical expressions
            let currentBeat = Int(grooveStep / .pi)
            if currentBeat > lastBeatIndex {
                lastBeatIndex = currentBeat
                if currentBeat >= nextExpressionBeat {
                    triggerMusicExpression()
                    nextExpressionBeat = currentBeat + Int.random(in: 8...14)
                }
            }

            // Combine gaze tracking with groove bounce and sway
            let combinedLeft = CGSize(
                width: (gazeLeft.width * 0.55) + swayX,
                height: (gazeLeft.height * 0.55) + bounceY
            )
            let combinedRight = CGSize(
                width: (gazeRight.width * 0.55) + swayX,
                height: (gazeRight.height * 0.55) + bounceY
            )

            withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) {
                self.leftOffset = combinedLeft
                self.rightOffset = combinedRight
            }

        } else {
            // MARK: - Idle Gaze Tracking Mode
            self.grooveRotation = 0

            if deltaMove > 0.5 {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    self.leftOffset = gazeLeft
                    self.rightOffset = gazeRight
                }
            } else {
                let idleDuration = now.timeIntervalSince(lastMovementTime)
                if idleDuration > 4.0 {
                    handleIdleGlance(maxOffset: maxOffset)
                }
            }
        }
    }

    private func calculateEyeOffset(from eyePos: CGPoint, to mousePos: CGPoint, maxOffset: CGFloat) -> CGSize {
        let dx = mousePos.x - eyePos.x
        let dy = mousePos.y - eyePos.y // Up is positive in AppKit

        // In SwiftUI coordinates, down is positive
        let swiftDx = dx
        let swiftDy = -dy

        let distance = hypot(swiftDx, swiftDy)
        guard distance > 1.0 else { return .zero }

        let dirX = swiftDx / distance
        let dirY = swiftDy / distance

        // Distance factor: smoothly scale offset down if cursor is right on the notch
        let factor = min(1.0, max(0.15, distance / 120.0))

        return CGSize(
            width: dirX * maxOffset * factor,
            height: dirY * maxOffset * factor
        )
    }

    private func triggerMusicExpression() {
        guard !isBlinking && !isHappySquint && !isLeftWinking && !isRightWinking else { return }

        let roll = Double.random(in: 0...1)
        if roll < 0.45 {
            // Happy Squint (^ ^) enjoying the song
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                self.isHappySquint = true
            }
            expressionTask?.cancel()
            expressionTask = Task {
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    self.isHappySquint = false
                }
            }

        } else if roll < 0.75 {
            // Playful musical wink
            let isLeft = Bool.random()
            withAnimation(.easeInOut(duration: 0.08)) {
                if isLeft { self.isLeftWinking = true } else { self.isRightWinking = true }
            }
            expressionTask?.cancel()
            expressionTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    self.isLeftWinking = false
                    self.isRightWinking = false
                }
            }

        } else {
            // On-beat double blink
            triggerBlink()
        }
    }

    private func handleIdleGlance(maxOffset: CGFloat) {
        if !isIdleGlancing && Double.random(in: 0...1) < 0.02 {
            isIdleGlancing = true
            let randomAngle = Double.random(in: 0...(2 * .pi))
            let randomDist = CGFloat.random(in: 0.3...0.75) * maxOffset
            let glance = CGSize(
                width: cos(randomAngle) * randomDist,
                height: sin(randomAngle) * randomDist
            )

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.leftOffset = glance
                self.rightOffset = glance
            }

            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                guard self.isIdleGlancing else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.leftOffset = .zero
                    self.rightOffset = .zero
                }
                self.isIdleGlancing = false
                self.lastMovementTime = Date()
            }
        }
    }

    private func triggerBlink() {
        isBlinking = true
        blinkTask?.cancel()
        blinkTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self.isBlinking = false

            // 18% chance of quick double-blink
            if Double.random(in: 0...1) < 0.18 {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self.isBlinking = true
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                self.isBlinking = false
                self.scheduleNextBlinkTime()
            } else {
                self.scheduleNextBlinkTime()
            }
        }
    }

    deinit {
        timer?.invalidate()
        blinkTask?.cancel()
        expressionTask?.cancel()
    }
}

struct MinimalFaceFeatures: View {
    var height: CGFloat = 20
    var width: CGFloat = 30
    var screenUUID: String? = nil
    var isMusicPlaying: Bool = false

    @StateObject private var viewModel = EyeTrackingViewModel()

    // Dynamic sizing based on provided dimensions
    private var eyeSize: CGFloat {
        max(5.0, min(height, width) * 0.28)
    }

    private var eyeSpacing: CGFloat {
        eyeSize * 1.5
    }

    private var maxOffset: CGFloat {
        eyeSize * 0.55
    }

    init(
        height: CGFloat = 20,
        width: CGFloat = 30,
        screenUUID: String? = nil,
        isMusicPlaying: Bool = false
    ) {
        self.height = height
        self.width = width
        self.screenUUID = screenUUID
        self.isMusicPlaying = isMusicPlaying
    }

    var body: some View {
        HStack(spacing: eyeSpacing) {
            Eye(
                size: eyeSize,
                offset: viewModel.leftOffset,
                isBlinking: viewModel.isBlinking || viewModel.isLeftWinking,
                isHappy: viewModel.isHappySquint
            )
            Eye(
                size: eyeSize,
                offset: viewModel.rightOffset,
                isBlinking: viewModel.isBlinking || viewModel.isRightWinking,
                isHappy: viewModel.isHappySquint
            )
        }
        .rotationEffect(.degrees(viewModel.grooveRotation))
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .onAppear {
            viewModel.start(
                eyeSpacing: eyeSpacing,
                maxOffset: maxOffset,
                screenUUID: screenUUID,
                isMusicPlaying: isMusicPlaying
            )
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: isMusicPlaying) { _, newIsPlaying in
            viewModel.setMusicPlaying(newIsPlaying)
        }
        .onChange(of: screenUUID) { _, newUUID in
            viewModel.setScreenUUID(newUUID)
        }
    }
}

struct Eye: View {
    var size: CGFloat = 6.5
    var offset: CGSize = .zero
    var isBlinking: Bool = false
    var isHappy: Bool = false

    init(
        size: CGFloat = 6.5,
        offset: CGSize = .zero,
        isBlinking: Bool = false,
        isHappy: Bool = false
    ) {
        self.size = size
        self.offset = offset
        self.isBlinking = isBlinking
        self.isHappy = isHappy
    }

    init(isBlinking: Binding<Bool>) {
        self.size = 6.5
        self.offset = .zero
        self.isBlinking = isBlinking.wrappedValue
        self.isHappy = false
    }

    var body: some View {
        ZStack {
            if isHappy {
                // Happy curved "^" eye arc
                Path { path in
                    let w = size * 1.15
                    let h = size * 0.85
                    path.move(to: CGPoint(x: 0, y: h * 0.85))
                    path.addQuadCurve(
                        to: CGPoint(x: w, y: h * 0.85),
                        control: CGPoint(x: w / 2, y: -h * 0.15)
                    )
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: size * 1.15, height: size * 0.85)
                .offset(offset)
            } else {
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .scaleEffect(
                        x: isBlinking ? 1.25 : 1.0,
                        y: isBlinking ? 0.12 : 1.0,
                        anchor: .center
                    )
                    .offset(offset)
                    .animation(.easeInOut(duration: 0.08), value: isBlinking)
            }
        }
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            VStack(spacing: 20) {
                // Idle face
                MinimalFaceFeatures(isMusicPlaying: false)
                // Dancing face
                MinimalFaceFeatures(isMusicPlaying: true)
            }
        }
        .previewLayout(.fixed(width: 120, height: 100))
    }
}
