import XCTest
@testable import VisionSpatialKit

/// v0.25.1 — Locks the pure substrate behind the deferred Vision Pro
/// spatial layout. The visionOS App + RealityView surface plug into
/// the same shape later; every test here reflects a contract the
/// future surface reads.
final class VisionSpatialKitTests: XCTestCase {

    // MARK: - SpatialAnchor

    /// The anchor preserves every field through a Codable round trip
    /// — critical because the store writes one JSON file per preset
    /// and a future CloudKit mirror serialises the same shape.
    func test_anchor_codableRoundTrip_preservesEveryField() throws {
        let original = SpatialAnchor(
            x: 0.5,
            y: 0.3,
            z: -1.2,
            yaw: 0.7,
            pitch: -0.2,
            roll: 0.1
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpatialAnchor.self, from: data)

        XCTAssertEqual(decoded.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.y, 0.3, accuracy: 0.001)
        XCTAssertEqual(decoded.z, -1.2, accuracy: 0.001)
        XCTAssertEqual(decoded.yaw, 0.7, accuracy: 0.001)
        XCTAssertEqual(decoded.pitch, -0.2, accuracy: 0.001)
        XCTAssertEqual(decoded.roll, 0.1, accuracy: 0.001)
    }

    /// Position values are clamped to ±10 m so a programmer error
    /// (centimetres mistaken for metres) can't spawn a panel
    /// 30 metres away from the user.
    func test_anchor_clampsPositionTo10m() {
        let huge = SpatialAnchor(x: 9999, y: -9999, z: 9999)
        XCTAssertEqual(huge.x, 10)
        XCTAssertEqual(huge.y, -10)
        XCTAssertEqual(huge.z, 10)
    }

    /// Angles are wrapped into `[-π, π]` at construction so a
    /// downstream `simd_quatf` conversion never sees a runaway
    /// 7π value.
    func test_anchor_wrapsAnglesIntoMinusPiToPi() {
        let wrapped = SpatialAnchor(x: 0, y: 0, z: 0, yaw: 7 * .pi, pitch: -7 * .pi, roll: 3 * .pi)
        XCTAssertLessThanOrEqual(abs(wrapped.yaw), .pi + 0.001)
        XCTAssertLessThanOrEqual(abs(wrapped.pitch), .pi + 0.001)
        XCTAssertLessThanOrEqual(abs(wrapped.roll), .pi + 0.001)
    }

    /// `origin` is the literal (0, 0, 0) zero-rotation anchor —
    /// SwiftUI surfaces use this as the safe default when a preset
    /// opens before the user has aimed.
    func test_anchor_originIsZero() {
        XCTAssertEqual(SpatialAnchor.origin.x, 0)
        XCTAssertEqual(SpatialAnchor.origin.y, 0)
        XCTAssertEqual(SpatialAnchor.origin.z, 0)
        XCTAssertEqual(SpatialAnchor.origin.yaw, 0)
    }

    /// Translation adds the supplied vector. Used by the layout
    /// builder to walk a base anchor across a grid.
    func test_anchor_translation_addsVector() {
        let base = SpatialAnchor(x: 0.5, y: 0, z: -1.0)
        let translated = base.translated(byX: 0.2, y: 0.1, z: -0.3)
        XCTAssertEqual(translated.x, 0.7, accuracy: 0.001)
        XCTAssertEqual(translated.y, 0.1, accuracy: 0.001)
        XCTAssertEqual(translated.z, -1.3, accuracy: 0.001)
    }

    /// `facing(_:)` rotates the anchor so it points at the target.
    /// An anchor at (1, 0, -1) facing the origin should have a
    /// positive yaw (rotated right-of-front).
    func test_anchor_facingOrigin_yawsTowardCenter() {
        let rightSide = SpatialAnchor(x: 1, y: 0, z: -1)
        let facing = rightSide.facing(.origin)
        // Origin is to the user's left from the panel's perspective,
        // so the yaw should be negative (panel rotates left).
        XCTAssertLessThan(facing.yaw, 0)
        // Pitch stays zero — both at y = 0.
        XCTAssertEqual(facing.pitch, 0, accuracy: 0.001)
    }

    // MARK: - SpatialPanel

