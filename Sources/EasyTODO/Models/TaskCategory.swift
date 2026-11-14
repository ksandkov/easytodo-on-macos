import AppKit
import SwiftUI

struct TaskCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String

    var color: Color {
        guard let hex = Self.normalizedColorHex(colorHex), let rgb = UInt32(hex, radix: 16) else {
            return .gray
        }
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }

    static func normalizedColorHex(_ value: String) -> String? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return hex.uppercased()
    }

    static func colorHex(from color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}
