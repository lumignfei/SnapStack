// Standalone regression checks: works with Command Line Tools, without XCTest.
@main
enum PermissionLaunchPolicyChecks {
    static func main() {
        // Existing system permission must win even when Continue was never clicked.
        for presented in [false, true] {
            for completed in [false, true] {
                precondition(!PermissionLaunchPolicy.shouldPresent(
                    screenGranted: true, hasPresented: presented, hasCompleted: completed),
                    "Granted permission must skip startup onboarding")
            }
        }
        precondition(PermissionLaunchPolicy.shouldPresent(
            screenGranted: false, hasPresented: false, hasCompleted: false),
            "A new installation without access needs onboarding")
        precondition(!PermissionLaunchPolicy.shouldPresent(
            screenGranted: false, hasPresented: true, hasCompleted: false),
            "Dismissing the guide must not cause repeated startup prompts")
        precondition(!PermissionLaunchPolicy.shouldPresent(
            screenGranted: false, hasPresented: false, hasCompleted: true),
            "After revocation, request access when a protected action is attempted")
        print("Permission launch regression checks: 7 cases passed")
    }
}