    /// Codable round trip preserves every field.
    func test_panel_codableRoundTrip_preservesEveryField() throws {
        let payload = UUID()
        let id = UUID()
        let original = SpatialPanel(
            id: id,
            kind: .auditReport,
            anchor: SpatialAnchor(x: 0, y: 0, z: -2),
            widthMeters: 1.6,
            heightMeters: 1.0,
            title: "Audit AZ Construction",
            payloadID: payload
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SpatialPanel.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.kind, .auditReport)
        XCTAssertEqual(decoded.widthMeters, 1.6, accuracy: 0.001)
        XCTAssertEqual(decoded.heightMeters, 1.0, accuracy: 0.001)
        XCTAssertEqual(decoded.title, "Audit AZ Construction")
        XCTAssertEqual(decoded.payloadID, payload)
    }

    /// Panel dimensions are clamped to `[0.05, 4.0]` metres so a
    /// 100-metre panel never spawns.
    func test_panel_clampsSizeWithinBounds() {
        let huge = SpatialPanel(
            kind: .generic,
            anchor: .origin,
            widthMeters: 1000,
            heightMeters: 0.001
        )
        XCTAssertEqual(huge.widthMeters, 4.0)
        XCTAssertEqual(huge.heightMeters, 0.05)
    }

    /// Titles are trimmed to 80 characters at construction so a
    /// runaway transcript can't blow the panel's title bar.
    func test_panel_trimsLongTitleTo80Chars() {
        let long = String(repeating: "x", count: 200)
        let panel = SpatialPanel(
            kind: .noteCard,
            anchor: .origin,
            widthMeters: 0.5,
            heightMeters: 0.7,
            title: long
        )
        XCTAssertEqual(panel.title.count, 80)
    }

    /// `diagonalMeters` returns sqrt(w² + h²) — the layout builder
    /// uses this to compute safe spacing.
    func test_panel_diagonalIsPythagorean() {
        let panel = SpatialPanel(
            kind: .generic,
            anchor: .origin,
            widthMeters: 0.3,
            heightMeters: 0.4
        )
        XCTAssertEqual(panel.diagonalMeters, 0.5, accuracy: 0.001)
    }

    /// `.anchored(at:)` returns a new panel with the new anchor;
    /// every other field stays identical.
    func test_panel_anchored_changesAnchorOnly() {
        let original = SpatialPanel(
            kind: .focusTimer,
            anchor: SpatialAnchor(x: 0, y: 0, z: 0),
            widthMeters: 0.3,
            heightMeters: 0.3,
            title: "25 min"
        )
        let moved = original.anchored(at: SpatialAnchor(x: 0, y: 0, z: -1))

        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(moved.kind, original.kind)
        XCTAssertEqual(moved.title, original.title)
        XCTAssertEqual(moved.widthMeters, original.widthMeters)
        XCTAssertEqual(moved.anchor.z, -1)
    }

    // MARK: - SpatialLayoutBuilder

    /// Empty input returns empty output for every preset.
    func test_builder_emptyInput_returnsEmpty() {
        for preset in SpatialLayoutPreset.allCases {
            XCTAssertEqual(SpatialLayoutBuilder.layout(panels: [], preset: preset), [])
        }
    }

    /// Bento — 3 columns: the middle panel sits at x = 0, the left
    /// panel at x = -step, the right panel at x = +step. All at
    /// `bentoDepth`.
    func test_builder_bento_threePanels_arrangeAsRow() {
        let panels = (0..<3).map { i in
            SpatialPanel(
                kind: .generic,
                anchor: .origin,
                widthMeters: 0.5,
                heightMeters: 0.4,
                title: "Panel \(i)"
            )
        }
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .bento)

