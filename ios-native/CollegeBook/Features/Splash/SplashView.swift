import SwiftUI

/// SplashScreen: the CollegeBook artwork on brand green for three seconds.
struct SplashView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    ZStack {
      AppColors.primary.ignoresSafeArea()
      Image("collegebooksplash")
        .resizable()
        .scaledToFit()
        .accessibilityLabel("CollegeBook")
    }
    .task {
      try? await Task.sleep(seconds: 3)
      app.finishSplash()
    }
  }
}
