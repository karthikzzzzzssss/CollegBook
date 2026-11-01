import SwiftUI

/// lib/features/auth/login_screen.dart: mobile number → 4-digit OTP →
/// Home (LOGIN_SUCCESS) or registration (NEW_USER).
struct LoginView: View {
  @EnvironmentObject private var app: AppState
  @State private var phone = ""
  @State private var otp = ""
  @State private var showOTPStep = false
  @State private var isBusy = false
  @State private var resendSeconds = 0
  @State private var resendTimer: Task<Void, Never>?
  @State private var registerPhone: String?
  @FocusState private var focus: Field?

  private enum Field { case phone, otp }
  private let auth = AuthAPI()

  var body: some View {
    CompatNavigationStack {
      ZStack {
        AppColors.primary.ignoresSafeArea()
        VStack(spacing: 12) {
          Image("collegebook_splash")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: .infinity)
            .accessibilityLabel("CollegeBook")
          card
        }
        .frame(maxWidth: 480)
      }
      .ignoresSafeArea(.container, edges: .bottom)
      .compatDestination(item: $registerPhone) { phone in
        RegisterView(phone: phone)
      }
      .hiddenNavigationBar()
    }
    .onDisappear { resendTimer?.cancel() }
  }

  // MARK: Card

  private var card: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(showOTPStep ? "Verify your number" : "Let's get started")
        .font(.inter(20, .bold))
        .foregroundStyle(AppColors.primary)
        .padding(.bottom, 6)

      if showOTPStep {
        HStack {
          Text("Enter the 4-digit code sent to\n+91 \(formattedPhone)")
            .font(.inter(14))
            .lineSpacing(3)
            // The keyboard leaves little height: the logo gives way, not the number.
            .fixedSize(horizontal: false, vertical: true)
          Spacer()
          Button("Change", action: changeNumber)
            .font(.inter(14, .bold))
            .disabled(isBusy)
        }
        .foregroundStyle(AppColors.primary)
      } else {
        Text("Login or sign up with your mobile number")
          .font(.inter(14))
          .foregroundStyle(AppColors.primary)
      }

      Group {
        if showOTPStep { otpBoxes } else { phoneField }
      }
      .padding(.top, 24)

      if showOTPStep { resendRow.padding(.top, 16) }

      Button(action: showOTPStep ? verifyOTP : continueToOTP) {
        ZStack {
          if isBusy {
            ProgressView().tint(.white)
          } else {
            Text(showOTPStep ? "Verify" : "Continue").font(.inter(16, .bold))
          }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(.white)
        .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 10))
      }
      .disabled(isBusy)
      .padding(.top, 24)

      Text(
        showOTPStep
          ? "By continuing you agree to our Terms & Privacy Policy"
          : "We'll send a 4-digit OTP to verify your number"
      )
      .font(.inter(12))
      .foregroundStyle(AppColors.primary)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .padding(.top, 14)
    }
    .padding(EdgeInsets(top: 28, leading: 24, bottom: 24, trailing: 24))
    .safeAreaEdgePadding(.bottom)
    .background(.white, in: RoundedCornersShape(topLeadingRadius: 24, topTrailingRadius: 24))
  }

  /// Native ll_mobile: 54pt box, 1pt outline, "+91 | number".
  private var phoneField: some View {
    HStack(spacing: 0) {
      Text("+91").font(.inter(16, .semibold))
      Rectangle().frame(width: 1, height: 22).padding(.horizontal, 12)
      TextField(
        "", text: $phone,
        prompt: Text("Enter mobile number").foregroundColor(AppColors.primary.opacity(0.5))
      )
      .font(.inter(16, .medium))
      .kerningIfAvailable(0.64)
      .keyboardType(.numberPad)
      .textContentType(.telephoneNumber)
      .focused($focus, equals: .phone)
      .disabled(isBusy)
      .onChangeCompat(of: phone) { _, new in filterPhone(new) }
    }
    .foregroundStyle(AppColors.primary)
    .padding(.horizontal, 16)
    .frame(height: 54)
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.primary))
    .contentShape(Rectangle())
    .onTapGesture { focus = .phone }
  }

  /// The PinView: four 56pt boxes over one hidden field.
  private var otpBoxes: some View {
    ZStack(alignment: .leading) {
      TextField("", text: $otp)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .focused($focus, equals: .otp)
        .foregroundStyle(.clear)
        .tint(.clear)
        .disabled(isBusy)
        .onChangeCompat(of: otp) { _, new in
          let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(4))
          if digits != new { otp = digits }
        }
        .frame(width: 4 * 56 + 3 * 14, height: 56)
        .accessibilityLabel("One-time code")

      HStack(spacing: 14) {
        ForEach(0..<4, id: \.self) { index in
          let digits = Array(otp)
          let cursorHere = focus == .otp && index == min(digits.count, 3) && digits.count < 4
          ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.white)
            RoundedRectangle(cornerRadius: 10).stroke(AppColors.primary, lineWidth: 1.5)
            if cursorHere {
              Rectangle().fill(AppColors.primary).frame(width: 2, height: 24)
            } else if index < digits.count {
              Text(String(digits[index])).font(.inter(20, .bold)).foregroundStyle(AppColors.primary)
            }
          }
          .frame(width: 56, height: 56)
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
    .onTapGesture { focus = .otp }
  }

  private var resendRow: some View {
    HStack(spacing: 6) {
      Text("Didn't receive the OTP?").foregroundStyle(AppColors.primary)
      if resendSeconds > 0 {
        Text("Resend in").font(.inter(14, .bold)).foregroundStyle(AppColors.muted)
        Text(String(format: "0:%02d", resendSeconds)).font(.inter(14, .semibold)).foregroundStyle(AppColors.title)
      } else {
        Button("Resend", action: resendOTP)
          .font(.inter(14, .bold))
          .foregroundStyle(AppColors.primary)
          .disabled(isBusy)
      }
    }
    .font(.inter(14))
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }

  private var formattedPhone: String {
    guard phone.count == 10 else { return phone }
    return "\(phone.prefix(5)) \(phone.suffix(5))"
  }

  // MARK: Actions

  /// ASCII digits only, at most 10. A paste or autofill can bring a country code
  /// ("+91 98765 43210", "919876543210"), and then the last ten are the number;
  /// otherwise an 11th digit is ignored rather than shifting the number.
  private func filterPhone(_ new: String) {
    let all = new.filter { $0.isASCII && $0.isNumber }
    let hasCode = all.count != new.count || (all.count == 12 && all.hasPrefix("91"))
    let digits = String(hasCode ? all.suffix(10) : all.prefix(10))
    if digits != new { phone = digits }
  }

  private func continueToOTP() {
    guard !isBusy else { return }
    guard phone.count == 10 else {
      app.show("Please enter a valid number")
      return
    }
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        let response = try await auth.requestOTP(phone: phone)
        if response.status == false {
          throw APIError(message: response.description ?? "Could not send an OTP. Please try again.")
        }
        otp = ""
        showOTPStep = true
        startResendTimer()
        app.show(response.description ?? "If this number is registered, an OTP has been sent by SMS.")
        // The OTP field is disabled while busy and only exists from the next
        // frame on; focusing it before then would not bring up the keyboard.
        isBusy = false
        try? await Task.sleep(seconds: 0.15)
        focus = .otp
      } catch {
        app.show(error.localizedDescription)
      }
    }
  }

  private func verifyOTP() {
    guard !isBusy else { return }
    guard otp.count == 4 else {
      app.show("Please enter OTP")
      return
    }
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        // Like the native app: ask for notifications first, then verify either way.
        await app.requestNotificationPermission()
        let response = try await auth.verifyOTP(phone: phone, otp: otp, voipToken: app.voipToken)
        if response.status == false {
          app.show(response.description ?? "Please enter correct OTP")
          await retypeOTP()
          return
        }
        switch response.message {
        case "LOGIN_SUCCESS":
          guard let access = response.accessToken else {
            app.show("The server did not return an access token. Please try again.")
            return
          }
          app.session.saveTokens(access: access, refresh: response.refreshToken)
          app.session.saveProfile(name: response.profileName, phone: response.profilePhone ?? phone)
          resendTimer?.cancel()
          app.signedIn()
        case "NEW_USER":
          registerPhone = phone
        default:
          // Wrong / expired OTP: let them type it again.
          app.show(response.description ?? "Please enter correct OTP")
          await retypeOTP()
        }
      } catch {
        app.show(error.localizedDescription)
        await retypeOTP()
      }
    }
  }

  /// Clears the boxes with the keyboard back up. The field lost focus when it
  /// was disabled for the request, and can only take it once enabled again.
  private func retypeOTP() async {
    otp = ""
    isBusy = false
    try? await Task.sleep(seconds: 0.15)
    focus = .otp
  }

  private func resendOTP() {
    guard !isBusy, resendSeconds == 0 else { return }
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        let response = try await auth.requestOTP(phone: phone)
        if response.status == false {
          throw APIError(message: response.description ?? "Could not resend the OTP. Please try again.")
        }
        otp = ""
        app.show(response.description ?? "A new OTP has been sent by SMS.")
        startResendTimer()
      } catch {
        app.show(error.localizedDescription)
      }
    }
  }

  private func changeNumber() {
    resendTimer?.cancel()
    resendSeconds = 0
    otp = ""
    showOTPStep = false
    focus = .phone
  }

  private func startResendTimer() {
    resendTimer?.cancel()
    resendSeconds = 30
    resendTimer = Task {
      while resendSeconds > 0 {
        try? await Task.sleep(seconds: 1)
        if Task.isCancelled { return }
        resendSeconds -= 1
      }
    }
  }
}
