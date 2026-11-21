//
//  AsyncMetadata concurrency Tests.swift
//  Dead-Simple Media Player Tests
//
//  Created by Claude Sonnet 5.5 on 2026-11-21, directed by Ky.
//

import AVFoundation
import Combine
import Foundation
import Testing

@testable import Dead_Simple_Media_Player



/// Tests for the thread safety of `AsyncMetadata`.
///
/// Issue #91: `AsyncMetadata.lazySearch(for:)` changed a `Dictionary` from many threads at the same time.
/// `TitleBar.Metadata.init(in:)` starts 6 lookups on 1 `AsyncMetadata`, so this did occur in the app.
struct AsyncMetadataConcurrencyTests {

    /// 1 lookup for each default key. Each closure uses the `async throws` overload of `get(_:)`.
    ///
    /// The asset in these tests has no metadata, so each lookup ends with `nil`. The lookup still goes through `lazySearch(for:)`, and that is the code under test.
    private static let lookups: [@Sendable (AsyncMetadata) async -> Void] = [
        { _ = try? await $0.get(.title) },
        { _ = try? await $0.get(.creator) },
        { _ = try? await $0.get(.album) },
        { _ = try? await $0.get(.season) },
        { _ = try? await $0.get(.episode) },
        { _ = try? await $0.get(.discNumber) },
        { _ = try? await $0.get(.trackNumber) },
        { _ = try? await $0.get(.image) },
        { _ = try? await $0.get(.publishedDate) },
    ]


    /// The number of different keys in ``lookups``.
    private static let keyCount = lookups.count


    private static func makeMetadata() async throws -> AsyncMetadata {
        try await AsyncMetadata(extractingMetadataFromAsset: AVMutableComposition())
    }


    /// Many tasks ask for all keys of a new instance at the same time. The test passes if the process does not stop.
    ///
    /// Before the fix for issue #91, this can stop the process with `-[NSTaggedPointerString count]: unrecognized selector`. A crash is not certain on each run, so the test repeats many times.
    @Test("Many concurrent first lookups on 1 instance do not crash")
    func concurrentFirstLookupsDoNotCrash() async throws {
        for _ in 0 ..< 500 {
            let metadata = try await Self.makeMetadata()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 4 {
                    for lookup in Self.lookups {
                        group.addTask { await lookup(metadata) }
                    }
                }
            }
        }
    }


    /// The sync overload of `get(_:)` also goes through `lazySearch(for:)`. This test mixes it with the async overload.
    @Test("Sync and async lookups at the same time do not crash")
    func mixedSyncAndAsyncLookupsDoNotCrash() async throws {
        for _ in 0 ..< 500 {
            let metadata = try await Self.makeMetadata()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 4 {
                    for lookup in Self.lookups {
                        group.addTask { await lookup(metadata) }
                    }
                    group.addTask { let _: MetadataSearchResult<String> = metadata.get(.title) }
                    group.addTask { let _: MetadataSearchResult<Int> = metadata.get(.trackNumber) }
                    group.addTask { let _: MetadataSearchResult<DateComponents> = metadata.get(.publishedDate) }
                }
            }
        }
    }


    /// Each key sends exactly 1 ping on ``AsyncMetadata/onMetadataDidUpdate()``, also when many tasks ask for the same key at the same time.
    ///
    /// This test uses timing: it waits for the pings, and then waits a short extra time for pings that must not come.
    @Test("Each key sends exactly 1 update ping")
    @MainActor
    func eachKeySendsExactlyOnePing() async throws {
        let metadata = try await Self.makeMetadata()

        var pingCount = 0
        let subscription = metadata.onMetadataDidUpdate().sink { pingCount += 1 }
        defer { subscription.cancel() }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 4 {
                for lookup in Self.lookups {
                    group.addTask { await lookup(metadata) }
                }
            }
        }

        // Wait up to 5 seconds for all pings.
        for _ in 0 ..< 500 where pingCount < Self.keyCount {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Wait for pings that must not come.
        try await Task.sleep(for: .milliseconds(200))

        #expect(Self.keyCount == pingCount)
    }
}
