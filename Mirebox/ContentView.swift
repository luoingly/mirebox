//
//  ContentView.swift
//  Mirebox
//
//  Created by 洛樱 on 2026/8/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List(Tool.all) { tool in
                NavigationLink(value: tool) {
                    HStack(spacing: 14) {
                        Image(systemName: tool.systemImage)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name)
                                .font(.headline)
                            Text(tool.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Mirebox")
            .navigationDestination(for: Tool.self) { $0.destination }
        }
    }
}

#Preview {
    ContentView()
}
