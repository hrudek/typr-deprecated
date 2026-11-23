import CoreGraphics

extension KeyboardLayout {
    nonisolated static func typrAdaptsRows(posture: KeyboardPosture, pad: KeyboardPadPlacement?) -> Bool {
        pad == nil && !posture.splitsKeyboard
    }

    nonisolated static func typrHexPlacement(_ placement: HexKeyPlacement, bottomRow: BottomRow?, showsStrip: Bool) -> HexKeyPlacement {
        if let bottomRow {
            let order = bottomRow.order
            let typrFirst = (order.firstIndex(of: .typr) ?? 0) < (order.firstIndex(of: .space) ?? 0)
            return typrFirst ? .leftOfSpace : .rightOfSpace
        }
        guard !showsStrip, placement.isInStrip else { return placement }
        return placement == .stripLeading ? .leftOfSpace : .rightOfSpace
    }

    nonisolated static func typrBottomRowKeys(
        _ bottomRow: BottomRow,
        leading: [(KeyKind, CGFloat, String)],
        returnWidth: CGFloat,
        periodWidth: CGFloat,
        typrWidth: CGFloat
    ) -> (leading: [(KeyKind, CGFloat, String)], trailing: [(KeyKind, CGFloat, String)]) {
        var before = leading.filter { $0.0 != .hex }
        var after: [(KeyKind, CGFloat, String)] = []
        var pastSpace = false
        for key in bottomRow.order {
            let item: (KeyKind, CGFloat, String)
            switch key {
            case .space:
                pastSpace = true
                continue
            case .period:
                guard bottomRow.periodKey else { continue }
                item = (.character("."), periodWidth, ".")
            case .typr:
                item = (.hex, typrWidth, "hex")
            }
            if pastSpace { after.append(item) } else { before.append(item) }
        }
        after.append((.returnKey, returnWidth, "return"))
        return (before, after)
    }
}

extension KeyboardMetrics {
    nonisolated func typrWithoutStrip(_ orientation: KeyboardOrientation) -> KeyboardMetrics {
        KeyboardMetrics(
            side: side, gap: gap, rowGap: rowGap, keyHeight: keyHeight,
            stripTop: 0, stripHeight: 0, stripBottom: 0,
            keysTop: orientation == .landscape ? 4 : 6, keysBottom: keysBottom, cornerRadius: cornerRadius,
            bottomRowTrim: bottomRowTrim, bottomRowReturnColumn: bottomRowReturnColumn,
            bottomRowLeadColumn: bottomRowLeadColumn,
            modifierLetterRatio: modifierLetterRatio, pad: pad, accentCellWidth: accentCellWidth,
            numberRowHeight: numberRowHeight
        )
    }

    nonisolated func typrWithStrip(_ bar: KeyboardMetrics) -> KeyboardMetrics {
        KeyboardMetrics(
            side: side, gap: gap, rowGap: rowGap, keyHeight: keyHeight,
            stripTop: bar.stripTop, stripHeight: bar.stripHeight, stripBottom: bar.stripBottom,
            keysTop: keysTop, keysBottom: keysBottom, cornerRadius: cornerRadius,
            bottomRowTrim: bottomRowTrim, bottomRowReturnColumn: bottomRowReturnColumn,
            bottomRowLeadColumn: bottomRowLeadColumn,
            modifierLetterRatio: modifierLetterRatio, pad: pad, accentCellWidth: accentCellWidth,
            numberRowHeight: numberRowHeight
        )
    }
}
