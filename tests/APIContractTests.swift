import Foundation

@main
struct APIContractTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profileData = try Data(contentsOf: fixtures.appendingPathComponent("profile.json"))
        let profile = try decoder.decode(FitFightProfile.self, from: profileData)
        precondition(profile.userId.uuidString.lowercased() == "11111111-1111-4111-8111-111111111111")
        precondition(profile.atHandle == "@marc" && profile.initials == "ML")
        precondition(profile.handleSetAt == "2026-09-01T10:00:00Z")
        precondition(profile.referralCode?.uuidString.lowercased() == "22222222-2222-4222-8222-222222222222")

        guard var extendedProfile = try JSONSerialization.jsonObject(with: profileData) as? [String: Any] else {
            preconditionFailure("Profile fixture must be a JSON object")
        }
        extendedProfile["future_field"] = ["enabled": true]
        let extended = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(extended == profile)
        extendedProfile["handle"] = "user_123456789012"
        extendedProfile["handle_set_at"] = NSNull()
        let onboarding = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(onboarding.looksGenerated && onboarding.handleSetAt == nil)
        extendedProfile.removeValue(forKey: "handle_set_at")
        extendedProfile.removeValue(forKey: "referral_code")
        let cached = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(cached.handleSetAt == nil && cached.referralCode == nil)

        let snapshotData = try Data(contentsOf: fixtures.appendingPathComponent("fight-snapshot.json"))
        guard var extendedSnapshot = try JSONSerialization.jsonObject(with: snapshotData) as? [String: Any] else {
            preconditionFailure("Snapshot fixture must be a JSON object")
        }
        extendedSnapshot["future_field"] = true
        let snapshot = try decoder.decode(FitFightSnapshot.self,
            from: JSONSerialization.data(withJSONObject: extendedSnapshot))
        precondition(snapshot.fights.count == 1 && snapshot.members.count == 2)
        precondition(snapshot.fights[0].name == "September Steps" && snapshot.fights[0].actionText == nil)
        precondition(snapshot.members[0].currentValue == 8500 && snapshot.members[0].rank == 1)
        precondition(snapshot.members[0].lastSyncedAt != nil && snapshot.members[0].finalValue == nil)
        precondition(snapshot.members[1].state == "deferred" && snapshot.members[1].rank == nil)
        precondition(snapshot.profiles[0].handle == "marc" && snapshot.profiles[0].handleSetAt == nil)
        precondition(snapshot.series[0].joinCode == "ABCD" && snapshot.series[0].recurring)
        precondition(snapshot.stepDays[0].day == "2026-09-02" && snapshot.stepDays[0].steps == 8500)
        print("API contracts: profile, onboarding, cached profiles, extra fields, Fight snapshot passed")
    }
}
