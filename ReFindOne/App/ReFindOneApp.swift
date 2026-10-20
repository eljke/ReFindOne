import SwiftUI

@main
struct ReFindOneApp: App {
    @StateObject private var model = AppModel()
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack { LibraryView() }
                    .tabItem { Label("Библиотека", systemImage: "square.stack.3d.up") }
                    .tag(0)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
                    .tag(1)
            }
            .environmentObject(model)
            .sheet(item: $model.captureDraft, onDismiss: model.presentNextShare) { draft in
                AddCaptureView(initialText: draft.text)
                    .environmentObject(model)
            }
            .onOpenURL { url in
                selectedTab = 0
                model.receiveSharedURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    selectedTab = 0
                    model.receiveSharedURL(url)
                }
            }
            .tint(Color(red: 0.40, green: 0.35, blue: 0.91))
            .alert("ReFind One", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
            .overlay(alignment: .top) {
                if let message = model.infoMessage {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                        .padding(.top, 6)
                        .onTapGesture { model.infoMessage = nil }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .overlay(alignment: .bottom) {
                if model.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(model.busyMessage)
                            .font(.footnote.weight(.medium))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 70)
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.infoMessage)
            .task(id: model.infoMessage) {
                if model.infoMessage != nil {
                    try? await Task.sleep(for: .seconds(2.5))
                    if !Task.isCancelled { model.infoMessage = nil }
                }
            }
        }
    }
}
