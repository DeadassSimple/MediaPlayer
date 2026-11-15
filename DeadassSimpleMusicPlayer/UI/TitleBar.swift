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
    
    let expansion: Binding<Expansion>
    
    /// The title and the artist of the loaded item
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(.primary) // not strictly necessary, but I wanted to explicitly call out the relationship to the next Text down
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
//                .border(.red)
            
            furtherMetadata
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
    
    
    
    /// The title bar can request that content nearby it expand or collapse. This is how that state is represented
    enum Expansion {
        
        /// The nearby content is collapsed (can be gone, minimised, etc.)
        case collapsed
        
        /// The nearby content is expanded (can be previewed, fullscreen, etc.)
        case expanded
    }
}



// MARK: - Metadata

private extension TitleBar {
    
    /// The title of the loaded item. While something loads, this view shows `loadingMessage` and not the title.
    @ViewBuilder
    var title: some View {
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
            switch currentItem.metadata?.get(.title) {
            case .notStarted,
                    .loading:
                Text("…")
                
            case .success(let value):
                Text(verbatim: value)
                    .fontWeight(.medium)
                
            case .failure(_),
                    .none:
                // If we ever add more possible error cases than NotFound, this needs updating
                if let filename = currentItem.autoAccessSecurityScopedResourceUrl.deletingPathExtension().lastPathComponent.nonEmptyOrNil {
                    Text(verbatim: filename)
                }
                else {
                    Text("Untitled")
                }
            }
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    var furtherMetadata: some View {
        switch mode {
        case .appIsLoading(message: _),
                .noMedia:
            Text("")
            
        case .loaded(currentItem: let currentItem):
            HStack {
                ForEach(currentItem.presentedMetadata) { labelledMetadata in
                    smallMetadata(label: labelledMetadata.label, value: labelledMetadata.metadata)
                }
            }
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    func smallMetadata(label: LocalizedStringKey, value: AsyncMetadataKey<String>) -> Text {
        switch mode {
        case .appIsLoading(message: _),
                .noMedia:
            Text("")
            
        case .loaded(currentItem: let currentItem):
            switch currentItem.metadata?.get(value) {
            case .notStarted,
                    .loading:
                Text("⋯")
                
            case .success(let value):
                Text("\(value) \(Text(verbatim: value).bold())")
                    .fontWeight(.medium)
                
            case .failure(_),
                    .none:
                Text("")
            }
        }
    }
}
