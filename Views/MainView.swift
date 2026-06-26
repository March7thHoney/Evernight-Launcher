import SwiftUI

// MARK: - Main View

struct MainView: View {
    @State private var gameManager = GameManager()
    @State private var showSettings = false

    var body: some View {
        @Bindable var gameManager = gameManager
        GameDetailView(gameManager: gameManager)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .overlay(alignment: .topTrailing) {
                            if AppUpdater.shared.updateAvailable {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                                    .shadow(color: .orange.opacity(0.6), radius: 2)
                            }
                        }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(gameManager: gameManager)
        }
        .alert("Error", isPresented: $gameManager.showErrorAlert) {
            Button("OK", role: .cancel) {
                gameManager.errorMessage = nil
            }
        } message: {
            Text(gameManager.errorMessage ?? "An unknown error occurred.")
        }
        .alert("New Version Available", isPresented: Bindable(AppUpdater.shared).showUpdatePrompt) {
            Button("Update Now") {
                Task {
                    await AppUpdater.shared.installUpdate()
                }
            }
            Button("Later", role: .cancel) {
                AppUpdater.shared.showUpdatePrompt = false
            }
        } message: {
            Text("Version \(AppUpdater.shared.latestVersion ?? "") is available. Would you like to update now?")
        }
        .overlay {
            if AppUpdater.shared.isDownloading {
                VStack(spacing: 16) {
                    Text("Updating Evernight Launcher...")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    ProgressView(value: AppUpdater.shared.updateProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 250)
                    
                    Text(AppUpdater.shared.updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            }
        }
    }
}

#Preview {
    MainView()
}
