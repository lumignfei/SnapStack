enum PermissionLaunchPolicy {
    static func shouldPresent(screenGranted: Bool, hasPresented: Bool, hasCompleted: Bool) -> Bool {
        // System permission is authoritative. The onboarding preference is only
        // presentation history, never a substitute for an actual permission check.
        !screenGranted && !hasPresented && !hasCompleted
    }
}
