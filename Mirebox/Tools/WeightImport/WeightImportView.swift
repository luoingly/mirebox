//
//  WeightImportView.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/30.
//

import SwiftUI
import UniformTypeIdentifiers

struct WeightImportView: View {
    static let toolID = "weight-import"

    @State private var store = WeightImportStore()
    @State private var isFileImporterPresented = false

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                ContentUnavailableView {
                    Label("尚未选择文件", systemImage: "scalemass")
                } description: {
                    Text("选择 weight_history.json（结构为 [{\"time\": 秒, \"weight\": 千克}]）")
                } actions: {
                    Button("选择文件") {
                        isFileImporterPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法读取文件", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重新选择") {
                        isFileImporterPresented = true
                    }
                }
            case .loaded(let entries, let existing):
                loadedView(entries, existing: existing)
            }
        }
        .navigationTitle("体重导入")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                Task {
                    await store.load(url: url)
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let error):
                store.fail(error.localizedDescription)
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { store.importErrorMessage != nil },
            set: { if !$0 { store.importErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.importErrorMessage ?? "")
        }
        .alert("导入完成", isPresented: Binding(
            get: { store.importResult != nil },
            set: { if !$0 { store.importResult = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            if let result = store.importResult {
                Text("已导入 \(result.inserted) 条，跳过 \(result.skipped) 条。")
            }
        }
    }

    @ViewBuilder
    private func loadedView(_ entries: [WeightEntry], existing: Set<WeightEntry>) -> some View {
        let toInsert = store.toInsert(from: entries, existing: existing)
        let sorted = entries.sorted { $0.time < $1.time }

        List {
            Section {
                HStack {
                    Text("共 \(entries.count) 条")
                    Spacer()
                    Text("\(sorted.first?.time.formatted(date: .abbreviated, time: .omitted) ?? "") ~ \(sorted.last?.time.formatted(date: .abbreviated, time: .omitted) ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("新增 \(toInsert.count) 条")
                    Spacer()
                    Text("跳过 \(entries.count - toInsert.count) 条")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    performImport(entries: toInsert, total: entries.count)
                } label: {
                    HStack {
                        if store.isImporting {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在导入…")
                        } else {
                            Label("导入 \(toInsert.count) 条到健康", systemImage: "arrow.down.heart")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(toInsert.isEmpty || store.isImporting)
            }

            Section("预览") {
                ForEach(sorted) { entry in
                    HStack {
                        Text(entry.time, format: .dateTime.year().month().day().hour().minute())
                            .font(.subheadline)
                        Spacer()
                        if existing.contains(where: { $0.time == entry.time && $0.weightKg == entry.weightKg }) {
                            Text("已存在")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(entry.weightKg, specifier: "%.1f") kg")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }

    private func performImport(entries: [WeightEntry], total: Int) {
        store.beginImport()
        Task {
            defer { store.endImport() }
            do {
                try await store.requestAuthorization()
                try await store.insert(entries)
                await store.refreshExisting()
                store.importResult = ImportResult(inserted: entries.count, skipped: total - entries.count)
            } catch {
                store.importErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        WeightImportView()
    }
}