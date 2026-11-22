@_exported import Foundation

public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
    public static let zero = CGVector(dx: 0, dy: 0)
}
