import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Thin actor around `HKHealthStore` that exposes only what MIND needs:
/// permission gating and "give me the last 7 days of activity".
///
/// Three deliberate design choices:
///
///   1. **Actor**, not @MainActor — HKHealthStore is thread-safe but its
///      queries block. Running them off the main actor keeps HomeView's
///      scroll latency clean. The summary is published back to SwiftUI
///      via the caller's @State, not via @Published, so the actor never
///      has to hop to main.
///
///   2. **Single shared store** — Apple's docs are explicit: keep one
///      HKHealthStore alive for the lifetime of the process. Recreating
///      it on every call leaks file descriptors and (worse) loses change
///      notifications when the user logs new data while the app is in
///      the foreground. `HealthReader.shared` holds the canonical
///      reference; tests don't need a real store.
///
///   3. **Soft-fail to `.empty`** — if the user hasn't opted in, HealthKit
///      is unavailable on this device (iPad without iPhone), or any
///      individual sample-query throws, `weeklySummary()` returns
///      `WeeklySummary.empty`. The HomeView card then hides itself
///      (`isMeaningful == false`), the rest of HomeView stays intact,
///      and we never block startup on a HealthKit prompt.
///
/// HealthKit framework gating: the entire HealthKit-backed path is wrapped
/// in `#if canImport(HealthKit)` so the module still compiles on
/// platforms that don't expose the framework (e.g. macOS in an SPM
/// preview context). On those platforms the actor just returns `.empty`.
public actor HealthReader {
    public static let shared = HealthReader()

    #if canImport(HealthKit)
    private let store: HKHealthStore?

    /// The four read-types MIND requests. Kept as a computed property so
    /// the actor's init stays free of side effects — we materialise the
    /// HKObjectType instances lazily on first authorization call.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let active = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(active)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }
    #endif

    public init() {
        #if canImport(HealthKit)
        // HKHealthStore.isHealthDataAvailable() is the canonical check for
        // platforms that ship the framework but don't have the backing
        // database (e.g. iPad). Falling back to nil here lets every
        // public method short-circuit to .empty without conditionals.
        if HKHealthStore.isHealthDataAvailable() {
            self.store = HKHealthStore()
        } else {
            self.store = nil
        }
        #endif
    }

    // MARK: - Permission

    /// Requests HealthKit read authorization for the four metrics MIND
    /// surfaces in the weekly summary. Returns true if the system
    /// considers the request successful — note that Apple deliberately
    /// hides per-type grant decisions from apps (privacy), so a return
    /// of `true` only means "the user dismissed the sheet" and not
    /// "every type was granted". We rely on the actual sample queries
    /// to soft-fail per type, which is the only correct way to detect
    /// denial.
    public func requestAccess() async -> Bool {
        #if canImport(HealthKit)
        guard let store else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Weekly summary

    /// Returns the 7-day aggregation for the three metrics surfaced by
    /// the HomeView "Cette semaine" card.
    ///
    /// Soft-fails to `WeeklySummary.empty` when:
    /// - HealthKit is unavailable on this device
    /// - the user hasn't granted any of the requested permissions
    /// - any underlying query throws
    ///
    /// The window is computed relative to `now` so unit tests can pin a
    /// fixed reference date if they ever need to (none currently do —
    /// the value type is what's tested; this method is exercised
    /// end-to-end via the simulator screenshot).
    public func weeklySummary(now: Date = .now, calendar: Calendar = .current) async -> WeeklySummary {
        #if canImport(HealthKit)
        guard let store else { return .empty }

        let startOfToday = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: startOfToday
        ) else {
            return .empty
        }
        // End-of-window is the start of tomorrow so any sample logged
        // during the current day is included. Without this the user
        // sees zero steps if they open the app at 11am — a UX trap.
        guard let weekEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) else {
            return .empty
        }

        async let totalStepsTask = sumQuantity(
            identifier: .stepCount,
            unit: .count(),
            start: weekStart,
            end: weekEnd,
            store: store
        )
        async let activeMinutesTask = sumQuantity(
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: weekStart,
            end: weekEnd,
            store: store
        )
        async let sleepHoursTask = avgSleepHours(
            start: weekStart,
            end: weekEnd,
            store: store
        )

        let totalSteps = Int((await totalStepsTask) ?? 0)
        let activeMinutes = Int((await activeMinutesTask) ?? 0)
        let avgSleep = await sleepHoursTask

        return WeeklySummary(
            totalSteps: totalSteps,
            avgSleepHours: avgSleep,
            activeMinutes: activeMinutes
        )
        #else
        return .empty
        #endif
    }

    #if canImport(HealthKit)
    /// Sums a quantity-typed sample over `[start, end)`. Returns nil if
    /// HealthKit refuses the query (denied, restricted, or unknown
    /// identifier on this iOS major) so the caller can soft-fail.
    private func sumQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        store: HKHealthStore
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Mean nightly sleep duration in hours across the window. Sleep
    /// samples can overlap (multiple stages cover the same span), so we
    /// only count distinct "asleep" categories and dedupe by start/end
    /// pair before summing. Divided by 7 to get a nightly average.
    private func avgSleepHours(
        start: Date,
        end: Date,
        store: HKHealthStore
    ) async -> Double {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        // Only "asleep" states count. HealthKit returns "inBed" alongside,
        // which we deliberately ignore so the average reflects actual
        // sleep, not just time horizontally in bed.
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        // Dedupe by (start, end) so overlapping stage samples don't
        // inflate the total — Watch + iPhone often log the same span
        // from both sources.
        var seen = Set<String>()
        var totalSeconds: TimeInterval = 0
        for sample in samples where asleepValues.contains(sample.value) {
            let key = "\(sample.startDate.timeIntervalSince1970)-\(sample.endDate.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
            }
        }
        let hours = totalSeconds / 3_600
        return hours / 7
    }
    #endif
}
