//
//  WeightImportStore.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/30.
//

import Foundation
import Observation
import HealthKit

nonisolated struct WeightEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let time: Date
    let weightKg: Double
}

nonisolated struct ImportResult {
    let inserted: Int
    let skipped: Int
}

@Observable
final class WeightImportStore {
    enum State {
        case idle
        case loaded([WeightEntry], existing: Set<WeightEntry>)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var isImporting = false
    var importErrorMessage: String?
    var importResult: ImportResult?

    private let healthStore = HKHealthStore()
    private static let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!

    func beginImport() {
        isImporting = true
        importErrorMessage = nil
    }

    func endImport() {
        isImporting = false
    }

    func fail(_ message: String) {
        state = .failed(message)
    }

    func load(url: URL) async {
        do {
            try await requestAuthorization()
            let data = try Data(contentsOf: url)
            let entries = try Self.parse(data)
            guard !entries.isEmpty else {
                state = .failed("文件中没有体重记录")
                return
            }
            state = .loaded(entries, existing: try await queryExisting())
        } catch let error as HKError where error.code == .errorUserCanceled {
            state = .failed("已取消授权")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [Self.bodyMassType], read: [Self.bodyMassType])
    }

    /// 「只跳完全相同」：同时间戳且同体重才算重复。
    func toInsert(from entries: [WeightEntry], existing: Set<WeightEntry>) -> [WeightEntry] {
        entries.filter { entry in
            !existing.contains { $0.time == entry.time && $0.weightKg == entry.weightKg }
        }
    }

    func insert(_ entries: [WeightEntry]) async throws {
        let samples = entries.map { entry in
            HKQuantitySample(
                type: Self.bodyMassType,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: entry.weightKg),
                start: entry.time,
                end: entry.time
            )
        }
        try await healthStore.save(samples)
    }

    /// 导入成功后重新查询已存在记录，让预览里的「已存在」标记即时更新。
    func refreshExisting() async {
        guard case .loaded(let entries, _) = state else { return }
        state = .loaded(entries, existing: (try? await queryExisting()) ?? [])
    }

    private func queryExisting() async throws -> Set<WeightEntry> {
        let predicate = HKQuery.predicateForSamples(
            withStart: Date.distantPast,
            end: Date.distantFuture,
            options: [.strictStartDate, .strictEndDate]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.bodyMassType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: Set((samples ?? []).compactMap { sample in
                        guard let quantity = (sample as? HKQuantitySample)?.quantity else { return nil }
                        return WeightEntry(
                            time: sample.startDate,
                            weightKg: quantity.doubleValue(for: .gramUnit(with: .kilo))
                        )
                    }))
                }
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func parse(_ data: Data) throws -> [WeightEntry] {
        struct Raw: Decodable {
            let time: Double
            let weight: Double
        }
        let raws = try JSONDecoder().decode([Raw].self, from: data)
        return raws.map { WeightEntry(time: Date(timeIntervalSince1970: $0.time), weightKg: $0.weight) }
    }
}