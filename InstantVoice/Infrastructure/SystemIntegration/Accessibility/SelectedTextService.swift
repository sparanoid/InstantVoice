import AppKit
import ApplicationServices
import Foundation
import SelectedTextKit
import os

@MainActor
final class SelectedTextService {
    private static let logger = Logger(subsystem: "com.sparanoid.instantvoice", category: "SelectedTextService")
    private static let textManager = SelectedTextManager.shared
    private static let selectedTextStrategies: [TextStrategy] = [
        .accessibility,
        .menuAction,
        .appleScript,
    ]

    static func fetchSelectedText() async -> String? {
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility is not trusted; selected text capture skipped")
            return nil
        }

        // SelectedTextKit targets the frontmost app and runs its menu-copy strategy off the main
        // thread. Aimed at this process, those Accessibility calls run AppKit on that thread and
        // trip NSMenu's main-thread assertion while reading our own main menu.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
            != ProcessInfo.processInfo.processIdentifier
        else {
            logger.debug("InstantVoice is frontmost; selected text capture skipped")
            return nil
        }

        do {
            return normalized(try await textManager.getSelectedText(strategies: selectedTextStrategies))
        } catch {
            logger.debug("SelectedTextKit failed to capture selected text: \(error, privacy: .public)")
            return nil
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
