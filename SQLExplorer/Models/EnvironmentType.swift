import SwiftUI

enum EnvironmentLabel: String, Codable, CaseIterable, Identifiable {
    case development = "Development"
    case staging = "Staging"
    case production = "Production"
    case stagingNAM = "Staging - NAM"
    case productionNAM = "Production - NAM"
    case custom = "Custom"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .production, .productionNAM: return Color(hex: 0xF85149)
        case .staging, .stagingNAM: return Color(hex: 0xD29922)
        case .development: return Color(hex: 0x3FB950)
        case .custom: return Color(hex: 0x8B949E)
        }
    }

    var badgeBackground: Color {
        switch self {
        case .production, .productionNAM: return Color(hex: 0x2D1518)
        case .staging, .stagingNAM: return Color(hex: 0x2D2410)
        case .development: return Color(hex: 0x122117)
        case .custom: return Color(hex: 0x1A1F24)
        }
    }

    /// Resolve a stored string label back to an EnvironmentLabel
    static func from(_ string: String?) -> EnvironmentLabel? {
        guard let string else { return nil }
        return EnvironmentLabel.allCases.first { $0.rawValue == string }
            ?? .custom
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
