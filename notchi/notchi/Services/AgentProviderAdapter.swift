import Foundation

nonisolated enum AgentHookInstallStatus: Equatable, Sendable {
    case installed
    case notInstalled
    case providerUnavailable
    case failed
}

nonisolated protocol AgentProviderAdapter: Sendable {
    nonisolated var provider: AgentProvider { get }

    @discardableResult
    nonisolated func installIfNeeded() -> Bool

    /// Returns whether the provider runtime itself is available on this machine,
    /// regardless of whether Notchi has installed hooks for it yet.
    nonisolated func isProviderAvailable() -> Bool
    nonisolated func isInstalled() -> Bool
    nonisolated func configureForLaunch()
    nonisolated func normalize(_ envelope: AgentHookEnvelope) -> HookEvent?
}

nonisolated extension AgentProviderAdapter {
    func installStatus() -> AgentHookInstallStatus {
        guard isProviderAvailable() else {
            return .providerUnavailable
        }
        return isInstalled() ? .installed : .notInstalled
    }

    @discardableResult
    func installIfNeededStatus() -> AgentHookInstallStatus {
        guard isProviderAvailable() else {
            return .providerUnavailable
        }
        guard installIfNeeded(), isInstalled() else {
            return .failed
        }
        return .installed
    }
}
