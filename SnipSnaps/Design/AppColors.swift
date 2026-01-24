import SwiftUI

struct AppColor {
    static let primary = Color(red: 0, green: 0.478, blue: 1) // systemBlue
    static let background = Color(red: 0.95, green: 0.95, blue: 0.97) // systemGray6
    static let text = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let subtext = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let card = Color.white
    static let shadow = Color.black.opacity(0.08)
    static let delete = Color(red: 1.0, green: 0.23, blue: 0.19) // systemRed
    static let keep = Color(red: 0.2, green: 0.84, blue: 0.29) // systemGreen
    
    // Gradients
    static let gradient1 = LinearGradient(colors: [Color(hex: "84fab0"), Color(hex: "8fd3f4")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gradient2 = LinearGradient(colors: [Color(hex: "a1c4fd"), Color(hex: "c2e9fb")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gradient3 = LinearGradient(colors: [Color(hex: "ff9a9e"), Color(hex: "fecfef")], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
