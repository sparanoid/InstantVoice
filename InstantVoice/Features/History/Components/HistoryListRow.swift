import SwiftUI

/// A two-line row for the main window's history list, in the style of a mail message list.
struct HistoryListRow: View {
    /// Two text lines plus padding. The list uses it as its minimum row height so rows never clip.
    static let height: CGFloat = 62

    let transcription: Transcription

    var body: some View {
        // Baseline alignment keeps the mode icon level with the time on the first line.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            modeIcon
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.relativeTimestamp(for: transcription.timestamp))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if transcription.hasEnhancedHistoryText {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Enhanced")
                            .accessibilityLabel("Enhanced")
                    }

                    Spacer(minLength: 4)

                    if transcription.duration > 0 {
                        Text(Duration.seconds(Int(transcription.duration)), format: .time(pattern: .minuteSecond))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                // Reserving both lines gives every row the same height, which the list can't mis-measure.
                Text(transcription.preferredHistoryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Mail-style date: the time today, then "Yesterday", the weekday this week, and the date after that.
    static func relativeTimestamp(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return time
        }
        if calendar.isDateInYesterday(date) {
            return "\(String(localized: "Yesterday")), \(time)"
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
            days < 7
        {
            return date.formatted(.dateTime.weekday(.wide).hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    @ViewBuilder
    private var modeIcon: some View {
        if let icon = transcription.recordedHistoryModeIcon {
            ModeIconView(icon: icon, size: icon.kind == .emoji ? 16 : 14)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Shown in the detail pane when several transcriptions are selected.
struct HistoryMultiSelectionView: View {
    let count: Int
    let canSelectAll: Bool
    let onSelectAll: () -> Void
    let onAnalyze: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(String(format: String(localized: "%lld Transcriptions Selected"), Int64(count)))
            } icon: {
                Image(systemName: "square.stack.3d.up")
            }
        } description: {
            Text("Analyze, export, or delete the selected transcriptions.")
        } actions: {
            HStack(spacing: 10) {
                Button(action: onAnalyze) {
                    Label("Analyze", systemImage: "chart.bar.xaxis")
                }

                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if canSelectAll {
                Button("Select All", action: onSelectAll)
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
        }
    }
}
