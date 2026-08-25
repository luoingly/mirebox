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
    ]
}
