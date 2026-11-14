# Claude Opus 5.5 • Issue #89 journal

## 2026-11-13 — plan: find and fix the actor reentrancy races

**Model:** Claude Opus 5.5
**Director:** Ky

### Where this came from

Issue #89: when the user drags the scrub bar, the transport buttons change between the disabled look and the normal look many times each second.

The cause is in `PlayerControls.performUserAction(_:)`. Each action starts a `Task` on the global actor `UserActionQueue`. The task sets `disabled` to `true`, waits for `onUserAction(action)`, and then sets `disabled` to `false`. The code expects that `UserActionQueue` runs 1 task to its end before it starts the next task. That is not correct. An actor is reentrant: while a task waits at an `await`, the actor can start a different task ([SE-0306 acceptance](https://forums.swift.org/t/accepted-with-modification-se-0306-actors/47662)). Thus the first task to complete sets `disabled` to `false` while other tasks are not complete.

Ky asked me to examine all of the codebase for the same type of error, and to make 1 patch that fixes all of them.

### What I looked for

I read each `actor`, each `@MainActor` type, and each `Task` in the app. `@MainActor` is also an actor, thus it is also reentrant. I looked for this pattern: code reads or sets a state, then waits at an `await`, then uses the state as if it did not change.

### What I found

These have the error:

1. `PlayerControls.performUserAction(_:)`. See above.
2. `PlayerSession.withLoadingMessage(_:perform:)` and `PlayerSession.loadIfNeeded()`. `withLoadingMessage` keeps the previous message, and puts it back when its work is complete. This is correct only if the operations complete in the opposite sequence from the sequence in which they started. Example: operation A starts, then operation B starts, then A completes. A puts back `nil`, thus the message of B goes away while B continues. Then B completes and puts back the message of A, and that message stays on the screen with no operation. `loadIfNeeded()` sets `loadingMessage` to `nil` when it completes, also if a different operation continues.
3. `NowPlayingStore.load()`. It reads the previous session (slow for a large queue), and then sets `queue`. If the user opens a folder or a playlist during that time, the restored queue replaces the queue of the user.
4. `NowPlayingStore.loadIntoQueue(_:andPlay:)` and `NowPlayingStore.replay(_:)`. Each finds its files, and then changes the queue. The library sheet stays open during this time. If the user taps playlist A (large) and then playlist B (small), B completes first, and then A replaces B. The last request of the user must win.
5. `ContentView`, the folder import. 2 imports can run at the same time. Each adds its entries to the queue when its load is complete. Thus a small folder that the user picked second can go into the queue before a large folder that the user picked first.
6. `ArtworkThumbnailCache.thumbnail(for:)`. It puts the file into `alreadyAttempted` before the read. If a second row asks for the same file during the read, the second row finds the file in `alreadyAttempted` and gets `nil` ("no art"). The second row then shows the placeholder for as long as it shows.
7. `PlaybackEngine.load(_:resumingAt:autoplay:)`, the restored position. When the item becomes ready, a `Task` moves the playhead to the restored position. That task runs later on the main actor. If a different item loads before the task runs, the task moves the playhead of the new item.
8. `ShowToastWithItemShim` (`ToastError + SwiftUI.swift`). When the item changes, a `Task` sets `showToast` to `true` after a cycle. If the item changes again (to `nil` or to a different item) before the task runs, the old task shows the toast anyway.

These do not have the error. I did not change them:

- `PlaybackEngine`, the duration task and the video track task. Each examines `playerItem === player.currentItem` after its `await`.
- `ArtworkThumbnailCache`, the check of `alreadyAttempted` and the insert. No `await` is between them, as the comment says.
- `PlaylistLibraryStore.autoGroupAlbums(from:)`. All of the `await`s are before it reads `savedPlaylists`. The read and the changes have no `await` between them.
- `MediaPlayer.SessionHolder.replaceQueue(with:autoplay:)`. `.task(id:)` cancels the old task, and the function examines `Task.isCancelled` after its `await`s.
- `PlayerSession.loadIfNeeded()`, the `hasRestored` check. No `await` is between the check and the change.

### Problems that are not reentrancy

- `AsyncMetadata` is `@unchecked Sendable`, and `lazySearch(for:)` changes the dictionary `__cache` with no lock. If 2 threads call it at the same time, that is a data race. Its comment says that the result is "benign", but 2 writes to a Swift `Dictionary` at the same time can damage memory. I did not change this, because it is a different type of error. I will tell Ky.
- The doc comment of `ArtworkLoadQueue` says that "a single serial actor also caps how much of this work happens at once". The actor does not stop other work while a task waits at an `await`. The image decode is synchronous and runs on the `ArtworkThumbnailCache` actor, thus decodes do occur 1 at a time. I did not change the comment. I will tell Ky.

### What I will change

1. `PlayerControls.swift`: remove `UserActionQueue`. Each new action waits for the action before it (a chain of `Task`s on the main actor). Replace the `disabled` `@State` with a count of the actions that are not complete. `disabled` becomes a computed property of that count.
2. `PlayerSession.swift`: keep a list of the messages of the operations that run. `loadingMessage` becomes a computed property: the message of the newest operation in the list. `loadIfNeeded()` uses `withLoadingMessage(_:perform:)`.
3. `NowPlayingStore.swift`: a count of the changes to `queue`. `load()` does not restore the queue if the count changed while it read the previous session. It does not restore the repeat mode if the user changed it in that time. An ID of the newest request from `replay(_:)` or `loadIntoQueue(_:andPlay:)`. Each request changes the queue only if it is still the newest request.
4. `ContentView.swift`: each folder import waits for the import before it, before it adds its entries to the queue. The folders still load at the same time.
5. `ArtworkThumbnailCache.swift`: keep the reads that run. A second request for the same file waits for that read.
6. `PlaybackEngine.swift`: the restored-position task examines `item === player.currentItem` before it moves the playhead. Apple's documentation says that `AVPlayerItem` is `Sendable` and `@MainActor` ([AVPlayerItem](https://developer.apple.com/documentation/avfoundation/avplayeritem)), thus the task can keep it.
7. `ToastError + SwiftUI.swift`: the task examines that the item did not change before it shows the toast.

The change to `PlayerControls.swift` does not stop the flash of issue #89 fully. The count goes to 0 between 2 drag updates, thus the buttons can still flash. Ky said that Ky has a preferred fix for the flash. Thus I only make the count correct, and I do not change what the buttons show during a scrub.

## 2026-11-13 — done: the patch for the reentrancy races

**Model:** Claude Opus 5.5
**Director:** Ky

I started from `952af4b` on `feature/1.0-UI`. Its tree is the same as the tree of `production` (`2c22501`). The patch changes the 7 files in the plan, and adds this journal. I made the changes that the plan describes, with no other changes.

### Results that Ky must know

- The transport buttons can still flash during a scrub (issue #89). The count of actions is now correct, but it goes to 0 between 2 drag updates. Ky's preferred fix for the flash is still necessary.
- With the chain, the actions go to `onUserAction` 1 at a time, in sequence. Before, they could go in a different sequence. In the harness (see below), the old code performed 6 actions in the sequence `[1, 3, 5, 0, 2, 4]`.
- When a newer request makes `replay(_:)` or `loadIntoQueue(_:andPlay:)` stop, the function returns with no change. `LibraryView` calls `dismiss()` after the function returns. Thus the sheet can close before the newer request is complete. I did not change this.
- When `replay(_:)` cannot find its file, it still stops an older request that did not complete.
- In `ArtworkThumbnailCache`, if the row that started a read goes away, the read stops, and a different row that waits for that read gets `nil`. That row shows the placeholder until it shows again.

### Checks

I have no Xcode and no Apple SDKs here. Thus I did not compile this patch against the real project, and I did not test it on a device. I did these checks with the Swift 6.2 toolchain for Linux:

1. `swiftc -parse` on the 7 changed files. All of them parse.
2. A harness that is not part of the patch. It compiles with `-swift-version 6 -warnings-as-errors`. For each fix, it runs the old pattern and the new pattern with the same timing:
    - Actions: the old pattern set `disabled` to `false` while an action was not complete. The new pattern performed the actions in sequence, with 1 action at a time, and it was disabled until all were complete.
    - Loading messages: A starts, B starts, A completes, B completes. The old pattern showed `nil` while B ran, and showed A after both were complete. The new pattern showed B while B ran, and `nil` after both were complete.
    - Playlists: tap A (slow), then B (fast). The old pattern put A in the queue. The new pattern put B in the queue.
    - Cover art: 2 rows ask for 1 file. The old pattern gave `nil` to the second row. The new pattern gave the art to both rows, and read the file 1 time. When the first row goes away, a later request reads the file again.

The harness uses stand-in types, not the real types. Thus it does not prove that the real files compile. These are the parts that I could not check:

- `Task<NativeImage?, Never>` in `ArtworkThumbnailCache` needs `NativeImage` to be `Sendable`. I think that it is, because `thumbnail(for:)` already returns it from the actor to the main actor.
- The restored-position task in `PlaybackEngine` keeps the `AVPlayerItem`. Apple's documentation says that `AVPlayerItem` is `Sendable`.
