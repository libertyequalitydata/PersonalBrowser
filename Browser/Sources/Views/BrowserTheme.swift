import SwiftUI

extension Color {
    static let browserAccent = Color(red: 0.0, green: 0.66, blue: 0.56)
    static let browserInk = Color(red: 0.04, green: 0.12, blue: 0.15)
    static let browserControl = Color(red: 0.25, green: 0.29, blue: 0.30)
    static let browserCanvas = Color(red: 0.965, green: 0.98, blue: 0.978)
    static let browserAddressField = Color(red: 0.91, green: 0.925, blue: 0.925)
    static let readerCanvas = Color(red: 0.985, green: 0.98, blue: 0.955)
    static let incognitoCanvas = Color(red: 0.045, green: 0.052, blue: 0.067)
    static let incognitoChrome = Color(red: 0.085, green: 0.095, blue: 0.12)
    static let incognitoSurface = Color(red: 0.12, green: 0.13, blue: 0.16)

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
