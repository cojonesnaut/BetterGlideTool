import Cocoa

final class GestureProcessor {
    weak var engine: GestureEngine?

    /// How long the contact count may sit below a candidate's finger count before
    /// it counts as a change of hand. One finger's contact can flicker out for a
    /// frame or two mid-slide; treating that as the end of the gesture lost the
    /// whole swipe, which reads as the gesture simply not firing.
    static let fingerDropoutGrace: TimeInterval = 0.05
    
    init(engine: GestureEngine) {
        self.engine = engine
    }

    func handleTouches(_ frame: TouchFrameData, phase: GesturePhase, tuning: GestureTuning) -> GesturePhase? {
        let n = Int(frame.count)
        let now = ProcessInfo.processInfo.systemUptime
        // Hardware time for everything that turns distance into speed; `now` stays
        // in charge of what is compared against the engine's own clocks.
        let t = frame.timestamp > 0 ? frame.timestamp : now

        switch phase {
        case .idle:
            guard GestureRuleResolver.hasAnySwipeRule(fingers: n) else { return nil }
            if tuning.edgeMarginEnabled {
                let m = tuning.edgeMargin
                if frame.cx < m.left || frame.cx > (1.0 - m.right) || frame.cy < m.bottom || frame.cy > (1.0 - m.top) { return nil }
            }
            return .candidate(newCandidate(frame, fingers: n, time: t))

        case .candidate(var data):
            if n > data.fingers {
                guard GestureRuleResolver.hasAnySwipeRule(fingers: n) else { return .ignored }
                return .candidate(newCandidate(frame, fingers: n, time: t))
            }
            if n < data.fingers {
                // Skip the frame rather than reading it: its centroid and spread are
                // of a different set of contacts, and would show up as a jump.
                let since = data.fingerDropoutStart ?? t
                if t - since < Self.fingerDropoutGrace {
                    data.fingerDropoutStart = since
                    return .candidate(data)
                }
                // Held long enough to be deliberate: the hand is now using fewer
                // fingers, so match against those instead of dropping the gesture.
                guard GestureRuleResolver.hasAnySwipeRule(fingers: n) else { return .ignored }
                return .candidate(newCandidate(frame, fingers: n, time: t))
            }
            data.fingerDropoutStart = nil

            data.frameCount += 1
            let frameDx = frame.cx - data.prevCx
            let frameDy = frame.cy - data.prevCy
            let movedFromStart = ((frame.cx - data.startX) * (frame.cx - data.startX) + (frame.cy - data.startY) * (frame.cy - data.startY)).squareRoot()
            let frameDt = t - data.lastFrameTime
            data.lastFrameTime = t
            let isMoving = movedFromStart >= max(0.002, tuning.initialThreshold * 0.12)
            if isMoving {
                if data.movementStartTime == nil { data.movementStartTime = t }
                let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
                SpeedClassifier.appendVelocitySample(frameDist / Float(max(frameDt, 0.001)), to: &data.velocitySamples)
            }
            data.prevCx = frame.cx; data.prevCy = frame.cy
            let frameDelta = abs(frame.spread - data.prevSpread)
            data.cumulativeSpreadDelta += frameDelta
            data.prevSpread = frame.spread
            // Coherence is how well the fingers agree on a direction. Fingers that
            // have only just landed have no direction yet — their velocities are
            // sensor noise pointing anywhere — so a single resting frame used to set
            // a minimum low enough to veto the swipe that followed. Only frames
            // with real movement get a say.
            if isMoving, frame.coherence < data.minCoherence { data.minCoherence = frame.coherence }

            if frameDelta > tuning.pinchFrameSpreadThreshold * 1.5 { return .ignored }
            let totalSpreadChange = abs(frame.spread - data.initialSpread)
            if totalSpreadChange > 0.002 && totalSpreadChange > movedFromStart * 0.8 && data.frameCount >= 2 { return .ignored }

            let minFrames = max(Int(tuning.candidateFrames), 3)
            guard data.frameCount >= minFrames else { return .candidate(data) }

            if data.gestureKind == .unknown {
                data.classificationFrameDelay += 1
                if data.classificationFrameDelay >= 2 {
                    data.gestureKind = totalSpreadChange > movedFromStart * 0.8 ? .pinch : .swipe
                }
            }
            if data.gestureKind == .pinch { return .ignored }
            if totalSpreadChange > 0.002 && totalSpreadChange > movedFromStart * 0.5 { return .ignored }
            if data.cumulativeSpreadDelta > tuning.pinchSpreadThreshold { return .ignored }
            if data.minCoherence < tuning.swipeCoherenceThreshold { return .ignored }

            if data.cumulativeSpreadDelta < tuning.pinchSpreadThreshold && movedFromStart > totalSpreadChange && data.minCoherence >= tuning.swipeCoherenceThreshold {
                data.gestureKind = .swipe
                let swipeData = SwipeTrackData(
                    startX: data.startX, startY: data.startY, lastX: frame.cx, lastY: frame.cy,
                    fingers: data.fingers, startTime: data.startTime,
                    modifiersAtStart: data.modifiersAtStart, movementStartTime: data.movementStartTime,
                    velocitySamples: data.velocitySamples, lastFrameTime: t,
                    recentDeltas: [], initialSpread: data.initialSpread, prevSpread: frame.spread,
                    cumulativeSpreadDelta: data.cumulativeSpreadDelta, continuousRefX: frame.cx, continuousRefY: frame.cy,
                    lastContinuousActionTime: 0, continuousRule: nil, lockedSpeed: nil
                )
                return .lockedSwipe(swipeData)
            } else if data.frameCount >= minFrames + 5 {
                return .ignored
            } else {
                return .candidate(data)
            }

        case .lockedSwipe(let data):
            guard n == data.fingers else { return nil }
            return processSwipeFrame(frame, data: data, tuning: tuning)

        case .continuousSwipe(let data):
            guard n == data.fingers else { return nil }
            return processContinuousSwipeFrame(frame, data: data, tuning: tuning)

        default: return nil
        }
    }

