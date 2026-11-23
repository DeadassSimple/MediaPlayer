# Claude Sonnet 5.5 • Issue #91 journal

## 2026-11-21: diagnosis of the crash in `AsyncMetadata.lazySearch(for:)`

**Model:** Claude Sonnet 5.5
**Director:** Ky

I wrote the first two sections from a summary of the session, because I could not read the first turns again. I did not make sure of the dates of those turns. Thus I put them under the date of today.

### Where this came from

Ky sent a crash. The exception was `-[NSTaggedPointerString count]: unrecognized selector sent to instance 0x8000000000000000`. It occurred at `__cache[key.id] = search` in `AsyncMetadata.lazySearch(for:)`.

Ky first said that it occurred at the end of a playlist. After that, Ky said that it occurred when one item in the middle of a playlist ended.

The journal of issue #89 already noted this race and said that its author did not change it.

### What I thought the cause was

I thought that two threads change the `Dictionary` `__cache` at the same time. `TitleBar.Metadata.init(in:)` starts 6 `async let` lookups on 1 `AsyncMetadata`. Each lookup asks for a different key. Each item change builds a new `TitleBar.Metadata`.

I read the code to find this. I did not see the race run.

### Dead ends

1. The previous doc comment of `lazySearch(for:)` said to use `Mutex.run { ... }` from ConcurrencyTools. I planned to do that. It cannot work. In ConcurrencyTools (version 0.3.1, revision `c67b236c567751024e6dbf5659dc0b7f9dcf3583`), `Mutex` is an `actor` and `run` is `async`. `lazySearch(for:)` and the sync `get(_:)` are not `async`.
2. `Synchronization.Mutex` from the standard library. In a file that imports ConcurrencyTools, its name clashes with `Mutex` from ConcurrencyTools. I did not use it.

I chose `OSAllocatedUnfairLock` from `import os`. From my memory of Apple's documentation, it is available from iOS 16 or macOS 13. I did not compare this with the SDK.

## 2026-11-21: the lldb output and the standard library

**Model:** Claude Opus 5.5
**Director:** Ky

Ky sent the lldb output of the stop. `__cache` had 8 keys: `publishedDate`, `image`, `album`, `title`, `discNumber`, `episode`, `trackNumber`, and `creator`. The key `season` was not there, and `key.id` was `season`.

I read `DictionaryVariant.swift` on the `main` branch of `swiftlang/swift`. Its `_modify` accessor sets `self = .init(dummy: ())` while a change is in progress. That placeholder is `_BridgeStorage(taggedPayload: 0)` on 64-bit platforms. `setValue(_:forKey:)` checks `isNative` and then reads `cocoa.count`. This agrees with the exception.

I checked the `main` branch. I did not examine the runtime of Xcode 27 or iOS 27.

Ky tried Thread Sanitizer. It stopped the Swift compiler. Thus I could not confirm the race with a tool. Ky and I agreed to write a test that starts many lookups at the same time.

I also checked the Xcode project. It has no test target.

Mistake of mine: I said that the iOS 16 target compiles the folder `Media processing/`. That was misleading. That target does not have the ConcurrencyTools product. I do not know that it builds this file, and I did not examine it.

## 2026-11-21: the change

**Model:** Claude Sonnet 5.5
**Director:** Ky

I started from `ab9ba5b` on `feature/1.0-UI`. I filed issue #91 for this crash.

### What I changed

1. `AsyncMetadata.swift`: `__cache` is an `OSAllocatedUnfairLock` that holds the dictionary. It was a `var`. `lazySearch(for:)` reads and inserts in one `withLock` block.
2. Only the caller that inserted a search starts the `Task` that observes it. Before, each caller that missed the cache started a task. Each key sends exactly 1 ping on `onMetadataDidUpdate()`.
3. I replaced 2 comments that said that the race is benign. The new comments say that the lock guards `__cache`.
4. I added `DeadassSimpleMusicPlayerTests/AsyncMetadata concurrency Tests.swift` with 3 tests.

Making a `CachedSearch` only stores a closure (I read `ThrowingAsyncLazy.init(get:)`). Thus it is safe to make one while the lock is held.

### Why I checked the tag bit

In an earlier turn, I said from memory that the exception address `0x8000000000000000` is the placeholder of the `Dictionary`. I searched the standard library for the constant, and the search found nothing. Today I read `Builtin.swift` and `System.h` on the `main` branch.

- `_bridgeObject(taggingPayload:)` sets `_bridgeObjectTaggedPointerBits`.
- `SWIFT_ABI_DEFAULT_BRIDGEOBJECT_TAG_64` is `0x8000000000000000`. The file has no other definition of this tag.

I did not examine how `_swift_BridgeObject_TaggedPointerBits` takes its value from this macro. The tag bit agrees with the exception address. This is an examination of the source and not a test of the app.

### Dead ends in this step

- I made a fork with `mcp__github__fork_repository`. It failed with 403 `Resource not accessible by integration`. Thus I could not make a pull request. Ky's rule is that I never push to the repository of Ky or make a branch there. I made the commit in a local clone and I give it to Ky as a patch.
- In the first text of issue #91, I wrote a device name and a list of stack frames. I could not make sure that they are correct. I removed them from the issue.

### Not done

- I have no Xcode and no Apple SDKs here. I did not compile the change and I did not run the tests. I did not test on a device.
- `OSAllocatedUnfairLock.withLock` can have rules that the body is `@Sendable` and the result is `Sendable`. I assume that `CachedSearch`, `Key<Value>`, and `AsyncMetadataKeyId` are `Sendable`. The compiler can say that I am wrong.
- `__cache` changed from a `var` to a `let`. The `@Observable` macro does not track a `let`. The code that uses `AsyncMetadata` listens to `onMetadataDidUpdate()`. I did not examine each user.
- The module name `Dead_Simple_Media_Player` in the test file comes from the target name `Dead-Simple Media Player`. I did not make sure of it with a build.
- The project has no test target. Ky must add a Unit Testing Bundle in Xcode and point it at the folder `DeadassSimpleMusicPlayerTests`.
- I do not know that the first 2 tests stop the process with the previous code. A crash is not certain on each run. The third test uses timing (a wait of 5 seconds at most, and a wait of 200 milliseconds).
- The tests assume that `load(.metadata)` of an empty `AVMutableComposition` gives an empty array.
- The doc comment of `lazySearch(for:)` has an older sentence about an `onDidChange` callback that no longer agrees with the code. I did not change it.
- `CONTRIBUTING.md` says that pull requests go to `nightly`. The code that starts the race (`TitleBar`) is on `feature/1.0-UI` only. The `AsyncMetadata` code on `production` is the same, thus the change can go to `nightly` with a cherry-pick.
- Only a human can change `LLM transparency/README.md`. Ky must add this journal to it.
