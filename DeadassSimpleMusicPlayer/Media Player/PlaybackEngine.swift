//
//  PlaybackEngine.swift
//  DeadassSimpleMusicPlayer
//
//  Created by Ky directing Claude Fable 5.1 on 2026-09-06.
//

import AVFoundation
import Combine
import MediaPlayer
import Observation

#if canImport(UIKit)
import UIKit
#endif

import CollectionTools
import CrossKitTypes
import SimpleLogging



/// Plays 1 media item, and tells the system that this item is the media that plays.
///
/// Use this type to show or control playback directly. For example, a transport bar can read `isPlaying` and call `play()`. To show the video or the cover art, use `CustomMediaPlayer`, which shows this engine.
///
/// The engine does the work that the system wants from a media app:
/// - It obeys the remote commands (Control Center, the Lock Screen, headphone buttons).
/// - It publishes the Now Playing info.
/// - It continues to play in the background.
/// - It shows cover art for audio.
///
/// This work continues when no view shows the engine.
///
/// The engine does not know about queues or about `RepeatMode`. When an item plays to its end, the engine sends `Event.finished(item:)` and stays at the end of the item. The owner of the queue selects the next item, and calls `load(_:resumingAt:autoplay:)`.
///
/// Read the state from the properties, and change the state with the methods. The properties change only when the `AVPlayer` changes. For example, `play()` does not set `isPlaying`: `isPlaying` becomes `true` when the player starts. Thus the properties always agree with the player.
///
/// Load items into only 1 engine at a time. The process has only 1 set of remote commands and only 1 Now Playing info. Thus 2 engines that load items replace the handlers and the info of each other.
@MainActor
@Observable
public final class PlaybackEngine {
    
    // MARK: Facts
    
    /// The item that is loaded, or `nil` when no item is loaded
    public private(set) var currentItem: MediaItem? = nil
    
    /// `true` while the player plays. This value changes when the player starts or stops, not when a method of this engine starts.
    public private(set) var isPlaying = false
    
    /// The playhead position in the loaded item, in seconds from the start of the item. This value changes at intervals during playback, and after each seek.
    public private(set) var currentTime: TimeInterval = 0
    
    /// The duration of the loaded item, in seconds. `nil` while the duration is not known, and when no item is loaded.
    public private(set) var duration: TimeInterval? = nil
    
    /// The cover art to show in the video area. `nil` when the loaded item has video, and when no item is loaded.
    public private(set) var artwork: NativeImage? = nil
    
    /// `true` when the loaded item has video.
    ///
    /// This value stays `true` until the engine finds that the item has no video. Thus cover art cannot show on top of the first frames of a video.
    public private(set) var hasVideoTrack = true
    
    /// Increases by 1 each time `AsyncMetadata` completes the search for a metadata key of the current item (for example, the title). A search completes when it finds the value, and also when it gives an error.
    ///
    /// `metadata(_:)` reads this value. Thus each SwiftUI `body` that calls `metadata(_:)` runs again when a search completes. Observation does not track the searches of `AsyncMetadata` directly.
    private var metadataRevision: UInt = 0
    
    
    // MARK: Machinery
    
    /// The player of this engine. Use it to show the video, for example in `Player`.
    ///
    /// To change playback, call the methods of this engine, not the methods of the player. The methods of the engine do more than the methods of the player. For example, `play()` starts an item again after the item played to its end.
    public let player = AVPlayer()
    
    /// The subscriptions that stay for the life of the engine
    @ObservationIgnored
    private var sinks: Set<AnyCancellable> = []
    
    /// Sends each metadata change of the loaded item to `metadataRevision`, to the Now Playing info, and to `artwork`. The engine replaces this subscription with each item.
    @ObservationIgnored
    private var metadataSink: AnyCancellable? = nil
    
    /// Sends `Event.finished(item:)` when the loaded `AVPlayerItem` plays to its end. The engine replaces this subscription with each item, and the release of the previous subscription stops it.
    @ObservationIgnored
    private var itemEndSink: AnyCancellable? = nil
    
    /// Writes the new playhead position to the Now Playing info after a seek in the loaded `AVPlayerItem`. The engine replaces this subscription with each item, and the release of the previous subscription stops it.
    ///
    /// The system calculates the playback position from the last position that the app wrote and from the rate. A seek changes the position but not the rate. Thus the system does not see a seek until the app writes the position again.
    @ObservationIgnored
    private var itemTimeJumpSink: AnyCancellable? = nil
    
