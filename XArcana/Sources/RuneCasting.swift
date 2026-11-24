import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

enum RuneKind: String, CaseIterable {
    case zap, fireball, ice, shield, summon, nyan, revelio, lumos, patronus

    static var gestureCases: [RuneKind] { SpellCatalog.gestureRunes }

    var title: String { SpellCatalog.definition(for: self).title }

}

/// A press captures motion until release. Stillness never ends a held stroke.
struct RuneCasting {
    private(set) var isDrawing = false
    private var points: [CGPoint] = []
    private var measuredPoints: [CGPoint] = []
    private var previousAngles: SIMD2<Float>?
    private var position = CGPoint.zero
    private var filtered = CGPoint.zero
    private var firstSample: TimeInterval?
    private var lastSample: TimeInterval?
    private var pressedAt: TimeInterval = 0
    private var invalid = false
    private var stayedStill = true
    private var lastUpdate: TimeInterval?

    /// A preview never releases a spell. Readiness ends if this hold loses tracking or starts moving.
    var preview: RuneKind? {
        guard isDrawing, !invalid, let firstSample, let lastUpdate, let lastSample,
            lastUpdate - lastSample <= 0.4
        else { return nil }
        if stayedStill, lastSample - firstSample >= 1 { return .shield }
        guard lastSample - firstSample >= 0.14 else { return nil }
        return recognizedStroke
    }

    private var recognizedStroke: RuneKind? {
        if let measured = RuneRecognizer.recognize(measuredPoints) { return measured }
        // Include the current tip without moving existing visible ink or waiting for release.
        var complete = points
        Self.append(position, to: &complete)
        return RuneRecognizer.recognize(complete)
    }

    /// Fixed angular scale keeps existing ink still as a stroke grows.
    /// The first sample is at the center; points outside the square remain unclamped.
    var normalizedTrace: [CGPoint] {
        guard let origin = points.first else { return [] }
        return points.map {
            CGPoint(
                x: 0.5 + ($0.x - origin.x) / 1.1,
                y: 0.5 - ($0.y - origin.y) / 1.1)
        }
    }

    mutating func begin(angles: SIMD2<Float>?, at now: TimeInterval) {
        guard !isDrawing else { return }
        cancel()
        isDrawing = true
        pressedAt = now
        update(angles: angles, at: now)
    }

    /// Ignore a missing frame. A sustained gap or a jump would connect unrelated motion.
    mutating func update(angles: SIMD2<Float>?, at now: TimeInterval) {
        guard isDrawing, !invalid else { return }
        guard now.isFinite, now >= pressedAt, now - pressedAt <= 30,
            lastUpdate.map({ now >= $0 }) ?? true
        else {
            invalid = true
            return
        }
        lastUpdate = now
        if let lastSample, now - lastSample > 0.4 {
            invalid = true
            return
        }
        guard let angles else {
            stayedStill = false
            return
        }
        guard angles.x.isFinite, angles.y.isFinite else {
            invalid = true
            return
        }
        guard let previousAngles, let lastSample else {
            self.previousAngles = angles
            self.lastSample = now
            firstSample = now
            position = .zero
            filtered = .zero
            points = [.zero]
            measuredPoints = [.zero]
            return
        }
        let dt = now - lastSample
        guard dt >= 0 else {
            invalid = true
            return
        }
        guard dt > 0 else { return }
        let yaw = Double(angles.x) - Double(previousAngles.x)
        let delta = CGPoint(x: atan2(sin(yaw), cos(yaw)), y: Double(angles.y) - Double(previousAngles.y))
        guard hypot(delta.x, delta.y) < 0.6 else {
            invalid = true
            return
        }
        position.x += delta.x
        position.y += delta.y
        if hypot(position.x, position.y) > 0.04 { stayedStill = false }
        self.previousAngles = angles
        self.lastSample = now
        let alpha = 1 - exp(-dt / 0.035)
        filtered.x += alpha * (position.x - filtered.x)
        filtered.y += alpha * (position.y - filtered.y)
        Self.append(filtered, to: &points)
        // Do not turn a stationary charging hand's small tremor into a long prefix scribble.
        if !stayedStill { Self.append(position, to: &measuredPoints) }
        if points.count >= 4096 { invalid = true }
    }

