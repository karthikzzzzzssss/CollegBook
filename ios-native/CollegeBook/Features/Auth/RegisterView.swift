import SwiftUI

/// lib/features/auth/register_screen.dart: a new number gives its name.
struct RegisterView: View {
  let phone: String

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var isBusy = false
  @FocusState private var nameFocused: Bool

  var body: some View {
    ZStack(alignment: .top) {
      AppColors.primary.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ZStack {
            Text("Create Account").font(.inter(20, .medium))
            HStack {
              Button {
                dismiss()
              } label: {
                Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium))
                  .extendedTapArea(horizontal: 11, vertical: 11)
              }
              .disabled(isBusy)
              .accessibilityLabel("Back")
              Spacer()
            }
            .padding(.leading, 16)
          }
          .padding(.top, 24)

          Text("Full name *")
            .font(.inter(14, .medium))
            .padding(.top, 100)
            .padding(.horizontal, 24)

          TextField(
            "", text: $name,
            prompt: Text("Enter your full name").foregroundColor(AppColors.primary.opacity(0.5))
          )
          .font(.inter(16))
          .foregroundStyle(AppColors.primary)
          .textContentType(.name)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .onSubmit(register)
          .focused($nameFocused)
          .disabled(isBusy)
          .padding(16)
          .background(.white, in: RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.allIndia, lineWidth: nameFocused ? 2 : 1.5))
          .padding(.horizontal, 24)
          .padding(.top, 8)

          Button(action: register) {
            ZStack {
              if isBusy {
                ProgressView().tint(AppColors.primary).frame(width: 58, height: 19)
              } else {
                Text("Continue").font(.inter(16, .bold))
              }
            }
            .foregroundStyle(AppColors.primary)
            .padding(.horizontal, 42)
            .padding(.vertical, 10)
            .background(AppColors.allIndia, in: RoundedRectangle(cornerRadius: 8))
          }
          .disabled(isBusy)
          .frame(maxWidth: .infinity)
          .padding(.top, 42)
        }
        .foregroundStyle(AppColors.allIndia)
        .tabletContentWidth(TabletUI.loginCardMaxWidth)
      }
    }
    .hiddenNavigationBar()
    .onAppear { nameFocused = true }
  }

  private func register() {
    guard !isBusy else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      app.show("Please enter your name")
      return
    }
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        await app.requestNotificationPermission()
        let response = try await AuthAPI().register(phone: phone, name: trimmed, voipToken: app.voipToken)
        guard response.status == true, response.message == "PROFILE_CREATED" else {
          app.show(response.description ?? "Registration failed. Please try again.")
          return
        }
        guard let access = response.accessToken else {
          app.show("The server did not return an access token. Please try again.")
          return
        }
        app.session.saveTokens(access: access, refresh: response.refreshToken)
        app.session.saveProfile(name: response.profileName ?? trimmed, phone: response.profilePhone ?? phone)
        if let description = response.description { app.show(description) }
        app.signedIn()
      } catch {
        app.show(error.localizedDescription)
      }
    }
  }
}
