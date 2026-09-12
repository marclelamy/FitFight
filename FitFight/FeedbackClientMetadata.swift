import Foundation
import UIKit

struct FitFightFeedbackMetadata: Equatable, Hashable {
    var appVersion: String?
    var appBuild: String?
    var backend: String?
    var bundleId: String?
    var language: String?
    var preferredLanguages: [String]?
    var locale: String?
    var region: String?
    var timeZone: String?
    var calendar: String?
    var hourCycle: String?
    var measurementSystem: String?
    var os: String?
    var osVersion: String?
    var deviceModel: String?
    var idiom: String?
    var look: String?
    var appearance: String?
    var layoutDirection: String?
    var contentSize: String?
    var reduceMotion: Bool?
    var boldText: Bool?
    var increaseContrast: Bool?
    var voiceOver: Bool?
    var lowPowerMode: Bool?
    var thermalState: String?
    var backgroundRefresh: String?
    var screenScale: Double?
    var screenWidth: Double?
    var screenHeight: Double?

    var isEmpty: Bool {
        debugLines.isEmpty
    }

    var debugLines: [String] {
        var lines: [String] = []
        let version = [appVersion, appBuild.map { "build \($0)" }, backend]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !version.isEmpty { lines.append(version) }

        let phone = [os, osVersion, deviceModel, idiom]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !phone.isEmpty { lines.append(phone) }

        let lang = [language, locale, region, timeZone]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !lang.isEmpty { lines.append(lang) }

        if let preferredLanguages, !preferredLanguages.isEmpty {
            lines.append(preferredLanguages.joined(separator: ", "))
        }

        var settings: [String] = []
        if let look { settings.append(look) }
        if let appearance { settings.append(appearance) }
        if let hourCycle { settings.append("\(hourCycle)h") }
        if let measurementSystem { settings.append(measurementSystem) }
        if let calendar { settings.append(calendar) }
        if let layoutDirection { settings.append(layoutDirection) }
        if let contentSize { settings.append(contentSize) }
        if reduceMotion == true { settings.append("reduce motion") }
        if boldText == true { settings.append("bold text") }
        if increaseContrast == true { settings.append("increase contrast") }
        if voiceOver == true { settings.append("VoiceOver") }
        if lowPowerMode == true { settings.append("Low Power") }
        if let thermalState { settings.append(thermalState) }
        if let backgroundRefresh { settings.append("BAR \(backgroundRefresh)") }
        if !settings.isEmpty { lines.append(settings.joined(separator: " · ")) }

        if let screenWidth, let screenHeight, let screenScale {
            lines.append(
                "\(Int(screenWidth.rounded()))×\(Int(screenHeight.rounded())) @\(screenScale.formatted(.number.precision(.fractionLength(0...1))))"
            )
        }
        if let bundleId { lines.append(bundleId) }
        return lines
    }

    var debugCaption: String? {
        let parts = [
            appVersion.flatMap { version in
                appBuild.map { "\(version) (\($0))" } ?? version
            },
            [os, osVersion].compactMap { $0 }.joined(separator: " ").nilIfEmpty,
            language,
            look,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @MainActor
    static func current() -> FitFightFeedbackMetadata {
        let locale = Locale.current
        let traits = UITraitCollection.current
        let screen = UIScreen.main.bounds
        var info = utsname()
        uname(&info)
        let model = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: info.machine)) {
                String(cString: $0)
            }
        }

        let hour: String?
        switch locale.hourCycle {
        case .zeroToEleven, .oneToTwelve:
            hour = "12"
        case .zeroToTwentyThree, .oneToTwentyFour:
            hour = "24"
        @unknown default:
            hour = nil
        }