    private func newCandidate(_ frame: TouchFrameData, fingers: Int, time: TimeInterval) -> CandidateData {
        CandidateData(
            startX: frame.cx, startY: frame.cy,
            fingers: fingers, startTime: time,
            initialSpread: frame.spread,
            modifiersAtStart: engine?.captureModifiers() ?? CapturedModifiers(NSEvent.modifierFlags),
            frameCount: 1, cumulativeSpreadDelta: 0,
            prevSpread: frame.spread, minCoherence: 1,
            prevCx: frame.cx, prevCy: frame.cy,
            movementStartTime: nil, lastFrameTime: time
        )
    }

    private func processSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, tuning: GestureTuning) -> GesturePhase {
        var updated = data
        let now = ProcessInfo.processInfo.systemUptime
        let t = frame.timestamp > 0 ? frame.timestamp : now
        let frameDx = frame.cx - data.lastX
        let frameDy = frame.cy - data.lastY
        let frameDist = (frameDx * frameDx + frameDy * frameDy).squareRoot()
        updated.lastX = frame.cx; updated.lastY = frame.cy
        updated.cumulativeSpreadDelta += abs(frame.spread - updated.prevSpread)
        updated.prevSpread = frame.spread

        let swipeCentroidMovement = ((frame.cx - updated.startX) * (frame.cx - updated.startX) + (frame.cy - updated.startY) * (frame.cy - updated.startY)).squareRoot()
        if abs(frame.spread - updated.initialSpread) > 0.003 && abs(frame.spread - updated.initialSpread) > swipeCentroidMovement * 0.8 {
            return .ignored
        }

        if updated.movementStartTime == nil, frameDist > 0 {
            updated.movementStartTime = t
        }
        let frameDt = t - updated.lastFrameTime
        updated.lastFrameTime = t
        SpeedClassifier.appendVelocitySample(frameDist / Float(max(frameDt, 0.001)), to: &updated.velocitySamples)
        updated.recentDeltas.insert((dx: frameDx, dy: frameDy), at: 0)
        if updated.recentDeltas.count > 120 {
            updated.recentDeltas.removeLast(updated.recentDeltas.count - 120)
        }

        var totalDx: Float = 0, totalDy: Float = 0
        var thresholdIndex: Int?
        for (i, d) in updated.recentDeltas.enumerated() {
            totalDx += d.dx; totalDy += d.dy
            if (totalDx * totalDx + totalDy * totalDy).squareRoot() >= tuning.initialThreshold {
                thresholdIndex = i; break
            }
        }
        guard let cutoff = thresholdIndex else { return .lockedSwipe(updated) }
        if cutoff + 1 < updated.recentDeltas.count { updated.recentDeltas.removeSubrange((cutoff + 1)...) }

        let angleDeg = atan2(totalDy, totalDx) * (180.0 / .pi)
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg
        guard let direction = GestureDirection.fromAngle(angle360, tolerance: tuning.swipeAngleTolerance) else { return .lockedSwipe(updated) }

        if engine?.consumeReciprocalToken(fingers: data.fingers, direction: direction, now: now) == true { return .fired }

        let candidateRules = GestureRuleResolver.matchingRules(fingers: data.fingers, direction: direction, modifiers: updated.modifiersAtStart)
        if updated.lockedSpeed == nil {
            let configuredSpeeds = Set(candidateRules.map { $0.speed == .any ? GestureSpeed.normal : $0.speed })
            let elapsed = max(t - (updated.movementStartTime ?? updated.startTime), 0.001)
            // Per-frame tuning thresholds date from a fixed-60fps assumption; ×60 converts
            // them to widths/second so existing user settings keep their meaning.
            let slowMax = tuning.slowVelocityThreshold * 60
            let fastMin = tuning.fastVelocityThreshold * 60
            let intent: GestureSpeed?
            switch tuning.speedLogic {
            case .simple:
                intent = SpeedClassifier.classify(
                    totalDisplacement: swipeCentroidMovement,
                    elapsedSeconds: elapsed,
                    configuredSpeeds: configuredSpeeds,
                    slowMax: slowMax,
                    fastMin: fastMin
                )
            case .classic:
                intent = SpeedClassifier.classifyClassic(
                    velocitySamples: updated.velocitySamples,
                    totalDisplacement: swipeCentroidMovement,
                    elapsedSeconds: elapsed,
                    configuredSpeeds: configuredSpeeds,
                    slowMax: slowMax,
                    fastMin: fastMin,
                    initialDistance: tuning.initialThreshold
                )
            }
            guard let intent else { return .lockedSwipe(updated) }
            updated.lockedSpeed = intent
        }
        let speed = updated.lockedSpeed ?? .normal

        if abs(frame.spread - updated.initialSpread) >= tuning.pinchSpreadThreshold * 0.8 || frame.coherence < max(tuning.swipeCoherenceThreshold, 0.55) { return .ignored }

        if let rule = GestureRuleResolver.bestRule(fingers: data.fingers, direction: direction, speed: speed, modifiers: updated.modifiersAtStart) {
            if rule.continuous {
                engine?.executeGestureRuleAction(rule)
                engine?.clearReciprocalToken()
                updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy; updated.lastContinuousActionTime = now; updated.continuousRule = rule
                return .continuousSwipe(updated)
            } else {
                engine?.executeSwipeRule(rule, fingers: data.fingers, direction: direction)
                return .fired
            }
        }
        return .fired
    }

    private func processContinuousSwipeFrame(_ frame: TouchFrameData, data: SwipeTrackData, tuning: GestureTuning) -> GesturePhase {
        var updated = data
        let now = ProcessInfo.processInfo.systemUptime
        updated.lastX = frame.cx; updated.lastY = frame.cy
        updated.prevSpread = frame.spread

        let swipeCentroidMovement = ((frame.cx - updated.startX) * (frame.cx - updated.startX) + (frame.cy - updated.startY) * (frame.cy - updated.startY)).squareRoot()
        if abs(frame.spread - updated.initialSpread) > 0.003 && abs(frame.spread - updated.initialSpread) > swipeCentroidMovement * 0.8 {
            engine?.executeContinuousEndAction(for: updated); return .ignored
        }

        let dx = frame.cx - updated.continuousRefX
        let dy = frame.cy - updated.continuousRefY
        guard (dx * dx + dy * dy).squareRoot() >= tuning.continuousStepThreshold else { return .continuousSwipe(updated) }

        let angleDeg = atan2(dy, dx) * (180.0 / .pi)
        let angle360 = angleDeg < 0 ? angleDeg + 360 : angleDeg
        guard let direction = GestureDirection.fromAngle(angle360, tolerance: tuning.swipeAngleTolerance) else {
            updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy; return .continuousSwipe(updated)
        }

        guard now - updated.lastContinuousActionTime >= tuning.continuousDebounce else { return .continuousSwipe(updated) }

        if let rule = updated.continuousRule, direction.matchesAxis(of: rule.direction) {
            let action = engine?.continuousUpdateAction(for: direction, in: rule) ?? .doNothing
            if action != .doNothing {
                engine?.executeContinuousAction(action, shortcut: engine?.continuousUpdateShortcut(for: direction, in: rule), keyboard: engine?.continuousUpdateKeyboard(for: direction, in: rule) ?? [], gesture: direction.title(fingers: data.fingers))
            }
            updated.lastContinuousActionTime = now
        }
        updated.continuousRefX = frame.cx; updated.continuousRefY = frame.cy
        return .continuousSwipe(updated)
    }
}
