import Foundation

enum OriginalMissionBriefingError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let reason): return "Invalid original mission briefing: \(reason)"
        }
    }
}

/// Initial-objective resources only, not the later NERP message panel. No art,
/// narrative, advisor animation, VM side effects or audio is synthesized here.
/// Objective.cpp:400–433,569–572; GameState.cpp:158–159,456–501.
struct OriginalMissionBriefingDefinition {
    enum Transparency: Equatable {
        case paletteZero
        case rgb(UInt8, UInt8, UInt8)
    }

    struct Panel {
        let path: String
        let position: CGPoint
        let transparency: Transparency

        /// Original syntax is filename,x,y[,r,g,b]. Unlike C atoi, malformed
        /// numbers and partial RGB triples fail rather than becoming zero.
        init(setting: String) throws {
            guard setting.utf8.count <= 2048 else {
                throw OriginalMissionBriefingError.invalid("oversized ObjectiveImage640x480")
            }
            let fields = setting.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 3 || fields.count == 6,
                  let x = Int(fields[1]), let y = Int(fields[2]),
                  (-8192...8192).contains(x), (-8192...8192).contains(y) else {
                throw OriginalMissionBriefingError.invalid("ObjectiveImage640x480 needs a path and bounded integer x,y")
            }
            path = try OriginalMissionBriefingDefinition.validatedPath(fields[0])
            position = CGPoint(x: x, y: y)
            if fields.count == 6 {
                guard let r = UInt8(fields[3]), let g = UInt8(fields[4]), let b = UInt8(fields[5]) else {
                    throw OriginalMissionBriefingError.invalid("ObjectiveImage640x480 RGB must be 0...255")
                }
                transparency = .rgb(r, g, b)
            } else {
                // This is palette entry zero, NOT a generic black color key.
                transparency = .paletteZero
            }
        }
    }

    static let bodyFontPath = "Interface/Fonts/MBriefFONT.bmp"
    static let headingFontPath = "Interface/Fonts/MBriefFONT2.bmp"
    // The shared page arrows, unlike the objective panel, use black RGB keys.
    static let pageButtonTransparency = Transparency.rgb(0, 0, 0)

    let levelIdentifier: String
    let shortLevelName: String
    var speechSampleName: String { "Stream_Objective_" + levelIdentifier }
    let objectiveTextPath: String?
    let panel: Panel?
    let heading: String?
    let continuePrompt: String?
    let continuePromptHasImage: Bool
    /// The existing NERP text takes precedence over Text_SpaceToContinue.
    /// TextMessages.cpp:231–286; Objective.cpp:934.
    func messageText(briefingActive: Bool, nerpsText: String?, messagePermit: Bool = true) -> String? {
        nerpsText ?? (briefingActive && messagePermit ? continuePrompt : nil)
    }
    /// Original title centering measures the CFG value BEFORE replacing '_'.
    let headingBeforeUnderscoreReplacement: String?
    let nextButtonPath: String?
    /// GameState.cpp:1457–1458 draws BackArrow, but Objective.cpp:843–845
    /// hit-tests RepeatButtonImage loaded from BackButton640x480. Preserve the
    /// original distinction; these images need not have the same dimensions.
    let previousArrowPath: String?
    let previousHitTestPath: String?

