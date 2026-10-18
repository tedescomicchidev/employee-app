import Core
import SwiftUI

public struct RootView: View {
    private let environment: AppEnvironment
    @State private var model: AppModel

    @MainActor
    public init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: AppModel(
            auth: environment.auth, me: environment.me, cleaner: environment.cleaner))
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .launching, .loadingProfile:
                LoadingView()
            case .signedOut, .signingIn:
                SignInView(model: model)
            case .signedIn:
                MainTabView(model: model, environment: environment)
            }
        }
        .task {
            await model.start()
            #if DEBUG
            if environment.autoSignIn, model.phase == .signedOut { await model.signIn() }
            #endif
        }
    }
}
