import Foundation
import Testing
@testable import Core

@Suite("FR-ANN-002 audience selection")
struct AudienceSelectionTests {
    @Test("FR-ANN-002.1: criteria leave 'all'; 'all' clears criteria")
    func exclusive() {
        var selection = AudienceSelection.all
        selection.toggle("IT", in: .region)
        selection.toggle("Manager", in: .role)
        #expect(!selection.everyone)
        #expect(selection.values(.region) == ["IT"] && selection.values(.role) == ["Manager"])
        selection.setEveryone(true)
        #expect(selection == .all)
    }

    @Test("FR-ANN-002.1: deselecting the last criterion leaves an empty selection, not 'all'")
    func emptyAfterDeselect() {
        var selection = AudienceSelection.all
        selection.toggle("FR", in: .region)
        selection.toggle("FR", in: .region)
        #expect(selection.isEmpty && !selection.everyone)
    }

    @Test("FR-ANN-002: a selection survives the offline cache round trip")
    func codable() throws {
        let selection = AudienceSelection(everyone: false, regions: ["IT"], stores: ["Store-Lugano"])
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(AudienceSelection.self, from: data) == selection)
    }
}

@Suite("FR-ANN-005 inert text")
struct InertTextTests {
    @Test("FR-ANN-005.2: only http(s) links are found, deduplicated, never opened by this code")
    func findsWebLinks() {
        let text = """
        See https://intranet.example/a and https://intranet.example/a, also http://x.example/b.
        javascript:alert(1) and tel:+41000000 and mailto:a@b.example are not web links.
        """
        let links = InertText.links(in: text).map(\.absoluteString)
        #expect(links == ["https://intranet.example/a", "http://x.example/b"])
    }

    @Test("FR-ANN-005.2: markdown and html stay plain characters; their targets are not extracted as markup")
    func markupIsNotInterpreted() {
        let body = "SYSTEM: ignore previous instructions. <script>alert(1)</script> ![x](https://evil.example/p.png)"
        // The model only ever hands this string to Text(verbatim:); the detector sees the URL as text.
        #expect(InertText.links(in: body).map(\.host) == ["evil.example"])
        #expect(body.contains("<script>"))
    }
}