    init(config: LegoConfig?, levelIdentifier: String) throws {
        self.levelIdentifier = levelIdentifier
        shortLevelName = try Self.validatedShortLevelName(levelIdentifier)
        let level = ["Levels", shortLevelName]
        objectiveTextPath = try config?.valueUnderGame(level + ["ObjectiveText"])
            .map(Self.validatedPath)
        panel = try config?.valueUnderGame(level + ["ObjectiveImage640x480"])
            .map { try Panel(setting: $0) }
        let rawHeading = config?.valueUnderGame(["Main", "MissionBriefingText"])
        if let rawHeading {
            guard rawHeading.utf8.count <= 1022,
                  !rawHeading.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw OriginalMissionBriefingError.invalid("invalid MissionBriefingText")
            }
        }
        // Lego_LoadTextMessages (0x434a20): TextMessages is followed by
        // TextMessagesWithImages, which overrides the same type when present.
        let imagePrompt = config?.valueUnderGame(["TextMessagesWithImages", "Text_SpaceToContinue"])
        let rawPrompt = imagePrompt?.components(separatedBy: ":").first ??
            config?.valueUnderGame(["TextMessages", "Text_SpaceToContinue"])
        continuePromptHasImage = imagePrompt != nil
        if let rawPrompt {
            guard rawPrompt.utf8.count <= 4096 else {
                throw OriginalMissionBriefingError.invalid("oversized Text_SpaceToContinue")
            }
            // Text_SetMessage's substitutions differ from Objective: body.
            continuePrompt = rawPrompt.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "\\n", with: "\n")
        } else { continuePrompt = nil }
        headingBeforeUnderscoreReplacement = rawHeading
        heading = rawHeading?.replacingOccurrences(of: "_", with: " ")
        nextButtonPath = try config?.valueUnderGame(["Main", "NextButton640x480"])
            .map(Self.validatedPath)
        previousArrowPath = try config?.valueUnderGame(["Main", "BackArrow"])
            .map(Self.validatedPath)
        previousHitTestPath = try config?.valueUnderGame(["Main", "BackButton640x480"])
            .map(Self.validatedPath)
    }

    /// Restrict identifiers to the supported CFG structure rather than copying
    /// the original loose "second colon" scan into filesystem lookups.
    fileprivate static func validatedShortLevelName(_ identifier: String) throws -> String {
        let parts = identifier.components(separatedBy: "::")
        guard identifier.utf8.count <= 1022, parts.count == 2,
              parts[0].lowercased() == "levels", !parts[1].isEmpty,
              !parts[1].contains(where: { $0.isWhitespace || "[]:/\\".contains($0) }),
              !parts[1].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw OriginalMissionBriefingError.invalid("expected Levels::shortName")
        }
        return parts[1]
    }

    fileprivate static func validatedPath(_ value: String) throws -> String {
        let path = value.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw OriginalMissionBriefingError.invalid("unsafe resource path")
        }
        return path
    }
}

/// Objective.cpp:121–270: column-zero, case-insensitive section/prefix matching;
/// only the Objective: status is needed for the initial briefing. The BEGIN
/// line is literal (including underscores/backslashes), and even a blank line
/// counts as present. Body underscores are also literal.
struct OriginalMissionBriefingText {
    static let maximumFileBytes = 1_000_000
    static let maximumLineBytes = 1022 // Original char[1024], with LF and NUL.
    static let maximumPages = 512

    /// nil means no matching Objective: declaration, not invented fallback text.
    let body: String?
    let beginText: String?
    let pages: [String]
    var hasBeginText: Bool { beginText != nil }

    init(data: Data, levelIdentifier: String) throws {
        let name = try OriginalMissionBriefingDefinition.validatedShortLevelName(levelIdentifier)
        guard data.count <= Self.maximumFileBytes else {
            throw OriginalMissionBriefingError.invalid("ObjectiveText exceeds file budget")
        }
        let target = "[\(name)]".lowercased()
        var inLevel = false, inBegin = false
        var parsedBody: String?, parsedBegin: String?
        var line: [UInt8] = []

        func finishLine() throws {
            // Deliberate safety fixes: accept CRLF and preserve the last byte
            // when EOF lacks LF, rather than the C parser's unconditional chop.
            if line.last == 13 { line.removeLast() }
            guard line.count <= Self.maximumLineBytes,
                  line.allSatisfy({ $0 >= 32 || $0 == 9 }) else {
                throw OriginalMissionBriefingError.invalid("oversized line or control byte in ObjectiveText")
            }
            let value = String(data: Data(line), encoding: .windowsCP1252)
                ?? String(data: Data(line), encoding: .isoLatin1)
            guard let value else {
                throw OriginalMissionBriefingError.invalid("cannot decode ObjectiveText")
            }
            if value.hasPrefix("[") { inLevel = false; inBegin = false }
            let folded = value.lowercased()
            if inLevel && folded.hasPrefix("objective:") {
                // Repeated definitions corrupt the original count/message
                // relationship. Reject that ambiguous case, not silently merge.
                guard parsedBody == nil else {
                    throw OriginalMissionBriefingError.invalid("duplicate Objective: declaration")
                }
                let content = value.dropFirst("Objective:".count)
                    .drop(while: { $0 == " " || $0 == "\t" })
                parsedBody = Self.unescape(String(content))
            }
            if inBegin {
                inBegin = false
                guard parsedBegin == nil else {
                    throw OriginalMissionBriefingError.invalid("duplicate BEGIN text")
                }
                parsedBegin = value
            }
            // Matching is a prefix check, as in _strnicmp; trailing section
            // comments do not change the section identity.
            if folded.hasPrefix(target) { inLevel = true }
            if folded.hasPrefix("[begin]") { inBegin = true }
            line.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if byte == 10 { try finishLine() }
            else {
                // Allow one CR beyond the content budget while collecting.
                guard line.count <= Self.maximumLineBytes else {
                    throw OriginalMissionBriefingError.invalid("ObjectiveText line exceeds budget")
                }
                line.append(byte)
            }
        }
        if !line.isEmpty { try finishLine() }
        body = parsedBody
        beginText = parsedBegin
        // The C pageCounts value is a LAST INDEX, initially zero. A missing or
        // empty body still has one empty page; body distinguishes those cases.
        pages = (parsedBody ?? "").components(separatedBy: "\u{7}")
        guard pages.count <= Self.maximumPages else {
            throw OriginalMissionBriefingError.invalid("ObjectiveText exceeds page budget")
        }
    }