        // Column 0 (left)
        XCTAssertEqual(laid[0].anchor.x, -SpatialLayoutBuilder.bentoColumnStep, accuracy: 0.001)
        // Column 1 (middle)
        XCTAssertEqual(laid[1].anchor.x, 0, accuracy: 0.001)
        // Column 2 (right)
        XCTAssertEqual(laid[2].anchor.x, SpatialLayoutBuilder.bentoColumnStep, accuracy: 0.001)
        // All at the same depth
        for panel in laid {
            XCTAssertEqual(panel.anchor.z, SpatialLayoutBuilder.bentoDepth)
        }
    }

    /// Bento — 6 panels span 2 rows of 3 columns. Row 2 sits below
    /// row 1 by `bentoRowStep`.
    func test_builder_bento_sixPanels_spanTwoRows() {
        let panels = (0..<6).map { i in
            SpatialPanel(
                kind: .generic,
                anchor: .origin,
                widthMeters: 0.5,
                heightMeters: 0.4,
                title: "P\(i)"
            )
        }
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .bento)

        // Row 0 (panels 0..2) y > row 1 (panels 3..5) y
        XCTAssertGreaterThan(laid[0].anchor.y, laid[3].anchor.y)
        XCTAssertEqual(laid[0].anchor.y - laid[3].anchor.y, SpatialLayoutBuilder.bentoRowStep, accuracy: 0.001)
    }

    /// Cinema — index 0 is the hero panel: dead centre at
    /// (0, 0, cinemaDepth).
    func test_builder_cinema_heroSitsCentered() {
        let panels = (0..<5).map { i in
            SpatialPanel(
                kind: i == 0 ? .auditReport : .generic,
                anchor: .origin,
                widthMeters: 1.0,
                heightMeters: 0.7,
                title: "P\(i)"
            )
        }
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .cinema)

        XCTAssertEqual(laid[0].anchor.x, 0, accuracy: 0.001)
        XCTAssertEqual(laid[0].anchor.y, 0, accuracy: 0.001)
        XCTAssertEqual(laid[0].anchor.z, SpatialLayoutBuilder.cinemaDepth, accuracy: 0.001)
    }

    /// Cinema — side panels splay alternately left / right of the
    /// hero. Index 1 has negative x, index 2 has positive x.
    func test_builder_cinema_sidePanelsAlternate() {
        let panels = (0..<5).map { _ in
            SpatialPanel(
                kind: .generic,
                anchor: .origin,
                widthMeters: 1.0,
                heightMeters: 0.7
            )
        }
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .cinema)

        XCTAssertLessThan(laid[1].anchor.x, 0)   // left
        XCTAssertGreaterThan(laid[2].anchor.x, 0) // right
        XCTAssertLessThan(laid[3].anchor.x, 0)   // left
        XCTAssertGreaterThan(laid[4].anchor.x, 0) // right
    }

    /// Atelier — the first `.focusTimer` panel anchors at the
    /// central focus position (0, 0, atelierDepth). Other panels
    /// push off to ±1.0 m horizontal.
    func test_builder_atelier_focusTimerInCenter() {
        let panels = [
            SpatialPanel(kind: .auditReport, anchor: .origin, widthMeters: 1.0, heightMeters: 0.7),
            SpatialPanel(kind: .focusTimer, anchor: .origin, widthMeters: 0.3, heightMeters: 0.3),
            SpatialPanel(kind: .noteCard, anchor: .origin, widthMeters: 0.5, heightMeters: 0.7)
        ]
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .atelier)

        // Focus timer at index 1 → centred at z = atelierDepth.
        XCTAssertEqual(laid[1].anchor.x, 0, accuracy: 0.001)
        XCTAssertEqual(laid[1].anchor.z, SpatialLayoutBuilder.atelierDepth, accuracy: 0.001)

        // Other panels off-centre
        XCTAssertEqual(abs(laid[0].anchor.x), 1.0, accuracy: 0.001)
        XCTAssertEqual(abs(laid[2].anchor.x), 1.0, accuracy: 0.001)
    }

    /// Layout is deterministic for identical input — the same
    /// panels + the same preset produce byte-identical anchors.
    func test_builder_deterministicForIdenticalInput() {
        let panels = (0..<6).map { i in
            SpatialPanel(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(i)")!,
                kind: .generic,
                anchor: .origin,
                widthMeters: 0.5,
                heightMeters: 0.4
            )
        }
        let first = SpatialLayoutBuilder.layout(panels: panels, preset: .bento)
        let second = SpatialLayoutBuilder.layout(panels: panels, preset: .bento)
        XCTAssertEqual(first, second)
    }

    /// Preserves panel ordering (the SwiftUI surface diffs by index)
    /// + identity (UUIDs untouched).
    func test_builder_preservesOrderAndIDs() {
        let panels = (0..<4).map { _ in
            SpatialPanel(
                kind: .generic,
                anchor: .origin,
                widthMeters: 0.5,
                heightMeters: 0.4
            )
        }
        let laid = SpatialLayoutBuilder.layout(panels: panels, preset: .cinema)
        XCTAssertEqual(laid.count, panels.count)
        for (input, output) in zip(panels, laid) {
            XCTAssertEqual(input.id, output.id)
            XCTAssertEqual(input.kind, output.kind)
        }
    }

    // MARK: - SpatialLayoutPreset

    /// Three presets ship in the substrate.
    func test_preset_threeCases() {
        XCTAssertEqual(SpatialLayoutPreset.allCases.count, 3)
    }

    /// Every preset has a non-empty FR + EN display name + subtitle.
    func test_preset_localizedStringsNonEmpty() {
        for preset in SpatialLayoutPreset.allCases {
            XCTAssertFalse(preset.displayNameFR.isEmpty)
            XCTAssertFalse(preset.displayNameEN.isEmpty)
            XCTAssertFalse(preset.subtitleFR.isEmpty)
        }
    }

    /// Raw values are stable so on-disk persistence doesn't break
    /// between releases.
    func test_preset_rawValuesStable() {
        XCTAssertEqual(SpatialLayoutPreset.bento.rawValue, "bento")
        XCTAssertEqual(SpatialLayoutPreset.cinema.rawValue, "cinema")
        XCTAssertEqual(SpatialLayoutPreset.atelier.rawValue, "atelier")
    }

    // MARK: - SpatialLayoutStore

    /// Save → load round trip surfaces the original panel list.
    func test_store_saveLoadRoundTrip() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        let panels = [
            SpatialPanel(
                kind: .focusTimer,
                anchor: SpatialAnchor(x: 0, y: 0, z: -1),
                widthMeters: 0.3,
                heightMeters: 0.3,
                title: "Focus 25 min"
            ),
            SpatialPanel(
                kind: .auditReport,
                anchor: SpatialAnchor(x: 0.5, y: 0, z: -1.5),
                widthMeters: 1.6,
                heightMeters: 1.0,
                title: "AZ Construction"
            )
        ]

        try await store.save(panels, for: .bento)
        let loaded = try await store.load(.bento)

        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].kind, .focusTimer)
        XCTAssertEqual(loaded?[0].title, "Focus 25 min")
        XCTAssertEqual(loaded?[1].title, "AZ Construction")
    }

    /// Loading a preset that's never been saved returns nil.
    func test_store_loadMissingPresetReturnsNil() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        let loaded = try await store.load(.cinema)
        XCTAssertNil(loaded)
    }

    /// Save replaces the previous JSON for the same preset
    /// (idempotent overwrite).
    func test_store_saveReplacesPrevious() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        let first = [
            SpatialPanel(kind: .generic, anchor: .origin, widthMeters: 0.5, heightMeters: 0.4, title: "v1")
        ]
        let second = [
            SpatialPanel(kind: .noteCard, anchor: .origin, widthMeters: 0.5, heightMeters: 0.7, title: "v2"),
            SpatialPanel(kind: .generic, anchor: .origin, widthMeters: 0.3, heightMeters: 0.3, title: "v3")
        ]

        try await store.save(first, for: .bento)
        try await store.save(second, for: .bento)
        let loaded = try await store.load(.bento)

        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].title, "v2")
    }

    /// Delete removes the file; subsequent load returns nil.
    func test_store_deleteRemovesFile() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        try await store.save([SpatialPanel(kind: .generic, anchor: .origin, widthMeters: 0.5, heightMeters: 0.4)], for: .atelier)

        let removed = try await store.delete(.atelier)
        XCTAssertTrue(removed)

        let loaded = try await store.load(.atelier)
        XCTAssertNil(loaded)
    }

    /// Delete on a missing preset is a no-op (returns false).
    func test_store_deleteMissingPresetReturnsFalse() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        let removed = try await store.delete(.cinema)
        XCTAssertFalse(removed)
    }

    /// `isEmpty` is true when no preset has been saved, false after
    /// the first save.
    func test_store_isEmptyFlipsAfterSave() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SpatialLayoutStore(rootDirectory: root)
        let initial = try await store.isEmpty()
        XCTAssertTrue(initial)

        try await store.save(
            [SpatialPanel(kind: .generic, anchor: .origin, widthMeters: 0.5, heightMeters: 0.4)],
            for: .bento
        )

        let afterSave = try await store.isEmpty()
        XCTAssertFalse(afterSave)
    }

    /// A fresh store reading the same root after the previous
    /// instance saved data hydrates the persisted layout (the cache
    /// doesn't shadow disk).
    func test_store_hydrationAcrossInstances() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = SpatialLayoutStore(rootDirectory: root)
        try await writer.save(
            [
                SpatialPanel(
                    kind: .auditReport,
                    anchor: SpatialAnchor(x: 0, y: 0, z: -2),
                    widthMeters: 1.6,
                    heightMeters: 1.0,
                    title: "Persisted across instances"
                )
            ],
            for: .cinema
        )

        let reader = SpatialLayoutStore(rootDirectory: root)
        let loaded = try await reader.load(.cinema)

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].title, "Persisted across instances")
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-spatial-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