    /// Release returns one spell synchronously, without a stillness wait.
    mutating func finish(angles: SIMD2<Float>?, at now: TimeInterval) -> RuneKind? {
        guard isDrawing else { return nil }
        defer { cancel() }
        update(angles: angles, at: now)
        guard !invalid, let firstSample, now - firstSample >= 0.14 else { return nil }
        if stayedStill, let lastSample, lastSample - firstSample >= 1 { return .shield }
        return recognizedStroke
    }

    /// Use for a canceled touch, backgrounding, recentering, or display changes.
    mutating func cancel() {
        isDrawing = false
        points.removeAll(keepingCapacity: true)
        measuredPoints.removeAll(keepingCapacity: true)
        previousAngles = nil
        firstSample = nil
        lastSample = nil
        lastUpdate = nil
        stayedStill = true
        invalid = false
    }

    private static func append(_ point: CGPoint, to points: inout [CGPoint]) {
        if points.last.map({ LightningRune.distance($0, point) >= 0.004 }) ?? true {
            points.append(point)
        }
    }
}

enum RuneRecognizer {
    static func recognize(_ points: [CGPoint]) -> RuneKind? {
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
            let bounds = LightningRune.bounds(points), max(bounds.width, bounds.height) <= 2.5
        else { return nil }
        if points.count >= 4 {
            if summon(points) { return .summon }
            if circle(points) { return .fireball }
        }
        if doubleVee(points) { return .nyan }
        if vee(points) { return .ice }
        return letterZ(points) || LightningRune.matches(points) ? .zap : nil
    }

    private static func doubleVee(_ input: [CGPoint]) -> Bool {
        guard input.count >= 5, let bounds = LightningRune.bounds(input),
            bounds.width >= 0.045, bounds.height >= 0.04
        else { return false }
        var points = LightningRune.resample(
            input.map {
                CGPoint(
                    x: ($0.x - bounds.minX) / bounds.width,
                    y: ($0.y - bounds.minY) / bounds.height)
            }, count: 64)
        if points[0].x > points[63].x { points.reverse() }
        guard points[63].x - points[0].x >= 0.62 else { return false }
        let backwards = zip(points, points.dropFirst()).reduce(CGFloat.zero) {
            $0 + max(0, $1.0.x - $1.1.x)
        }
        guard backwards < 0.60 else { return false }
        // Count substantial vertical turns, so rounded valleys and small hooks need no exact corners.
        var corners = [points[0]]
        var extreme = points[0]
        var descending = true
        for point in points.dropFirst() {
            if descending ? point.y < extreme.y : point.y > extreme.y {
                extreme = point
            } else if abs(point.y - extreme.y) >= 0.22 {
                corners.append(extreme)
                extreme = point
                descending.toggle()
            }
        }
        corners.append(extreme)
        guard corners.count == 5 else { return false }
        for index in 0..<4 {
            let rise = corners[index + 1].y - corners[index].y
            guard corners[index + 1].x - corners[index].x >= 0.035,
                (index % 2 == 0 ? -rise : rise) >= 0.22
            else { return false }
        }
        return true
    }

    private static func vee(_ input: [CGPoint]) -> Bool {
        guard input.count >= 3, let bounds = LightningRune.bounds(input),
            bounds.width >= 0.04, bounds.height >= 0.04
        else { return false }
        var points = LightningRune.resample(input, count: 48)
        guard points.count == 48 else { return false }
        if points[0].x > points[47].x { points.reverse() }
        let first = points[0]
        let last = points[47]
        guard last.x - first.x >= bounds.width * 0.72 else { return false }
        let extent = max(bounds.width, bounds.height)
        for tip in 8...39 {
            let bottom = points[tip]
            guard first.y - bottom.y >= bounds.height * 0.42,
                last.y - bottom.y >= bounds.height * 0.42,
                bottom.x - first.x >= bounds.width * 0.18,
                last.x - bottom.x >= bounds.width * 0.18
            else { continue }
            if LightningRune.fits(points, from: 0, to: tip, tolerance: extent * 0.13)
                && LightningRune.fits(points, from: tip, to: 47, tolerance: extent * 0.13)
            {
                return true
            }
        }
        return false
    }

