//
//  ArtistListView.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/19/26.
//

import Combine
import SwiftUI

struct ArtistListView: View {
    @StateObject private var viewModel: LibraryListViewModel
    @State private var indexBarHeight: CGFloat = 0

    init(fetch: @escaping () async throws -> [BaseItemDto]) {
        _viewModel = StateObject(wrappedValue: LibraryListViewModel(fetch: fetch))
    }

    private var sections: [(letter: String, items: [BaseItemDto])] {
        var result: [(letter: String, items: [BaseItemDto])] = []
        for item in viewModel.items {
            let letter = ArtistListView.firstLetter(of: item.Name)
            if let lastIndex = result.indices.last, result[lastIndex].letter == letter {
                result[lastIndex].items.append(item)
            } else {
                result.append((letter, [item]))
            }
        }
        return result
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Artists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No Artists", systemImage: "music.mic")
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(sections, id: \.letter) { section in
                            Section(header: Text(section.letter)) {
                                ForEach(section.items) { item in
                                    LibraryNavigableRow(item: item)
                                }
                            }
                            .id(section.letter)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        indexBar(proxy: proxy)
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func indexBar(proxy: ScrollViewProxy) -> some View {
        let letters = sections.map { $0.letter }
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 14)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { indexBarHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, newValue in indexBarHeight = newValue }
            }
        )
        .padding(.trailing, 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !letters.isEmpty, indexBarHeight > 0 else { return }
                    let rowHeight = indexBarHeight / CGFloat(letters.count)
                    let index = min(max(Int(value.location.y / rowHeight), 0), letters.count - 1)
                    proxy.scrollTo(letters[index], anchor: .top)
                }
        )
    }

    private static func firstLetter(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        return first.isLetter ? String(first).uppercased() : "#"
    }
}
