//
//  Tool.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/25.
//

import SwiftUI

struct Tool: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let description: String

    @ViewBuilder
    var destination: some View {
        switch id {
        case MedicationExportView.toolID: MedicationExportView()
        case WeightImportView.toolID: WeightImportView()
        default: Text("未知工具")
        }
    }
}

extension Tool {
    static let all: [Tool] = [
        Tool(
            id: MedicationExportView.toolID,
            name: "服药数据导出",
            systemImage: "pills",
            description: "从「健康」读取药物与服药记录，按状态筛选后导出为 JSON"
        ),
        Tool(
            id: WeightImportView.toolID,
            name: "体重数据导入",
            systemImage: "scalemass",
            description: "解析体重历史 JSON，预览确认后写入「健康」"
        ),
    ]
}