    /// Waits until the status of the loaded `AVPlayerItem` is `.readyToPlay`, then moves the playhead to the position from the previous session. An item ignores or rejects a seek before that status.
    ///
    /// This uses `observe(_:options:changeHandler:)`, not the KVO publisher of Combine. With the publisher, the playhead did not go to the positions from the previous session in tests. This KVO pattern is the usual pattern for item status. The observation must stay in memory while it is necessary. The engine invalidates and replaces it with each item.
    @ObservationIgnored
    private var itemReadinessObservation: NSKeyValueObservation? = nil
    
    /// The token of the periodic time observer. `deinit` gives it back to the player.
    @ObservationIgnored
    private var periodicTimeObserverToken: Any? = nil
    
    /// `true` after this engine connected the remote commands to its player.
    ///
    /// The engine connects them when it first loads an item, not in `init`. Thus an engine that does not load an item does not replace the handlers of the engine that plays.
    @ObservationIgnored
    private var hasInstalledRemoteTransportControls = false
    
    /// The continuations of the open streams from `events()`. Each stream removes its continuation when the stream ends.
    @ObservationIgnored
    private var eventContinuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    
    
    /// Makes an engine with no item loaded.
    ///
    /// The engine connects to the remote commands when it first loads an item. Thus you can make an engine that you do not use, and that engine does not change the remote commands.
    public init() {
        installRateObserver()
        
        // Keeps `currentTime` correct, and sends `Event.positionChanged(item:seconds:)` for the loaded item. This is here, not in a function, so that nothing else can add a second observer. `deinit` removes this one
        periodicTimeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: .commonMedia),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            
            MainActor.assumeIsolated {
                self.currentTime = time.seconds
                
                if let currentItem = self.currentItem {
                    self.send(.positionChanged(item: currentItem, seconds: time.seconds))
                }
            }
        }
        
        installInterruptionObserver()
        
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
    
    
    /// Gives the periodic time observer back to the player, and ends the streams from `events()`.
    ///
    /// The player must get a `removeTimeObserver(_:)` call for each periodic time observer. Without that call, the result is undefined.
    isolated deinit {
        if let periodicTimeObserverToken {
            player.removeTimeObserver(periodicTimeObserverToken)
        }
        
        eventContinuations.values.forEach { $0.finish() }
    }
}



// MARK: - Events

public extension PlaybackEngine {
    
    /// An occurrence during playback that the engine cannot make a decision about.
    ///
    /// Read these events from `events()`. An event can come after a different item loaded. Thus each event about an item names that item. Compare that item with your current item before you use the event.
    enum Event: Sendable {
        
        /// The item played to its end. The engine stays at the end of the item, and does not play again until something tells it to.
        case finished(item: MediaItem)
        
        /// The playhead of the item is at a new position, in seconds from the start of the item.
        ///
        /// The engine sends this event at intervals during playback, after each seek, and when playback starts or stops. While playback is paused, the engine does not send it at intervals.
        case positionChanged(item: MediaItem, seconds: TimeInterval)
        
        /// Playback stopped. The cause can be the user, a remote command, an interruption, or the end of the item.
        case paused
    }
    
    
    
    /// Returns a new stream of the events that occur after this call.
    ///
    /// Each call returns a different stream, and each stream gets all of the events. Thus more than 1 listener can read the events at the same time. To stop a stream, cancel the task that reads it. The stream ends when the engine is released.
    ///
    /// ```swift
    /// Task {
    ///     for await event in engine.events() {
    ///         // Respond to `event` here
    ///     }
    /// }
    /// ```
    func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        let subscriberId = UUID()
        
        eventContinuations[subscriberId] = continuation
        
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            
            Task { @MainActor in
                self.eventContinuations[subscriberId] = nil
            }
        }
        
        return stream
    }
}



private extension PlaybackEngine {
    
    /// Gives `event` to each open stream from `events()`
    func send(_ event: Event) {
        eventContinuations.values.forEach { $0.yield(event) }
    }
}



// MARK: - Commands

public extension PlaybackEngine {
    