    private static func letterZ(_ input: [CGPoint]) -> Bool {
        guard input.count >= 4, let bounds = LightningRune.bounds(input),
            bounds.width >= 0.04, bounds.height >= 0.04
        else { return false }
        var points = LightningRune.resample(input, count: 48)
        guard points.count == 48 else { return false }
        if points[0].y < points[47].y { points.reverse() }
        let first = points[0]
        let last = points[47]
        let extent = max(bounds.width, bounds.height)
        guard first.y - last.y >= bounds.height * 0.58,
            length(input) <= extent * 4.5
        else { return false }
        for left in 5...25 {
            for right in (left + 4)...42 {
                let upper = points[left]
                let lower = points[right]
                let direction: CGFloat = upper.x > first.x ? 1 : -1
                guard (upper.x - first.x) * direction >= bounds.width * 0.48,
                    (upper.x - lower.x) * direction >= bounds.width * 0.48,
                    (last.x - lower.x) * direction >= bounds.width * 0.48,
                    abs(upper.y - first.y) <= bounds.height * 0.43,
                    abs(last.y - lower.y) <= bounds.height * 0.43,
                    upper.y - lower.y >= bounds.height * 0.40
                else { continue }
                if LightningRune.fits(points, from: 0, to: left, tolerance: extent * 0.15)
                    && LightningRune.fits(points, from: left, to: right, tolerance: extent * 0.15)
                    && LightningRune.fits(points, from: right, to: 47, tolerance: extent * 0.15)
                {
                    return true
                }
            }
        }
        return false
    }

    private static func almostClosed(_ points: [CGPoint]) -> Bool {
        guard let first = points.first, let last = points.last,
            let bounds = LightningRune.bounds(points),
            min(bounds.width, bounds.height) >= 0.045
        else { return false }
        return LightningRune.distance(first, last) < max(bounds.width, bounds.height) * 1.02
    }

    private static func circle(_ points: [CGPoint]) -> Bool {
        guard almostClosed(points), let bounds = LightningRune.bounds(points),
            min(bounds.width, bounds.height) > 0.18 * max(bounds.width, bounds.height)
        else { return false }
        // Normalize width and height separately so a wrist-drawn oval counts as a circle.
        let oval = points.map {
            CGPoint(
                x: ($0.x - bounds.midX) * 2 / bounds.width,
                y: ($0.y - bounds.midY) * 2 / bounds.height)
        }
        let samples = LightningRune.resample(oval, count: 65)
        let center = CGPoint.zero
        let radii = samples.map { LightningRune.distance($0, center) }
        let radius = radii.reduce(0, +) / CGFloat(radii.count)
        let error = sqrt(radii.reduce(0) { $0 + pow($1 - radius, 2) } / CGFloat(radii.count))
        guard error < radius * 0.34, radii.filter({ $0 < radius * 0.38 }).count <= 3 else { return false }
        var rotation: CGFloat = 0
        var travel: CGFloat = 0
        for i in 1..<samples.count {
            let previous = atan2(samples[i - 1].y - center.y, samples[i - 1].x - center.x)
            let current = atan2(samples[i].y - center.y, samples[i].x - center.x)
            let delta = atan2(sin(current - previous), cos(current - previous))
            rotation += delta
            travel += abs(delta)
        }
        // A broad C, a lopsided oval, or an angular loop is enough; straight V/Z/W strokes stay distinct.
        return abs(rotation) > 3.85 && abs(rotation) < 8.0 && travel - abs(rotation) < 1.65
            && vertices(samples, tolerance: radius * 0.085).count >= 5
    }