        let idiom: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: idiom = "phone"
        case .pad: idiom = "pad"
        case .mac: idiom = "mac"
        default: idiom = "other"
        }

        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }

        let refresh: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: refresh = "available"
        case .denied: refresh = "denied"
        case .restricted: refresh = "restricted"
        @unknown default: refresh = "unknown"
        }

        return FitFightFeedbackMetadata(
            appVersion: AppVersion.marketing,
            appBuild: AppVersion.build,
            backend: AppVersion.backend,
            bundleId: Bundle.main.bundleIdentifier,
            language: locale.language.languageCode?.identifier,
            preferredLanguages: Array(Locale.preferredLanguages.prefix(8)),
            locale: locale.identifier,
            region: locale.region?.identifier,
            timeZone: TimeZone.current.identifier,
            calendar: String(describing: locale.calendar.identifier),
            hourCycle: hour,
            measurementSystem: locale.measurementSystem == .metric ? "metric" : "us",
            os: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: model,
            idiom: idiom,
            look: UserDefaults.standard.string(forKey: "ff.mode") ?? Mode.night.rawValue,
            appearance: traits.userInterfaceStyle == .dark ? "dark" : "light",
            layoutDirection: traits.layoutDirection == .rightToLeft ? "rtl" : "ltr",
            contentSize: UIApplication.shared.preferredContentSizeCategory.rawValue,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            boldText: UIAccessibility.isBoldTextEnabled,
            increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
            voiceOver: UIAccessibility.isVoiceOverRunning,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: thermal,
            backgroundRefresh: refresh,
            screenScale: UIScreen.main.scale,
            screenWidth: screen.width,
            screenHeight: screen.height
        )
    }
}

extension FitFightFeedbackMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
        case appBuild = "app_build"
        case backend
        case bundleId = "bundle_id"
        case language
        case preferredLanguages = "preferred_languages"
        case locale
        case region
        case timeZone = "time_zone"
        case calendar
        case hourCycle = "hour_cycle"
        case measurementSystem = "measurement_system"
        case os
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case idiom
        case look
        case appearance
        case layoutDirection = "layout_direction"
        case contentSize = "content_size"
        case reduceMotion = "reduce_motion"
        case boldText = "bold_text"
        case increaseContrast = "increase_contrast"
        case voiceOver = "voice_over"
        case lowPowerMode = "low_power_mode"
        case thermalState = "thermal_state"
        case backgroundRefresh = "background_refresh"
        case screenScale = "screen_scale"
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(appVersion, forKey: .appVersion)
        try container.encodeIfPresent(appBuild, forKey: .appBuild)
        try container.encodeIfPresent(backend, forKey: .backend)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(preferredLanguages, forKey: .preferredLanguages)
        try container.encodeIfPresent(locale, forKey: .locale)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(calendar, forKey: .calendar)
        try container.encodeIfPresent(hourCycle, forKey: .hourCycle)
        try container.encodeIfPresent(measurementSystem, forKey: .measurementSystem)
        try container.encodeIfPresent(os, forKey: .os)
        try container.encodeIfPresent(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try container.encodeIfPresent(idiom, forKey: .idiom)
        try container.encodeIfPresent(look, forKey: .look)
        try container.encodeIfPresent(appearance, forKey: .appearance)
        try container.encodeIfPresent(layoutDirection, forKey: .layoutDirection)
        try container.encodeIfPresent(contentSize, forKey: .contentSize)
        try container.encodeIfPresent(reduceMotion, forKey: .reduceMotion)
        try container.encodeIfPresent(boldText, forKey: .boldText)
        try container.encodeIfPresent(increaseContrast, forKey: .increaseContrast)
        try container.encodeIfPresent(voiceOver, forKey: .voiceOver)
        try container.encodeIfPresent(lowPowerMode, forKey: .lowPowerMode)
        try container.encodeIfPresent(thermalState, forKey: .thermalState)
        try container.encodeIfPresent(backgroundRefresh, forKey: .backgroundRefresh)
        try container.encodeIfPresent(screenScale, forKey: .screenScale)
        try container.encodeIfPresent(screenWidth, forKey: .screenWidth)
        try container.encodeIfPresent(screenHeight, forKey: .screenHeight)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