    /// Loads an item, and replaces the item that was loaded before.
    ///
    /// The engine first removes all values that came from the previous item. Thus no value from the previous item can show in the Now Playing info of this item.
    ///
    /// - Parameters:
    ///   - item:     The item to load, or `nil` to unload the player
    ///   - seconds:  The position to start from, in seconds. The engine moves the playhead to this position when the status of the item is `.readyToPlay`. `nil` starts at the start of the item.
    ///   - autoplay: `true` starts playback immediately. `false` loads the item paused.
    func load(_ item: MediaItem?, resumingAt seconds: TimeInterval? = nil, autoplay: Bool) {
        currentItem = item
        duration = nil // The previous track's duration must not survive into this one's Now Playing info
        artwork = nil // Likewise the previous track's cover art
        hasVideoTrack = true // Assumed until proven otherwise, so art can't flash over a video's first frames
        currentTime = 0
        
        itemEndSink = nil
        itemTimeJumpSink = nil
        metadataSink = nil
        itemReadinessObservation?.invalidate()
        itemReadinessObservation = nil
        
        guard let item else {
            player.replaceCurrentItem(with: nil)
            publishNowPlayingInfo()
            UIApplication.shared.endReceivingRemoteControlEvents()
            return
        }
        
        // Connected at the first load (not at init) because this is the moment this engine first publishes Now Playing info, so the engine that shows the info is the engine that answers its commands. An engine which never loads anything never takes the commands away from the one that does.
        if false == hasInstalledRemoteTransportControls {
            installRemoteTransportControls()
        }
        
        let playerItem = AVPlayerItem(item)
        
        // Subscribed per-item (with the item as the notification's object) so finishing can never be misattributed to whatever item happens to be current when the notification lands
        itemEndSink = NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
            .map { _ in } // Reduced to Void before crossing queues: the payload isn't needed, and Void is trivially Sendable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                send(.finished(item: item))
            }
        
        // Scoped to this item for the same reason, so a seek is never attributed to a track which has since been replaced
        itemTimeJumpSink = NotificationCenter.default
            .publisher(for: AVPlayerItem.timeJumpedNotification, object: playerItem)
            .map { _ in }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                currentTime = player.currentTime().seconds
                updateNowPlayingPlaybackPosition()
            }
        
        // Each completed search for a metadata key refreshes both what views can read and what the system shows
        metadataSink = item.metadata?.onMetadataDidUpdate()
            .sink { [weak self] in
                guard let self else { return }
                metadataRevision &+= 1
                publishNowPlayingInfo()
                refreshArtwork()
                log(info: "Metadata updated")
            }
        
        player.replaceCurrentItem(with: playerItem)
        
        if let seconds {
            log(info: "Holding a restored playback position of \(seconds)s until the item becomes ready")
            
            let targetTime = CMTime(seconds: seconds, preferredTimescale: .commonMedia)
            
            itemReadinessObservation = playerItem.observe(\.status, options: [.initial, .new]) { [player] item, _ in
                guard .readyToPlay == item.status else { return }
                
                Task { @MainActor in
                    log(info: "Item is ready; applying the restored playback position")
                    let seekFinished = await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    log(info: "Restored-position seek \(seekFinished ? "completed" : "was interrupted by another seek")")
                }
            }
        }
        else {
            player.seek(to: .zero)
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        }
        catch {
            log(error: error)
        }
        
        if autoplay {
            player.play()
        }
        
        // Published immediately with whatever's known so far, so remote controls never sit on the previous track's info (or their own "Unknown Artist" placeholders) while metadata resolves. Each metadata update pings this again to fill in the rest.
        publishNowPlayingInfo()
        
        // Loaded from the asset rather than read from `AVPlayerItem.duration`, which reports `.indefinite` until the item is ready. Publishing an indefinite duration is what gives remote controls a track with no progress bar.
        Task { [self] in
            guard let duration = try? await playerItem.asset.load(.duration),
                  duration.seconds.isFinite,
                  playerItem === player.currentItem // The queue may have moved on while this loaded
            else { return }
            
            self.duration = duration.seconds
            publishNowPlayingInfo()
        }
        
        // Cover art belongs only where video doesn't, so the asset's tracks decide whether art is allowed through at all
        Task { [self] in
            let videoTracks = (try? await playerItem.asset.loadTracks(withMediaType: .video)) ?? []
            
            guard playerItem === player.currentItem else { return }
            
            hasVideoTrack = videoTracks.isNotEmpty
            refreshArtwork()
        }
    }
    
    
    /// Starts playback of the loaded item. If the item played to its end, playback starts again at the start of the item.
    ///
    /// This method has no effect when no item is loaded.
    func play() {
        player.playOrRestart()
    }
    
    
    /// Pauses playback. The playhead stays where it is.
    func pause() {
        player.pause()
    }
    
    
    /// Pauses playback if the item plays, and starts playback if the item is paused. Headphone buttons and many car controls send this command.
    func togglePlayPause() {
        if player.isPaused {
            player.playOrRestart()
        }
        else {
            player.pause()
        }
    }
    
    
    /// Moves the playhead. The engine then writes the new position to the Now Playing info.
    /// - Parameter seconds: The new position, in seconds from the start of the loaded item
    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: .commonMedia))
    }
    
    
    /// Moves the playhead to the start of the loaded item, and starts playback
    func replayFromStart() {
        player.seek(to: .zero)
        player.play()
    }
}



