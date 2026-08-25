//
//  MedicationExportView.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/25.
//

import SwiftUI
import HealthKit

struct MedicationExportView: View {
    static let toolID = "medication-export"

    @Environment(\.scenePhase) private var scenePhase

    @State private var store = MedicationStore()
    @State private var excludedStatuses: Set<HKMedicationDoseEvent.LogStatus> = []
    @State private var exportFile: ExportFile?
    @State private var exportErrorMessage: String?
    @State private var isExporting = false

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                ContentUnavailableView {
                    Label("尚未加载", systemImage: "pills")
                } actions: {
                    Button("授权并加载数据") {
                        Task { await store.requestAndLoad() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .loading:
                ProgressView("正在读取药物数据…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法读取服药记录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await store.requestAndLoad() }
                    }
                }
            case .loaded(let medications):
                loadedView(medications)
            }
        }
        .navigationTitle("服药数据导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFile, onDismiss: { isExporting = false }) { file in
            ActivityView(items: [file.url])
        }
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert(
            "刷新失败",
            isPresented: Binding(
                get: { store.refreshErrorMessage != nil },
                set: { if !$0 { store.refreshErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.refreshErrorMessage ?? "")
        }
        .task {
            if case .idle = store.state {
                await store.requestAndLoad()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refresh() }
            }
        }
    }

    @ViewBuilder
    private func loadedView(_ medications: [MedicationInfo]) -> some View {
        let statusCounts = Self.statusCounts(in: medications)
        let filtered = medications.filtered(excluding: excludedStatuses)
        let filteredCount = filtered.reduce(0) { $0 + $1.doses.count }
        let totalCount = medications.reduce(0) { $0 + $1.doses.count }

        List {
            Section {
                ForEach(statusCounts, id: \.status) { item in
                    Toggle(isOn: Binding(
                        get: { !excludedStatuses.contains(item.status) },
                        set: { included in
                            if included {
                                excludedStatuses.remove(item.status)
                            } else {
                                excludedStatuses.insert(item.status)
                            }
                        }
                    )) {
                        HStack {
                            Text(item.status.label)
                            Spacer()
                            Text("\(item.count) 条")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.accentColor)
                }
            } header: {
                Text("包含哪些服药状态")
            } footer: {
                Text("筛选后 \(filteredCount) 条，共 \(totalCount) 条。")
            }

            Section {
                Button {
                    performExport(medications: filtered)
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在导出…")
                        } else {
                            Label("导出 JSON（\(filteredCount) 条）", systemImage: "square.and.arrow.up")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(filteredCount == 0 || isExporting)
            }

            Section {
                ForEach(filtered) { medication in
                    MedicationGroup(medication: medication)
                }
            }
        }
        .refreshable { await store.refresh() }
    }

    private func performExport(medications: [MedicationInfo]) {
        isExporting = true
        Task {
            do {
                let url = try await store.exportJSON(medications: medications, excludedStatuses: excludedStatuses)
                // 保持「正在导出…」状态，直到分享面板关闭时由 onDismiss 复位；
                // 分享面板初始化的等待时间远长于 JSON 生成本身。
                exportFile = ExportFile(url: url)
            } catch {
                isExporting = false
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private static func statusCounts(in medications: [MedicationInfo]) -> [(status: HKMedicationDoseEvent.LogStatus, count: Int)] {
        var counts: [HKMedicationDoseEvent.LogStatus: Int] = [:]
        for medication in medications {
            for dose in medication.doses {
                counts[dose.logStatus, default: 0] += 1
            }
        }
        return counts
            .map { (status: $0.key, count: $0.value) }
            .sorted { $0.status.sortOrder < $1.status.sortOrder }
    }
}

private extension Array where Element == MedicationInfo {
    func filtered(excluding statuses: Set<HKMedicationDoseEvent.LogStatus>) -> [MedicationInfo] {
        map { medication in
            var copy = medication
            copy.doses = medication.doses.filter { !statuses.contains($0.logStatus) }
            return copy
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

private struct MedicationGroup: View {
    let medication: MedicationInfo
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if medication.doses.isEmpty {
                Text("筛选后无记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(medication.doses) { dose in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.subheadline)
                            if let quantity = dose.doseQuantity {
                                Text("剂量：\(quantity) \(dose.unitString)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(dose.logStatus.label)
                            .font(.footnote.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                dose.logStatus == .taken
                                    ? Color.green.opacity(0.15)
                                    : Color.gray.opacity(0.15),
                                in: Capsule()
                            )
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(medication.nickname ?? medication.name)
                            .font(.headline)
                        if medication.isArchived {
                            badge("已归档")
                        }
                        if medication.hasSchedule {
                            badge("有日程")
                        }
                    }
                    if medication.nickname != nil {
                        Text(medication.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(medication.doses.count) 条")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        MedicationExportView()
    }
}
