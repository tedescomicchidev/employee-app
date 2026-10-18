import Features
import MSAL
import SwiftUI

@main
struct EmployeeApp: App {
    private let environment = AppBootstrap.makeEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .onOpenURL { url in
                    _ = MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
                }
        }
    }
}
