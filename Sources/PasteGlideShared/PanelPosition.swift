import Foundation

public enum PanelPosition: String, CaseIterable {
    case bottom
    case top
    case left
    case right
    case center

    public var title: String {
        switch self {
        case .bottom: "Bas"
        case .top: "Haut"
        case .left: "Gauche"
        case .right: "Droite"
        case .center: "Milieu"
        }
    }

    public var isVertical: Bool {
        self == .left || self == .right || self == .center
    }
}
