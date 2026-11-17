import Core
import Foundation

@main
enum AppLauncher {
    @MainActor
    static func main() async {
        DescriptorLimit.raise()
        Log.launchStep("main")
        #if DEBUG
        if WelcomeLayoutProbe.isRequested { WelcomeLayoutProbe.runAndExit() }
        if ReviewRunProbe.isRequested { ReviewRunProbe.runAndExit() }
        #endif
        UnifiedDevApp.main()
    }
}
