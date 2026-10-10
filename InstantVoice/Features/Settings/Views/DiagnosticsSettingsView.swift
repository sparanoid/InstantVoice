import SwiftUI

struct DiagnosticsSettingsView: View {
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showLogExportError = false
    @State private var logExportError: String = ""
    @State private var isSystemInfoCopied = false

    var body: some View {
        LabeledContent("Copy System Info") {
            Button {
                copySystemInfo()
            } label: {
                Label(
                    isSystemInfoCopied ? "Copied!" : "Copy",
                    systemImage: isSystemInfoCopied ? "checkmark" : "doc.on.doc"
                )
                .contentTransition(.symbolEffect(.replace))
            }
        }

        LabeledContent {
            HStack(spacing: 8) {
                if let url = exportedLogURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Status.positive)
                }

                Button("Export") {
                    exportDiagnosticLogs()
                }
                .disabled(isExportingLogs)
            }
        } label: {
            HStack(spacing: 4) {
                if isExportingLogs {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Export Logs")
            }
        }
        .alert("Export Failed", isPresented: $showLogExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logExportError)
        }
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.smooth(duration: 0.2)) {
            isSystemInfoCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.smooth(duration: 0.2)) {
                isSystemInfoCopied = false
            }
        }
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        exportedLogURL = nil

        Task {
            do {
                let url = try await LogExporter.shared.exportLogs()
                await MainActor.run {
                    exportedLogURL = url
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportError = error.localizedDescription
                    showLogExportError = true
                    isExportingLogs = false
                }
            }
        }
    }
}
