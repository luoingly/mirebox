//
//  MedicationStore.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/25.
//

import Foundation
import Observation
import HealthKit

struct MedicationDoseEntry: Identifiable {
    let id: UUID
    let date: Date
    let logStatus: HKMedicationDoseEvent.LogStatus
    let doseQuantity: Double?
    let unitString: String
}

struct MedicationInfo: Identifiable {
    let id = UUID()
    let name: String
    let nickname: String?
    let isArchived: Bool
    let hasSchedule: Bool
    var doses: [MedicationDoseEntry]
}

@Observable
final class MedicationStore {
    enum State {
        case idle
        case loading
        case loaded([MedicationInfo])
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var isRefreshing = false
    var refreshErrorMessage: String?

    private let healthStore = HKHealthStore()

    /// 首次加载：请求健康授权后读取数据。
    /// 实测系统只在首次授权时弹出选药界面，之后调用会静默返回，
    /// 因此调整授权统一走「跳转健康 App」，这里只在初始入口调用。
    func requestAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("此设备不支持 HealthKit")
            return
        }
        state = .loading
        do {
            try await healthStore.requestPerObjectReadAuthorization(
                for: .userAnnotatedMedicationType(),
                predicate: nil
            )
            state = .loaded(try await fetchMedications())
        } catch let error as HKError where error.code == .errorUserCanceled {
            state = .failed("已取消授权")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 静默刷新：仅重新查询已授权的数据，不会触发任何系统弹窗。
    func refresh() async {
        guard !isRefreshing, case .loaded = state else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            state = .loaded(try await fetchMedications())
            refreshErrorMessage = nil
        } catch {
            refreshErrorMessage = error.localizedDescription
        }
    }

    func exportJSON(medications: [MedicationInfo], excludedStatuses: Set<HKMedicationDoseEvent.LogStatus>) async throws -> URL {
        let payload = ExportPayload(
            exportedAt: Date(),
            excludedStatuses: excludedStatuses.sorted { $0.sortOrder < $1.sortOrder }.map(\.jsonValue),
            medications: medications.map(\.exportModel)
        )
        return try await Task.detached(priority: .userInitiated) {
            try Self.writeExportFile(payload)
        }.value
    }

    private func fetchMedications() async throws -> [MedicationInfo] {
        var medications: [MedicationInfo] = []
        for annotated in try await HKUserAnnotatedMedicationQueryDescriptor().result(for: healthStore) {
            medications.append(MedicationInfo(
                name: annotated.medication.displayText,
                nickname: annotated.nickname,
                isArchived: annotated.isArchived,
                hasSchedule: annotated.hasSchedule,
                doses: try await loadDoses(for: annotated)
            ))
        }
        medications.sort {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return $0.name < $1.name
        }
        return medications
    }

    private func loadDoses(for annotated: HKUserAnnotatedMedication) async throws -> [MedicationDoseEntry] {
        let predicate = HKQuery.predicateForMedicationDoseEvent(
            medicationConceptIdentifier: annotated.medication.identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.medicationDoseEventType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
                ]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? []).compactMap { sample in
                        guard let event = sample as? HKMedicationDoseEvent else { return nil }
                        return MedicationDoseEntry(
                            id: event.uuid,
                            date: event.startDate,
                            logStatus: event.logStatus,
                            doseQuantity: event.doseQuantity,
                            unitString: event.unit.unitString
                        )
                    })
                }
            }
            healthStore.execute(query)
        }
    }

    private nonisolated static func writeExportFile(_ payload: ExportPayload) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(payload)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mirebox-服药导出-\(formatter.string(from: Date())).json")
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return url
    }
}

private extension MedicationInfo {
    var exportModel: ExportPayload.Medication {
        ExportPayload.Medication(
            name: name,
            nickname: nickname,
            isArchived: isArchived,
            hasSchedule: hasSchedule,
            doses: doses.map { dose in
                ExportPayload.Dose(
                    id: dose.id,
                    date: dose.date,
                    logStatus: dose.logStatus.jsonValue,
                    quantity: dose.doseQuantity,
                    unit: dose.doseQuantity == nil ? nil : dose.unitString
                )
            }
        )
    }
}

extension HKMedicationDoseEvent.LogStatus {
    var label: String {
        switch self {
        case .taken: "已服用"
        case .skipped: "已跳过"
        case .snoozed: "已推迟"
        case .notInteracted: "未处理"
        case .notificationNotSent: "通知未发出"
        case .notLogged: "已撤销"
        @unknown default: "未知状态"
        }
    }

    var jsonValue: String {
        switch self {
        case .taken: "taken"
        case .skipped: "skipped"
        case .snoozed: "snoozed"
        case .notInteracted: "notInteracted"
        case .notificationNotSent: "notificationNotSent"
        case .notLogged: "notLogged"
        @unknown default: "unknown"
        }
    }

    var sortOrder: Int {
        switch self {
        case .taken: 0
        case .skipped: 1
        case .snoozed: 2
        case .notInteracted: 3
        case .notificationNotSent: 4
        case .notLogged: 5
        @unknown default: 99
        }
    }
}

private nonisolated struct ExportPayload: Encodable {
    struct Dose: Encodable {
        let id: UUID
        let date: Date
        let logStatus: String
        let quantity: Double?
        let unit: String?
    }

    struct Medication: Encodable {
        let name: String
        let nickname: String?
        let isArchived: Bool
        let hasSchedule: Bool
        let doses: [Dose]
    }

    let app = "Mirebox"
    let tool = "medication-export"
    let version = 1
    let exportedAt: Date
    /// 被用户排除的服药状态；空数组表示包含全部状态。
    let excludedStatuses: [String]
    let medications: [Medication]
}
