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
        case loaded(metadata: Metadata)
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
            
        case .loaded(metadata: let metadata):
            if let title = metadata.title {
                Text(verbatim: title)
                    .fontWeight(.medium)
            }
            else {
                Text(verbatim: metadata.filename)
            }
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    @ViewBuilder
    var furtherMetadata: some View {
        switch mode {
        case .appIsLoading(message: _),
                .noMedia:
            EmptyView()
            
        case .loaded(metadata: let metadata):
            HStack {
                ForEach(metadata.allSecondary) { labelledMetadatum in
                    smallMetadatum(label: labelledMetadatum.label, value: labelledMetadatum.value)
                }
            }
        }
    }
    
    
    /// The artist of the loaded item, or an empty string while something loads
    func smallMetadatum(label: LocalizedStringKey, value: String) -> Text {
        switch mode {
        case .appIsLoading(message: _),
                .noMedia:
            Text("")
            
        case .loaded(metadata: _):
            Text("\(Text(label)) \(Text(verbatim: value).bold())")
                .fontWeight(.medium)
        }
    }
}



internal extension TitleBar {
    /// All the metadata that a title bar can display
    struct Metadata {
        let filename: String
        let title: String?
        
        let season: String?
        let episode: String?
        let track: String?
        let album: String?
        let creator: String?
        
        var allSecondary: [LabelledMetadatum] {
            [
                // Show:
                (label: "season",                           value: season),
                (label: "ep",                               value: episode),
                
                // Movie:
                // <none yet>
                
                // Music:
                (label: "track",                            value: track),
                (label: nil == creator ? "album:" : "from", value: album),
                
                // General:
                (label: "by",                               value: creator),
            ]
                .compactMap { (label: LocalizedStringKey, value: String?) in
                    if let value {
                        return LabelledMetadatum(label: label, value: value)
                    }
                    else {
                        return nil
                    }
                }
        }
    }
    
    
    
    /// One metadatum and its label to show in the UI
    struct LabelledMetadatum: Identifiable {
        
        var id: String { "\(label):\(value)" }
        
        /// The label to display in th UI, labelling ``value``
        let label: LocalizedStringKey
        
        /// The metadatum value to display in the UI, labelled by ``label``
        let value: String
    }
}



internal extension TitleBar.Metadata {
    init(in item: MediaItem) async {
        let filename = item
            .autoAccessSecurityScopedResourceUrl
            .deletingPathExtension()
            .lastPathComponent
            .nonEmptyOrNil
        ?? NSLocalizedString("Untitled", comment: "") // Would prefer to not use `NS` but I can't find a more modern API so......
        
        async let title =   try? item.metadata?.get(.title)
        async let season =  try? item.metadata?.get(.season)
        async let episode = try? item.metadata?.get(.episode)
        async let track =   try? item.metadata?.get(.trackNumber)
        async let album =   try? item.metadata?.get(.album)
        async let creator = try? item.metadata?.get(.creator)
        
        self.init(
            filename: filename,
            title: await title,
            
            
            season: await season,
            episode: await episode,
            
            track: await track?.description,
            album: await album,
            
            creator: await creator,
        )
    }
}
