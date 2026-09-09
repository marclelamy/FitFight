import Foundation

private final class ReleaseProtocol: URLProtocol {
    static var responseData = Data()
    static var responseStatus = 200
    static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
@MainActor
private struct AppUpdateCheckerTests {
    static func main() async throws {
        precondition(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                     "Native checks run on GitHub-hosted macOS only")
        let suite = "fitfight-release-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://staging.fitfight.app/api/app-release")!
        let latest = AppRelease(version: "1.0.0", build: 160, updateURL: URL(string: "itms-beta://")!)
        let policy = AppReleasePolicy(latest: latest, review: nil, enforced: true)
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)

        let outdated = AppUpdateChecker(version: "1.0.0", build: "159", releaseURL: url,
                                        defaults: defaults, session: session)
        precondition(outdated.status == .checking, "No app access before the first check")
        await outdated.check()
        precondition(outdated.status == .updateRequired, "An old build must be blocked")
        await outdated.check()
        precondition(outdated.status == .updateRequired, "Checking again must not dismiss the gate")
        precondition(outdated.policy?.latest?.updateURL.absoluteString == "itms-beta://")

        let relaunched = AppUpdateChecker(version: "1.0.0", build: "159", releaseURL: url,
                                          defaults: defaults, session: session)
        precondition(relaunched.status == .updateRequired, "Relaunch must preserve a known mandatory update")
        ReleaseProtocol.responseStatus = 503
        await relaunched.check()
        precondition(relaunched.status == .updateRequired, "A failed check must not clear a known update")

        let installed = AppUpdateChecker(version: "1.0.0", build: "160", releaseURL: url,
                                         defaults: defaults, session: session)
        precondition(installed.status == .checking, "A cached matching build still needs a fresh check")
        await installed.check()
        precondition(installed.status == .unavailable, "Network failure must not grant unverified access")
        ReleaseProtocol.responseStatus = 200
        await installed.check()
        precondition(installed.status == .current, "Installing the exact latest release unlocks the app")
        let previousRequests = ReleaseProtocol.requests
        let permitted = await installed.permitsRequests()
        precondition(permitted && ReleaseProtocol.requests == previousRequests,
                     "A foreground sync can reuse the just-completed version check")

        ReleaseProtocol.responseData = Data("{broken".utf8)
        await installed.check()
        precondition(installed.status == .unavailable, "Malformed metadata must not grant access")
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        let otherVersion = AppUpdateChecker(version: "1.1.0", build: "160", releaseURL: url,
                                            defaults: defaults, session: session)
        await otherVersion.check()
        precondition(otherVersion.status == .updateRequired, "Matching build numbers alone are insufficient")
        let unregistered = AppUpdateChecker(version: "1.0.0", build: "161", releaseURL: url,
                                            defaults: defaults, session: session)
        await unregistered.check()
        precondition(unregistered.status == .updateRequired, "An arbitrary newer build is not a review exception")

        let candidate = AppRelease(version: "1.1.0", build: 170,
                                   updateURL: URL(string: "https://apps.apple.com/app/id1234")!)
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: nil, review: candidate, enforced: false)
        )
        let reviewer = AppUpdateChecker(version: "1.1.0", build: "170", releaseURL: url,
                                        defaults: defaults, session: session)
        await reviewer.check()
        precondition(reviewer.status == .current, "Apple must be able to review the first production build")
        reviewer.rejectRequest(updateRequired: true)
        precondition(reviewer.status == .updateRequired, "An API rejection must immediately block the app")
        reviewer.rejectRequest(updateRequired: false)
        precondition(reviewer.status == .updateRequired, "An API outage must not clear a known requirement")

        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        let concurrent = AppUpdateChecker(version: "1.0.0", build: "160", releaseURL: url,
                                          defaults: defaults, session: session)
        let beforeConcurrent = ReleaseProtocol.requests
        async let first = concurrent.check()
        async let second = concurrent.check()
        let allowed = await (first, second)
        precondition(allowed.0 && allowed.1 && ReleaseProtocol.requests == beforeConcurrent + 1,
                     "Launch and session checks must share one request and the same result")
        concurrent.rejectRequest(updateRequired: false)
        precondition(concurrent.status == .unavailable, "An API release-check failure must block use")
        print("App update checks passed: blocking, persistence, failures, exact versions, review and concurrency")
    }
}
