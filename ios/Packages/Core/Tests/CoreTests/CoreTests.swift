import Testing
@testable import Core

@Test func moduleName() {
    #expect(Core.moduleName == "Core")
}

@MainActor
@Test("FR-AUTH: mode store defaults to classic and can be forced in DEBUG")
func modeStore() {
    let store = ModeStore()
    #expect(store.current == .classic)
    #if DEBUG
    store.setForDebug(.agent)
    #expect(store.current == .agent)
    #endif
}