    private static func summon(_ points: [CGPoint]) -> Bool {
        guard let bounds = LightningRune.bounds(points),
            min(bounds.width, bounds.height) >= 0.045
        else { return false }
        // Wrist motion can flatten the star. Compare turns in a unit square.
        let normalized = points.map {
            CGPoint(
                x: ($0.x - bounds.midX) / bounds.width,
                y: ($0.y - bounds.midY) / bounds.height)
        }
        let samples = LightningRune.resample(normalized, count: 81)
        let stroke = simplify(samples, tolerance: 0.065)
        guard (5...17).contains(stroke.count) else { return false }
        let strokeLength = length(stroke)
        // Ignore fine hand shake, but keep large extra strokes distinguishable.
        guard length(samples) < strokeLength * 1.33 else { return false }

        if crossedStar(stroke, length: strokeLength) { return true }
        // A short gap can complete an outline without adding an imaginary crossing.
        guard LightningRune.distance(stroke[0], stroke.last!) < 0.78 else { return false }
        let outline = vertices(samples + [samples[0]], tolerance: 0.045)
        guard (6...15).contains(outline.count) else { return false }
        let twiceArea = outline.indices.reduce(CGFloat.zero) { sum, i in
            let a = outline[i]
            let b = outline[(i + 1) % outline.count]
            return sum + a.x * b.y - a.y * b.x
        }
        let direction: CGFloat = twiceArea > 0 ? 1 : -1
        var notches = 0
        var tips = 0
        var sharpTips = 0
        var totalTurn: CGFloat = 0
        for i in outline.indices {
            let previous = outline[(i + outline.count - 1) % outline.count]
            let current = outline[i]
            let next = outline[(i + 1) % outline.count]
            let turn = direction * angle(previous, current, next)
            totalTurn += turn
            if turn < -0.23 && distanceToSegment(current, previous, next) > 0.048 { notches += 1 }
            if turn > 0.95 { tips += 1 }
            if turn > 1.55 { sharpTips += 1 }
        }
        // Allow one rounded tip. Sharp tips keep a wobbly oval from looking like a sparkle.
        return abs(totalTurn - 2 * .pi) < 0.35 && (3...6).contains(notches) && tips >= 4 && sharpTips >= 3
    }

    private static func crossedStar(_ stroke: [CGPoint], length: CGFloat) -> Bool {
        // Four long strokes already show three characteristic turns and multiple crossings.
        // Use the actual ink so a loop or zigzag cannot acquire a crossing from auto-closing.
        guard (2.7...8).contains(length) else { return false }
        var left = 0
        var right = 0
        for i in 1..<(stroke.count - 1) {
            let turn = angle(stroke[i - 1], stroke[i], stroke[i + 1])
            if turn > 1.35 { left += 1 }
            if turn < -1.35 { right += 1 }
        }
        guard (3...6).contains(max(left, right)), min(left, right) == 0 else { return false }
        var crossings = 0
        for i in 0..<(stroke.count - 3) {
            for j in (i + 2)..<(stroke.count - 1) {
                if crosses(stroke[i], stroke[i + 1], stroke[j], stroke[j + 1]) { crossings += 1 }
            }
        }
        return (2...7).contains(crossings)
    }

