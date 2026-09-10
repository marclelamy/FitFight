import Foundation
import HealthKit

enum HealthKitActivityAggregates {
    static let lookbackDays = 29

    struct QuantityKind {
        let metric: String
        let unitName: String
        let type: HKQuantityType
        let unit: HKUnit
    }

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        for kind in quantityKinds {
            types.insert(kind.type)
        }
        types.insert(HKObjectType.workoutType())
        if let stand = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(stand)
        }
        if let effort = HKQuantityType.quantityType(forIdentifier: .physicalEffort) {
            types.insert(effort)
        }
        if #available(iOS 18.0, *) {
            if let score = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
                types.insert(score)
            }
            if let estimated = HKQuantityType.quantityType(forIdentifier: .estimatedWorkoutEffortScore) {
                types.insert(estimated)
            }
        }
        return types
    }

    static var quantityKinds: [QuantityKind] {
        var kinds: [QuantityKind] = []
        func add(
            _ metric: String,
            _ unitName: String,
            _ identifier: HKQuantityTypeIdentifier,
            _ unit: HKUnit
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
            kinds.append(QuantityKind(metric: metric, unitName: unitName, type: type, unit: unit))
        }
        add("active_energy", "kcal", .activeEnergyBurned, .kilocalorie())
        add("walking_running_distance", "m", .distanceWalkingRunning, .meter())
        add("exercise_minutes", "min", .appleExerciseTime, .minute())
        add("stand_minutes", "min", .appleStandTime, .minute())
        add("flights_climbed", "count", .flightsClimbed, .count())
        add("cycling_distance", "m", .distanceCycling, .meter())
        add("swimming_distance", "m", .distanceSwimming, .meter())
        add("move_time_minutes", "min", .appleMoveTime, .minute())
        add("wheelchair_distance", "m", .distanceWheelchair, .meter())
        add("wheelchair_pushes", "count", .pushCount, .count())
        add("swimming_strokes", "count", .swimmingStrokeCount, .count())
        add("downhill_snow_distance", "m", .distanceDownhillSnowSports, .meter())
        if #available(iOS 18.0, *) {
            add("rowing_distance", "m", .distanceRowing, .meter())
            add("paddle_distance", "m", .distancePaddleSports, .meter())
            add("skating_distance", "m", .distanceSkatingSports, .meter())
            add("cross_country_ski_distance", "m", .distanceCrossCountrySkiing, .meter())
        }
        return kinds
    }

    static func read(
        store: HKHealthStore,
        context: FitFightHealthKitContext
    ) async -> (
        days: [FitFightHealthKitStepSync.ActivityDay],
        workouts: [FitFightHealthKitStepSync.Workout]?
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: context.serverNow)
        let lookback = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let fightStart = context.fightWindows.map { calendar.startOfDay(for: $0.startsAt) }.min()
        let start = [lookback, fightStart].compactMap { $0 }.min() ?? lookback

        var totals: [String: [String: Double]] = [:]
        var workouts: [FitFightHealthKitStepSync.Workout]?
        await withTaskGroup(of: (String, [String: Double])?.self) { group in
            for kind in quantityKinds {
                group.addTask {
                    let values = try? await dailyTotals(
                        store: store,
                        type: kind.type,
                        unit: kind.unit,
                        start: start,
                        end: context.serverNow,
                        calendar: calendar
                    )
                    return values.map { (kind.metric, $0) }
                }
            }
            group.addTask {
                let values = try? await standHours(
                    store: store,
                    start: start,
                    end: context.serverNow,
                    calendar: calendar
                )
                return values.map { ("stand_hours", $0) }
            }
            for await result in group {
                guard let result else { continue }
                totals[result.0] = result.1
            }
        }

        do {
            let samples = try await workouts(
                store: store,
                start: start,
                end: context.serverNow
            )
            workouts = samples
            var counts: [String: Double] = [:]
            var seconds: [String: Double] = [:]
            var walkRun: [String: Double] = [:]
            for workout in samples {
                guard let started = parseISO8601(workout.startedAt) else { continue }
                let day = dayStamp(started, calendar: calendar)
                counts[day, default: 0] += 1
                seconds[day, default: 0] += workout.durationSeconds
                if workout.activityType == "walking" || workout.activityType == "running",
                   let distance = workout.distanceM {
                    walkRun[day, default: 0] += distance
                }
            }
            totals["workout_count"] = counts
            totals["workout_time"] = seconds
            totals["walk_run_workout_distance"] = walkRun
        } catch {
            workouts = nil
        }

        let units: [String: String] = [
            "active_energy": "kcal",
            "walking_running_distance": "m",
            "exercise_minutes": "min",
            "stand_minutes": "min",
            "stand_hours": "count",
            "flights_climbed": "count",
            "cycling_distance": "m",
            "swimming_distance": "m",
            "move_time_minutes": "min",
            "wheelchair_distance": "m",
            "wheelchair_pushes": "count",
            "swimming_strokes": "count",
            "rowing_distance": "m",
            "paddle_distance": "m",
            "skating_distance": "m",
            "cross_country_ski_distance": "m",
            "downhill_snow_distance": "m",
            "workout_count": "count",
            "workout_time": "s",
            "walk_run_workout_distance": "m",
        ]

        var days: [FitFightHealthKitStepSync.ActivityDay] = []
        var cursor = start
        while cursor < context.serverNow {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let day = dayStamp(cursor, calendar: calendar)
            let endsAt = min(nextDay, context.serverNow)
            for (metric, byDay) in totals {
                guard let value = byDay[day], let unit = units[metric] else { continue }
                days.append(FitFightHealthKitStepSync.ActivityDay(
                    day: day,
                    startsAt: iso8601(cursor),
                    endsAt: iso8601(endsAt),
                    metric: metric,
                    value: value,
                    unit: unit
                ))
            }
            cursor = nextDay
        }
        days.sort { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return lhs.metric < rhs.metric
        }
        return (days, workouts)
    }

    private static func dailyTotals(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var totals: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let value = quantityValue(statistics.sumQuantity(), unit: unit) else { return }
                    totals[dayStamp(statistics.startDate, calendar: calendar)] = value
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private static func standHours(
        store: HKHealthStore,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else {
            return [:]
        }
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        var totals: [String: Double] = [:]
        for sample in samples where sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
            totals[dayStamp(sample.startDate, calendar: calendar), default: 0] += 1
        }
        return totals
    }

    private static func workouts(
        store: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [FitFightHealthKitStepSync.Workout] {
        let samples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 200,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        return samples.map { workout in
            FitFightHealthKitStepSync.Workout(
                healthkitUuid: workout.uuid.uuidString.lowercased(),
                startedAt: iso8601(workout.startDate),
                endedAt: iso8601(workout.endDate),
                activityType: activityTypeName(workout.workoutActivityType),
                durationSeconds: max(0, workout.duration),
                distanceM: workoutDistanceMeters(workout),
                energyKcal: quantityValue(
                    workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity(),
                    unit: .kilocalorie()
                ),
                effort: workoutEffort(workout)
            )
        }
    }

    private static func workoutDistanceMeters(_ workout: HKWorkout) -> Double? {
        var identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .distanceWheelchair,
            .distanceDownhillSnowSports,
        ]
        if #available(iOS 18.0, *) {
            identifiers.append(contentsOf: [
                .distanceRowing,
                .distancePaddleSports,
                .distanceSkatingSports,
                .distanceCrossCountrySkiing,
            ])
        }
        return identifiers.compactMap { identifier in
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return quantityValue(workout.statistics(for: type)?.sumQuantity(), unit: .meter())
        }.max()
    }

    private static func workoutEffort(_ workout: HKWorkout) -> Double? {
        if #available(iOS 18.0, *) {
            for identifier in [HKQuantityTypeIdentifier.workoutEffortScore, .estimatedWorkoutEffortScore] {
                guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                      let value = quantityValue(
                        workout.statistics(for: type)?.averageQuantity()
                            ?? workout.statistics(for: type)?.sumQuantity(),
                        unit: .count()
                      )
                else { continue }
                return value
            }
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .physicalEffort) else { return nil }
        return quantityValue(
            workout.statistics(for: type)?.averageQuantity()
                ?? workout.statistics(for: type)?.sumQuantity(),
            unit: .applePhysicalEffortRating()
        )
    }

    private static func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .wheelchairWalkPace, .wheelchairRunPace: return "wheelchair"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .yoga: return "yoga"
        case .coreTraining: return "core"
        case .flexibility: return "flexibility"
        case .dance: return "dance"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairs"
        case .downhillSkiing: return "downhill_ski"
        case .snowboarding: return "snowboarding"
        case .crossCountrySkiing: return "cross_country_ski"
        case .paddleSports: return "paddle"
        case .skatingSports: return "skating"
        default: return "type_\(type.rawValue)"
        }
    }

    private static func quantityValue(_ quantity: HKQuantity?, unit: HKUnit) -> Double? {
        guard let quantity, quantity.is(compatibleWith: unit) else { return nil }
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value >= 0, value <= Double(HealthKitStepAggregates.maxCount) else {
            return nil
        }
        return value
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
