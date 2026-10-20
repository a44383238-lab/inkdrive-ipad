import SwiftUI

@main struct InkDriveApp: App {
    @StateObject private var library = NativeLibraryStore()
    var body: some Scene {
        WindowGroup { LibraryRootView().environmentObject(library).preferredColorScheme(.light) }
    }
}
