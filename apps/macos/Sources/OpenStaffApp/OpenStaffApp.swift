import SwiftUI

@main
struct OpenStaffApp: App {
    var body: some Scene {
        WindowGroup("OpenStaff") {
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenStaff Baseline")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Phase 0 shell is ready.")
                    .font(.body)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Modes")
                        .font(.headline)
                    Text("- Teaching")
                    Text("- Assist")
                    Text("- Student")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 420, minHeight: 260)
        }
        .windowResizability(.contentSize)
    }
}
