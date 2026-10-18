import Foundation
import Testing
@testable import Core

@Suite("DesignSystem")
struct DesignSystemTests {
    private var colorsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Core/Resources/Colors.xcassets")
    }

    @Test("every DSColor has a colour set with light, dark and increased-contrast variants")
    func colorSetsComplete() throws {
        for name in DSColor.allNames {
            let url = colorsDir.appending(path: "\(name).colorset/Contents.json")
            let data = try Data(contentsOf: url)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let colors = try #require(json["colors"] as? [[String: Any]])
            #expect(colors.count == 4, "\(name) needs light, dark, light-HC, dark-HC")
        }
    }

    @Test("touch targets and spacing follow the tokens")
    func tokens() {
        #expect(DSSize.touch >= 44)
        #expect(DSSize.button == 50)
        #expect(DSSize.rowMin == 56)
        #expect(DSRadius.card == 26)
        #expect(DSSpacing.gutter == 16)
    }

    @Test("DSStrings resolve in DE, FR, IT, EN catalog")
    func stringsCatalog() throws {
        let url = colorsDir.deletingLastPathComponent().appending(path: "Localizable.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for (key, entry) in strings {
            let locs = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(locs.keys) == ["en", "de", "fr", "it"], "\(key)")
        }
    }
}
