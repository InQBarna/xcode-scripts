import SwiftUI

@main
struct SampleApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Total: \(Calculator.add(1, 2))")
        }
    }
}
