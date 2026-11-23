import CoreGraphics

nonisolated enum SuggestionSlotLayout {
    static func widths(total: CGFloat, wanted: [CGFloat]) -> [CGFloat] {
        let floorW = total / 4
        var widths = wanted.map { max(floorW, $0) }
        let spare = total - widths.reduce(0, +)
        if spare >= 0 { return widths.map { $0 + spare / CGFloat(widths.count) } }
        var order = widths.indices.sorted { widths[$0] < widths[$1] }
        var share = total / CGFloat(widths.count)
        var remaining = total
        while let idx = order.first {
            if widths[idx] <= share {
                remaining -= widths[idx]
                order.removeFirst()
                share = order.isEmpty ? 0 : remaining / CGFloat(order.count)
            } else {
                for rest in order { widths[rest] = share }
                break
            }
        }
        return widths
    }
}
