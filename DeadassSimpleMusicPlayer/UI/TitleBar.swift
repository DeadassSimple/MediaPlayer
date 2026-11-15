//
//  TitleBar.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky on 2026-11-14.
//


import SwiftUI
import CollectionTools
import ConcurrencyTools
import SimpleLogging



struct TitleBar: View {
    
    let mode: Mode
    
    /// The title and the artist of the loaded item
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleView
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(.primary) // not strictly necessary, but I wanted to explicitly call out the relationship to the next Text down
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
//                .border(.red)
            
            Text(creatorText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize()
//                .border(.red)
            
            Spacer(minLength: 0)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
//        .border(.blue)
    }
    
    
    
    enum Mode {
        case appIsLoading(message: LocalizedStringKey)
        case noMedia
        case loaded(currentItem: MediaItem)
    }
}



// MARK: - Metadata

private extension TitleBar {
    
    /// The title of the loaded item. While something loads, this view shows `loadingMessage` and not the title.
    @ViewBuilder
    var titleView: some View {
        switch mode {
        case .appIsLoading(message: let loadingMessage):
            HStack {
                ProgressView()
                Text(loadingMessage)
                    .foregroundStyle(.secondary)
            }
            
        case .noMedia:
            Text("Pick something to play :3")
            
        case .loaded(currentItem: let currentItem):
            Text({
                switch currentItem.metadata?.get(.title) {
                case .notStarted: "…"
                case .loading: "⋯"
                case .success(let value): "\(value)"
                case .failure(_),
                        .none:
                    // If we ever add more possible error cases than NotFound, this needs updating
                    (currentItem.autoAccessSecurityScopedResourceUrl.deletingPathExtension().lastPathComponent.nonEmptyOrNil).map { "\($0)" } ?? "Untitled"
                }
            }())
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    var creatorText: LocalizedStringKey {
        switch mode {
        case .appIsLoading(message: _),
                .noMedia:
            return ""
            
        case .loaded(currentItem: let currentItem):
            
            return switch currentItem.metadata?.get(.creator) {
            case .notStarted,
                    .loading:
                "⋯"
                
            case .success(let value):
                "\(value)"
                
            case .failure(_),
                    .none:
                ""
            }
        }
    }
}