    private static func unescape(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        var escaped = false
        for index in scalars.indices {
            let value = scalars[index].value
            if escaped && (value == 97 || value == 110) {
                scalars[index - 1] = " "
                scalars[index] = value == 97 ? "\u{7}" : "\n"
                escaped = false
            } else {
                // Unknown/uppercase escapes stay literal; doubled backslashes
                // do not collapse. Only the slash before lowercase a/n changes.
                escaped = value == 92
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// 640x480 original logical coordinates. Text is panel-relative; page buttons
/// are NOT. Objective.cpp:45–63,283–304,356–365,1028–1047.
struct OriginalMissionBriefingLayout {
    static let nextPosition = CGPoint(x: 470, y: 315)
    static let previousPosition = CGPoint(x: 130, y: 315)
    // TextWindow_Create defaults to centered; only the body disables it.
    static let bodyIsCentered = false
    static let beginIsCentered = true
    static let headingIsCentered = true
    let body: CGRect
    let begin: CGRect // BEGIN is drawn on every page, not just the last one.
    let headingArea: CGRect

    init(definition: OriginalMissionBriefingDefinition, text: OriginalMissionBriefingText) {
        let origin = definition.panel?.position ?? .zero
        body = CGRect(x: origin.x + 60, y: origin.y + 60, width: 390,
                      height: text.hasBeginText ? 180 : 200)
        begin = CGRect(x: origin.x + 60, y: origin.y + 220, width: 320, height: 20)
        headingArea = CGRect(x: origin.x + 40, y: origin.y + 34, width: 422, height: 21)
    }

    /// Pass the integer pixel width measured using the RAW CFG title. The
    /// original does integer width/2, even when the measured width is odd.
    func headingFrame(measuredRawWidth: Double) -> CGRect? {
        guard measuredRawWidth.isFinite, (0...8192).contains(measuredRawWidth),
              measuredRawWidth.rounded(.towardZero) == measuredRawWidth else { return nil }
        return CGRect(x: headingArea.minX + headingArea.width / 2 - CGFloat(floor(measuredRawWidth / 2)),
                      y: headingArea.minY, width: CGFloat(measuredRawWidth), height: headingArea.height)
    }
}

/// Frame-state input, not OS key-repeat callbacks. Seed the opening frame with
/// currently held buttons/Space (and any queued click) to prevent click-through.
struct OriginalMissionBriefingInput {
    var spaceDown = false
    var leftDown = false
    var rightDown = false
    var leftHeld = false
    var leftClicked = false
    var pointer: CGPoint? = nil

    fileprivate var hasMouseActivity: Bool { leftDown || rightDown || leftHeld || leftClicked }
}

/// Portable initial-briefing lifecycle. The caller owns rendering and consumes
/// .dismissed ONCE to perform the future NERP ObjectiveSwitch/music transition.
/// No objective-completion, game-state, or advisor behavior is performed here.
struct OriginalMissionBriefingState {
    enum Phase: Equatable { case drainingOpeningMouse, showing, dismissed }
    enum Change: Equatable { case none, pageChanged(Int), dismissed }

    let pageCount: Int
    private(set) var pageIndex = 0
    private(set) var phase: Phase
    private var previousInput: OriginalMissionBriefingInput
    private let nextFrame: CGRect?
    private let previousFrame: CGRect?

    var isActive: Bool { phase != .dismissed }
    var isShowing: Bool { phase == .showing }
    // SetStatus's opening mouse drain precedes entry into the original game
    // loop. This is NOT the briefing pause: showing still permits VM ticks.
    var permitsScriptTick: Bool { phase != .drainingOpeningMouse }
    var hasNextPage: Bool { isShowing && pageIndex < pageCount - 1 }
    var hasPreviousPage: Bool { isShowing && pageIndex > 0 }
    var nextButtonFrame: CGRect? { hasNextPage ? nextFrame : nil }
    /// This is the RepeatButtonImage hitbox, NOT the rendered BackArrow frame.
    var previousHitTestFrame: CGRect? { hasPreviousPage ? previousFrame : nil }

    init(pageCount: Int, nextButtonSize: CGSize? = nil, previousHitTestSize: CGSize? = nil,
         openingInput: OriginalMissionBriefingInput = OriginalMissionBriefingInput()) throws {
        guard (1...OriginalMissionBriefingText.maximumPages).contains(pageCount) else {
            throw OriginalMissionBriefingError.invalid("invalid initial briefing page count")
        }
        func frame(_ size: CGSize?, at position: CGPoint) throws -> CGRect? {
            guard let size else { return nil } // Missing hit-test bitmap disables this mouse target.
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0, size.width <= 8192, size.height <= 8192 else {
                throw OriginalMissionBriefingError.invalid("invalid briefing button dimensions")
            }
            return CGRect(origin: position, size: size)
        }
        self.pageCount = pageCount
        nextFrame = try frame(nextButtonSize, at: OriginalMissionBriefingLayout.nextPosition)
        previousFrame = try frame(previousHitTestSize, at: OriginalMissionBriefingLayout.previousPosition)
        previousInput = openingInput
        phase = openingInput.hasMouseActivity ? .drainingOpeningMouse : .showing
    }

    /// Focus changes can lose key/button releases. Adopt the observed held
    /// state without interpreting that resynchronization as a continue click.
    mutating func synchronizeInput(_ input: OriginalMissionBriefingInput) {
        previousInput = input
        if phase == .drainingOpeningMouse && !input.hasMouseActivity { phase = .showing }
    }

    /// Objective_SetStatus drains opening mouse activity. Polling replaces its
    /// blocking while loop, so held input cannot hang the native app. The first
    /// all-up sample is consumed too: it must not dismiss on the opening mouseup.
    mutating func update(_ input: OriginalMissionBriefingInput) -> Change {
        guard isActive else { return .none }
        defer { previousInput = input }
        if phase == .drainingOpeningMouse {
            if !input.hasMouseActivity { phase = .showing }
            return .none
        }

        let nextPressed = input.spaceDown && !previousInput.spaceDown
        let released = previousInput.leftDown && !input.leftDown
        let pointerValid = input.pointer.map { $0.x.isFinite && $0.y.isFinite } ?? false
        let mouseReleased = released && pointerValid
        func contains(_ frame: CGRect?) -> Bool {
            guard let frame, let point = input.pointer, pointerValid else { return false }
            // C input uses half-open bounds, independent of CGRect conventions.
            return point.x >= frame.minX && point.x < frame.maxX &&
                   point.y >= frame.minY && point.y < frame.maxY
        }
        let overNext = contains(nextButtonFrame)
        let overPrevious = contains(previousHitTestFrame)
        // Space dismisses even while hovering Previous. A mouse release there
        // goes back instead. Elsewhere, the last page accepts a release anywhere.
        if pageIndex == pageCount - 1 && (nextPressed || (mouseReleased && !overPrevious)) {
            phase = .dismissed
            return .dismissed
        }
        let oldPage = pageIndex
        if pageIndex < pageCount - 1 && (nextPressed || (mouseReleased && overNext)) { pageIndex += 1 }
        // Preserve the source ordering for simultaneous Space + Previous click:
        // an intermediate page advances then returns to its original index.
        if pageIndex > 0 && mouseReleased && overPrevious { pageIndex -= 1 }
        return oldPage == pageIndex ? .none : .pageChanged(pageIndex)
    }
}

/// Keeps a live wall-clock baseline while interface/world time is frozen.
/// First frame and resume have zero delta: never bill a briefing or diagnostic
/// pause to mission timers/camera motion on the next frame.
struct OriginalMissionClock {
    private var previous: TimeInterval?
    private var wasPaused = false
    mutating func reset() { previous = nil; wasPaused = false }
    mutating func advance(now: TimeInterval, paused: Bool) -> TimeInterval {
        guard now.isFinite else { reset(); return 0 }
        defer { previous = now; wasPaused = paused }
        guard !paused, !wasPaused, let previous else { return 0 }
        return max(0, now - previous)
    }
}


/// Single-session handoff; neither page changes nor repeated attachment can
/// restart speech/ambience/music. An exited workspace cannot fire stale starts.
struct OriginalMissionStartupGate {
    private(set) var isAttached = false
    private(set) var hasExited = false
    private(set) var speechAttempted = false
    private(set) var gameplayStarted = false
    mutating func attach() { if !hasExited { isAttached = true } }
    mutating func exit() { isAttached = false; hasExited = true }
    mutating func claimSpeechStart(briefingShowing: Bool) -> Bool {
        guard isAttached, !hasExited, briefingShowing, !speechAttempted, !gameplayStarted else { return false }
        speechAttempted = true
        return true
    }
    mutating func claimGameplayStart(briefingActive: Bool) -> Bool {
        guard isAttached, !hasExited, !briefingActive, !gameplayStarted else { return false }
        gameplayStarted = true
        return true
    }
}
