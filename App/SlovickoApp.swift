import SwiftUI

@main
struct SlovickoApp: App {
    @StateObject private var store = ProgressStore()
    @StateObject private var course = CourseStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Делегат уведомлений нужен сразу при запуске.
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(course)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.refreshHearts()
                        Speech.shared.refreshVoice()
                        NotificationManager.shared.reschedule(for: store)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ProgressStore
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            PathView()
                .tabItem { Label("Учёба", systemImage: "house.fill") }
            ReviewView()
                .tabItem { Label("Повтор", systemImage: "rectangle.stack.fill") }
                .badge(store.dueCount)
            TutorView()
                .tabItem { Label("Репетитор", systemImage: "bubble.left.and.bubble.right.fill") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.blue)
        .roundedDesign()
        .onAppear {
            Speech.shared.rate = Float(store.state.speechRate)
            SoundFX.shared.enabled = store.state.soundsOn
            showOnboarding = !store.state.onboarded
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}