// MARK: - Metadata

public extension PlaybackEngine {
    
    /// Returns the result of the search for `key` in the metadata of the loaded item.
    ///
    /// When a view calls this function from its `body`, SwiftUI shows that view again when the search finds a value.
    ///
    /// - Parameter key: The metadata to find
    /// - Returns: The state of the search, and the value when the search found one. `nil` when no item is loaded, and when the metadata of the item could not be read.
    func metadata<Value>(_ key: AsyncMetadataKey<Value>) -> MetadataSearchResult<Value>? {
        access(keyPath: \.metadataRevision) // Registers the Observation dependency; see the property's doc
        return currentItem?.metadata?.get(key)
    }
}



// MARK: - Observing the player

private extension PlaybackEngine {
    
    /// Keeps `isPlaying` the same as the state of the player, and does the work that must occur each time playback starts or stops.
    ///
    /// This observer is the only code that writes `isPlaying`. The work occurs here for all causes of the change. The cause can be a tap in the app, a remote command, an interruption, or the end of the item.
    func installRateObserver() {
        player.publisher(for: \.rate)
            .sink { [weak self] _ in
                guard let self else { return }
                
                let wasPlaying = isPlaying
                isPlaying = player.isPlaying
                
                guard wasPlaying != isPlaying else { return }
                
                if isPlaying {
                    UIApplication.shared.beginReceivingRemoteControlEvents()
                }
                else {
                    send(.paused)
                }
                
                // The system (Control Center, the Lock Screen) calculates the elapsed time from the rate in the Now Playing info.
                // Thus, write the new rate there each time playback starts or stops.
                // If not, the remote progress bar continues to move while playback is paused.
                updateNowPlayingPlaybackPosition()
            }
            .store(in: &sinks)
    }
    
    
    /// In debug builds, records each audio session interruption (for example, a phone call or an alarm) in the log.
    ///
    /// This function does not change playback. When an interruption starts, the system pauses the player, and the rate observer sets `isPlaying` to `false`. When the interruption ends, playback stays paused.
    func installInterruptionObserver() {
        #if DEBUG
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .sink { notification in
                guard let interruptTypeNum = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
                      let interruptType =  AVAudioSession.InterruptionType.init(rawValue: interruptTypeNum.uintValue)
                else { return }
                
                switch interruptType {
                case .began:
                    log(verbose: "Audio session interruption began")
                    
                case .ended:
                    log(verbose: "Audio session interruption ended")
                    
                @unknown default:
                    log(verbose: "Audio session interruption of an unknown type: \(interruptType)")
                }
            }
            .store(in: &sinks)
        #endif
    }
    
    
    /// Sets `artwork` to the cover art of the loaded item, or to the placeholder art when the item has no cover art. Sets `artwork` to `nil` when the item has video.
    ///
    /// The placeholder makes sure that the player area always shows an image that the app selected. It also lets `Player` make that area not transparent. Thus the default audio image of `AVPlayerViewController` does not show.
    ///
    /// Call this function when the video-track check is complete and when the metadata changes. These 2 events can occur in a different sequence each time.
    func refreshArtwork() {
        guard !hasVideoTrack else {
            artwork = nil // Video fills this region itself; nothing should be drawn over it
            return
        }
        
        artwork = (try? metadata(.image)?.value)
            ?? .placeholderArt
    }
}



// MARK: - Control Center, Live Activites, Dynamic Island, etc.

private extension PlaybackEngine {
    
    /// Connects the remote commands (Control Center, the Lock Screen, headphone buttons, car controls) to the player.
    ///
    /// The process has only 1 command center. Thus this function first removes all handlers, and the remote commands then control the player of the engine that called this function last.
    func installRemoteTransportControls() {
        hasInstalledRemoteTransportControls = true
        
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Cleared first: the command center is a long-lived shared singleton, so re-running this would otherwise stack duplicate handlers on top of the old ones
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        // These capture `player` rather than this engine's `isPlaying`, because the handlers outlive any given value of that fact, and because driving the player directly lets the rate observer sync `isPlaying` back the same way an in-app tap would
        
        // Add handler for Play Command
        commandCenter.playCommand.addTarget { [player] _ in
            guard player.isPaused else { return .commandFailed }
            player.playOrRestart()
            return .success
        }
        
        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [player] _ in
            guard player.isPlaying else { return .commandFailed }
            player.pause()
            return .success
        }
        