    private static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let ex = c.x - b.x
        let ey = c.y - b.y
        return atan2(dx * ey - dy * ex, dx * ex + dy * ey)
    }

    private static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + LightningRune.distance($1.0, $1.1) }
    }

    private static func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return LightningRune.distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared))
        return LightningRune.distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    private static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var largest: CGFloat = 0
        var index = 0
        for i in 1..<(points.count - 1) {
            let distance = distanceToSegment(points[i], points[0], points.last!)
            if distance > largest {
                largest = distance
                index = i
            }
        }
        guard largest > tolerance else { return [points[0], points.last!] }
        return Array(simplify(Array(points[0...index]), tolerance: tolerance).dropLast())
            + simplify(Array(points[index...]), tolerance: tolerance)
    }

    private static func vertices(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count >= 4 else { return [] }
        var closed = points
        closed[closed.count - 1] = closed[0]
        var corners = Array(simplify(closed, tolerance: tolerance).dropLast())
        // The sampled start can lie halfway along a polygon side.
        var changed = true
        while changed && corners.count > 3 {
            changed = false
            for i in corners.indices {
                let previous = corners[(i + corners.count - 1) % corners.count]
                let next = corners[(i + 1) % corners.count]
                if distanceToSegment(corners[i], previous, next) < tolerance {
                    corners.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return corners
    }
}

enum LightningRune {
    /// Match two descending strokes separated by a turn, in either drawing direction.
    static func matches(_ input: [CGPoint]) -> Bool {
        guard input.count >= 4, input.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
            let bounds = bounds(input), bounds.width >= 0.045, bounds.height >= 0.07
        else { return false }
        let extent = max(bounds.width, bounds.height)
        guard extent <= 2.5 else { return false }
        var points = resample(input, count: 40)
        guard points.count == 40 else { return false }
        if points[0].y < points[39].y { points.reverse() }
        let length = zip(input, input.dropFirst()).reduce(CGFloat.zero) { $0 + distance($1.0, $1.1) }
        guard length >= 0.14, length < extent * 4.5 else { return false }

        // Search both corners after arc-length resampling so speed and pauses do not affect the fit.
        for first in 4...25 {
            for second in (first + 3)...35 {
                let a = points[0]
                let b = points[first]
                let c = points[second]
                let d = points[39]
                let firstDrop = a.y - b.y
                let lastDrop = c.y - d.y
                let direction: CGFloat = a.x >= b.x ? 1 : -1
                let firstLeft = (a.x - b.x) * direction
                let lastLeft = (c.x - d.x) * direction
                let right = (c.x - b.x) * direction
                guard firstDrop > bounds.height * 0.15, lastDrop > bounds.height * 0.15,
                    firstLeft > bounds.width * 0.18, lastLeft > bounds.width * 0.18,
                    right > bounds.width * 0.22,
                    abs(c.y - b.y) < min(right * 1.55, bounds.height * 0.55),
                    a.y - d.y >= bounds.height * 0.58
                else { continue }
                if fits(points, from: 0, to: first, tolerance: extent * 0.105)
                    && fits(points, from: first, to: second, tolerance: extent * 0.105)
                    && fits(points, from: second, to: 39, tolerance: extent * 0.105)
                {
                    return true
                }
            }
        }
        return false
    }

    static func bounds(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func fits(_ points: [CGPoint], from start: Int, to end: Int, tolerance: CGFloat) -> Bool {
        let a = points[start]
        let b = points[end]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let chord = distance(a, b)
        guard chord > 0 else { return false }
        var length: CGFloat = 0
        var squaredError: CGFloat = 0
        for i in (start + 1)...end {
            let point = points[i]
            let projection = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (chord * chord)))
            let error = distance(point, CGPoint(x: a.x + projection * dx, y: a.y + projection * dy))
            guard error < tolerance * 2 else { return false }
            squaredError += error * error
            length += distance(points[i - 1], point)
        }
        return length / chord < 1.3 && sqrt(squaredError / CGFloat(end - start)) < tolerance
    }

    static func resample(_ input: [CGPoint], count: Int) -> [CGPoint] {
        var cumulative: [CGFloat] = [0]
        for i in 1..<input.count { cumulative.append(cumulative.last! + distance(input[i - 1], input[i])) }
        guard let total = cumulative.last, total > 0 else { return [] }
        var segment = 1
        return (0..<count).map { index in
            let position = total * CGFloat(index) / CGFloat(count - 1)
            while segment < input.count - 1 && cumulative[segment] < position { segment += 1 }
            let span = cumulative[segment] - cumulative[segment - 1]
            let fraction = span > 0 ? (position - cumulative[segment - 1]) / span : 0
            let a = input[segment - 1]
            let b = input[segment]
            return CGPoint(x: a.x + fraction * (b.x - a.x), y: a.y + fraction * (b.y - a.y))
        }
    }
}

#if canImport(UIKit)
    final class RuneTrail: UIView {
        private let trail = CAShapeLayer()
        private var points: [CGPoint] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            backgroundColor = .clear
            trail.fillColor = UIColor.clear.cgColor
            trail.strokeColor = UIColor(red: 1, green: 0.83, blue: 0.43, alpha: 1).cgColor
            trail.lineWidth = 3
            trail.lineCap = .round
            trail.lineJoin = .round
            trail.shadowColor = trail.strokeColor
            trail.shadowOpacity = 0.85
            trail.shadowRadius = 8
            trail.shadowOffset = .zero
            layer.addSublayer(trail)
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(points: [CGPoint], active: Bool) {
            self.points = points
            isHidden = !active
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let side = min(bounds.width, bounds.height)
            let origin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
            let path = UIBezierPath()
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trail.frame = bounds
            trail.path = path.cgPath
            CATransaction.commit()
        }
    }
#endif