        // Add handler for Toggle Play/Pause Command, which is what headphone buttons and many car head units send instead of the discrete commands above
        commandCenter.togglePlayPauseCommand.addTarget { [player] _ in
            if player.isPaused {
                player.playOrRestart()
            }
            else {
                player.pause()
            }
            return .success
        }
        
        // Add handler for scrubbing from Control Center, the Lock Screen, or the Dynamic Island. This app publishes its own Now Playing info (see `Player.updatesNowPlayingInfoCenter`), so it owns the commands that go with it — without this, the remote scrubber would move and then snap back. The resulting seek fires `timeJumpedNotification`, which republishes the new position.
        commandCenter.changePlaybackPositionCommand.addTarget { [player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            
            player.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: .commonMedia))
            return .success
        }
    }
    
    
    /// Writes the Now Playing info for the loaded item. When no item is loaded, this function removes the Now Playing info.
    ///
    /// Call this function when the loaded item or its metadata changes. When only the playback position or the rate changes, call `updateNowPlayingPlaybackPosition()`. The system limits how frequently an app can change the Now Playing metadata.
    func publishNowPlayingInfo() {
        guard let currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        // Built fresh rather than read-modify-written from the existing dictionary: inheriting the previous track's entries means any key *this* track lacks silently keeps showing the last track's value
        var nowPlayingInfo = [String : Any]()
        
        if let title = ((try? metadata(.title)?.value) ?? nil)
            ?? currentItem.autoAccessSecurityScopedResourceUrl.deletingPathExtension().lastPathComponent.nonEmptyOrNil
        {
            nowPlayingInfo[MPMediaItemPropertyTitle] = title
        }
        
        if let artist = (try? metadata(.creator)?.value) ?? nil {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        if let album = (try? metadata(.album)?.value) ?? nil {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        
        if let trackNumber = (try? metadata(.trackNumber)?.value) ?? nil {
            nowPlayingInfo[MPMediaItemPropertyAlbumTrackNumber] = trackNumber
        }
        
        // Unlike the player, this falls back to the placeholder even for video: Control Center and the Lock Screen have no video to show in that slot, so the app's own art beats an empty square
        if let image = ((try? metadata(.image)?.value) ?? nil) ?? .placeholderArt {
            // `@Sendable` is load-bearing, per Apple DTS: MPMediaItemArtwork retains this closure and calls it on an arbitrary thread, so without it the closure inherits this engine's MainActor isolation and traps when the system asks for the image.
            nowPlayingInfo[MPMediaItemPropertyArtwork] =
                MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        }
        
        if let duration {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        addPlaybackPositionInfo(to: &nowPlayingInfo)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    
    /// Writes only the playback position and the rate to the Now Playing info. The other values in the Now Playing info do not change.
    ///
    /// Call this function after a seek, and when playback starts or stops. When the loaded item or its metadata changes, call `publishNowPlayingInfo()`. The system limits how frequently an app can change the Now Playing metadata.
    func updateNowPlayingPlaybackPosition() {
        // Over the throttle limit, the system drops the write and logs "Application exceeded audio metadata throttle limit". The user sees the title and the artist blink out and back while scrubbing from Control Center. Rewriting only the position keys keeps this path cheap.
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return // Nothing published yet, so there's no position to correct — a full publish will happen when media loads
        }
        
        addPlaybackPositionInfo(to: &nowPlayingInfo)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    
    /// Adds the playback position and the rate to `nowPlayingInfo`.
    ///
    /// The 2 functions `publishNowPlayingInfo()` and `updateNowPlayingPlaybackPosition()` use this function. Thus they always write the same position values.
    func addPlaybackPositionInfo(to nowPlayingInfo: inout [String : Any]) {
        // The system extrapolates elapsed time from the last-published value and the rate, so these two are what make a progress bar appear and move at all. Published on load, on play/pause, and on seek — deliberately *not* on a timer, since frequent writes get throttled during long background playback and go stale without warning.
        let elapsed = player.currentTime().seconds
        if elapsed.isFinite {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        else {
            nowPlayingInfo.removeValue(forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
    }
}



// MARK: - Conveniences

public extension PlaybackEngine {
    var currentTrackPosition: PlayheadPosition? {
        guard let duration else { return nil }
        return PlayheadPosition(current: currentTime, total: duration)
    }
}



// MARK: - Constants

private extension CMTimeScale {
    
    /// The timescale for times in this engine: 600 time units in each second.
    ///
    /// 600 divided by each of the frame rates 24, 25, 30 & 60 fps gives an integer. Thus each frame time at these rates is an integer number of units.
    static let commonMedia: Self = 600
}
