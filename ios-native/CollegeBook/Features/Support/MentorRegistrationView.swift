import SwiftUI

private let primarySoft = Color(hex: 0xE0FFC2)
private let pageBg = Color(hex: 0xF4F7F6)
private let cardBorder = Color(hex: 0xE6ECEA)
private let ink = Color(hex: 0x1C1E21)
private let labelColor = Color(hex: 0x374151)
private let muted = Color(hex: 0x6B7280)
private let hint = Color(hex: 0x9CA3AF)
private let fieldBorder = Color(hex: 0xDCE3E0)
private let fieldFill = Color(hex: 0xFAFBFB)
private let errorColor = Color(hex: 0xD93025)

/// The "degree" values the API accepts.
private let degrees = ["DNB", "Diploma", "M.Ch", "MD", "MS", "Nbems DMRD"]
/// The least a mentor may charge per minute.
private let minPerMinute = 10

struct Expert: Hashable, Identifiable {
  let id: Int
  let name: String
}

private enum Field: CaseIterable {
  case photo, name, speciality, designation, degree, state, institute, experts, fee
}

private func items(_ json: JSONObject) -> [Expert] {
  (json.object("data") ?? [:]).objects("results").compactMap { r in
    r.string("name").map { Expert(id: r.int("id") ?? 0, name: $0) }
  }
}

/// Mentor registration: photo, name, speciality, designation, degree, exam
/// type, state, institute, expertise and per-minute fee, posted as multipart
/// to college/counsellor/ (CounselorRegistrationActivity's request).
struct MentorRegistrationView: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var photo: Data?
  @State private var name = ""
  @State private var fee = ""
  @State private var speciality: String?
  @State private var designation: String?
  @State private var degree: String?
  @State private var stateName: String?
  @State private var institute: String?
  @State private var experts: [Expert] = []
  /// Inline messages, shown once Submit has been tried.
  @State private var errors: [Field: String] = [:]
  @State private var triedSubmit = false
  @State private var submitting = false
  @State private var choosingPhotoSource = false
  @State private var photoSource: UIImagePickerController.SourceType?
  @State private var choosingDegree = false
  @State private var picker: PickerRoute?
  @State private var pickingExperts = false
  @FocusState private var focus: Field?

  private struct PickerRoute: Identifiable, Hashable {
    let title: String
    let endpoint: String
    var query: [String: String] = [:]
    let field: Field
    var id: String { endpoint }
  }

  private var hasInput: Bool {
    photo != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty || !fee.trimmingCharacters(in: .whitespaces).isEmpty
      || speciality != nil || designation != nil || degree != nil || stateName != nil || institute != nil
      || !experts.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 12) {
            introCard.padding(.bottom, 4)
            photoCard.id(Field.photo)
            section("Professional details", "How students will see you") {
              textInput(.name, "Full name", "e.g. Dr. Ananya Rao", $name)
              selectInput(.speciality, "Speciality", "Select speciality", speciality) {
                picker = PickerRoute(
                  title: "Select speciality", endpoint: "college/counsellor/drop-down/speciality/", field: .speciality)
              }
              selectInput(.designation, "Designation", "Select designation", designation) {
                picker = PickerRoute(
                  title: "Select designation", endpoint: "college/counsellor/drop-down/designation/", field: .designation)
              }
              selectInput(.degree, "Degree", "Select degree", degree, sheet: true) { choosingDegree = true }
              selectInput(nil, "Exam type", "", "NEET PG", locked: true) {}
            }
            section("Your institute", "Where you study or work now") {
              selectInput(.state, "State", "Select state", stateName) {
                picker = PickerRoute(title: "Select state", endpoint: "college/counsellor/drop-down/state/", field: .state)
              }
              selectInput(
                .institute, "Institute", stateName == nil ? "Select a state first" : "Select institute", institute,
                disabled: stateName == nil
              ) {
                guard let stateName else { return app.show("Please select state first") }
                picker = PickerRoute(
                  title: "Select institute", endpoint: "college/counsellor/drop-down/institute_name/",
                  query: ["state": stateName], field: .institute)
              }
            }
            section("Areas of expertise", "Topics you can guide students on") { expertsInput }
            section("Consultation fee", "Students are charged per minute of call") {
              textInput(
                .fee, "Fee per minute", "\(minPerMinute)", $fee, prefix: "₹", suffix: "/ min", numeric: true,
                helper: "Minimum ₹\(minPerMinute) per minute. You can change it later.")
            }
          }
          .padding(EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16))
        }
        .dismissesKeyboardInteractively()
        .background(pageBg)
        .onChangeCompat(of: errors.count) { _, _ in }
        .onReceive(NotificationCenter.default.publisher(for: .mentorFormScroll)) { note in
          if let field = note.object as? Field { withAnimation { proxy.scrollTo(field, anchor: .top) } }
        }
      }
      submitBar
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
    .onChangeCompat(of: name) { _, _ in revalidate() }
    .onChangeCompat(of: fee) { _, new in
      let digits = String(new.filter(\.isNumber).prefix(5))
      if digits != new { fee = digits }
      revalidate()
    }
    .confirmationDialog("Profile photo", isPresented: $choosingPhotoSource, titleVisibility: .visible) {
      Button("Choose from gallery") { photoSource = .photoLibrary }
      Button("Take a photo") {
        if UIImagePickerController.isSourceTypeAvailable(.camera) { photoSource = .camera } else {
          app.show("Camera not available")
        }
      }
    } message: {
      Text("Use a clear, recent photo of your face.")
    }
    .confirmationDialog("Select degree", isPresented: $choosingDegree, titleVisibility: .visible) {
      ForEach(degrees, id: \.self) { d in
        Button(d == degree ? "\(d) ✓" : d) {
          degree = d
          revalidate()
        }
      }
    }
    .fullScreenCover(item: Binding(get: { photoSource.map { SourceBox(source: $0) } }, set: { photoSource = $0?.source })) {
      box in
      // A square crop, so the round avatar shows exactly what was chosen.
      SquarePhotoPicker(source: box.source) { image in
        guard let jpeg = Self.shrink(image) else { return app.show("Couldn't read that image") }
        photo = jpeg
        revalidate()
      }
      .ignoresSafeArea()
    }
    .compatDestination(item: $picker) { route in
      OptionPickerView(title: route.title, endpoint: route.endpoint, query: route.query, selected: value(route.field)) {
        set(route.field, $0)
      }
    }
    .compatDestination(isPresented: $pickingExperts) {
      ExpertsPickerView(selected: experts) {
        experts = $0
        revalidate()
      }
    }
  }

  private struct SourceBox: Identifiable {
    let source: UIImagePickerController.SourceType
    var id: Int { source.rawValue }
  }

  private func value(_ field: Field) -> String? {
    switch field {
    case .speciality: speciality
    case .designation: designation
    case .state: stateName
    case .institute: institute
    default: nil
    }
  }

  private func set(_ field: Field, _ value: String) {
    switch field {
    case .speciality: speciality = value
    case .designation: designation = value
    case .state:
      // The institute list depends on the state.
      if value != stateName { institute = nil }
      stateName = value
    case .institute: institute = value
    default: break
    }
    revalidate()
  }

  /// A JPEG no larger than 1000px a side at quality 85.
  private static func shrink(_ image: UIImage) -> Data? {
    let upright = image.normalized()
    let side = max(upright.size.width, upright.size.height)
    let scale = side > 1000 ? 1000 / side : 1
    let size = CGSize(width: upright.size.width * scale, height: upright.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in upright.draw(in: CGRect(origin: .zero, size: size)) }
      .jpegData(compressionQuality: 0.85)
  }

  // MARK: Validation

  private func revalidate() { if triedSubmit { validate() } }

  /// Fills `errors` for every missing or invalid field.
  private func validate() {
    var e: [Field: String] = [:]
    if photo == nil { e[.photo] = "Please add a profile photo" }
    if name.trimmingCharacters(in: .whitespaces).isEmpty { e[.name] = "Please enter your name" }
    if speciality == nil { e[.speciality] = "Please select your speciality" }
    if designation == nil { e[.designation] = "Please select your designation" }
    if degree == nil { e[.degree] = "Please select your degree" }
    if stateName == nil { e[.state] = "Please select a state" }
    if institute == nil { e[.institute] = "Please select your institute" }
    if experts.isEmpty { e[.experts] = "Please select your expertise" }
    let value = fee.trimmingCharacters(in: .whitespaces)
    if value.isEmpty {
      e[.fee] = "Please enter your fee per minute"
    } else if let amount = Double(value) {
      if amount < Double(minPerMinute) { e[.fee] = "Fee should be at least ₹\(minPerMinute) per minute" }
    } else {
      e[.fee] = "Enter a valid amount"
    }
    errors = e
  }

  private func submit() {
    focus = nil
    triedSubmit = true
    validate()
    if let first = Field.allCases.first(where: { errors[$0] != nil }) {
      app.show(errors[first]!)
      NotificationCenter.default.post(name: .mentorFormScroll, object: first)
      if first == .name || first == .fee { focus = first }
      return
    }
    submitting = true
    Task {
      defer { submitting = false }
      var message: String
      var ok = false
      do {
        let result = try await app.api.postMultipart(
          "college/counsellor/",
          fields: [
            "name": name.trimmingCharacters(in: .whitespaces), "state": stateName!, "institute_name": institute!,
            "speciality": speciality!, "designation": designation!, "degree": degree!,
            "expert": "[\(experts.map { String($0.id) }.joined(separator: ","))]", "per_min": fee.trimmingCharacters(in: .whitespaces),
            "exam_type": "NEET_PG",
          ],
          file: APIClient.UploadFile(field: "image", data: photo!, fileName: "mentor_profile.jpg", mimeType: "image/jpeg"))
        ok = (200..<300).contains(result.status)
        message = result.json?.string(["description", "message"]) ?? (ok ? "Registration submitted" : "Something went wrong")
      } catch {
        message = "Network error. Please try again."
      }
      app.show(message)
      if ok { dismiss() }
    }
  }

  /// Back with a half-filled form asks before throwing it away.
  private func back() {
    guard !submitting else { return }
    guard hasInput else { return dismiss() }
    Task {
      if await NativeAlert.show(
        title: "Discard application?", message: "The details you have entered will be lost.", negative: "Keep editing",
        positive: "Discard", destructive: true)
      {
        dismiss()
      }
    }
  }

  // MARK: Pieces

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: back) {
        Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).padding(8)
      }
      .accessibilityLabel("Back")
      Text("Become a Mentor").font(.inter(18, .bold)).foregroundStyle(.white)
      Spacer()
      NavigationLink {
        ContactUsView()
      } label: {
        Image(systemName: "questionmark.circle").font(.system(size: 20)).foregroundStyle(.white).padding(12)
      }
      .accessibilityLabel("Help")
    }
    .padding(.leading, 8).padding(.trailing, 4)
    .frame(height: 56)
    .background(AppColors.primary)
  }

  private var introCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Image("ic_menu_mentor").renderingMode(.template).resizable().foregroundStyle(.white).padding(10)
          .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("Guide NEET PG aspirants").font(.inter(17, .bold)).foregroundStyle(.white)
          Text("Earn on your own schedule").font(.inter(13)).foregroundStyle(.white.opacity(0.8))
        }
      }
      ForEach(
        [
          ("video", "1:1 video consultations with students"), ("indianrupeesign", "You set your own per-minute fee"),
          ("checkmark.seal", "Verified mentor badge on approval"),
        ], id: \.1
      ) { icon, text in
        HStack(spacing: 10) {
          Image(systemName: icon).font(.system(size: 15)).foregroundStyle(primarySoft).frame(width: 18)
          Text(text).font(.inter(13)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.top, 10)
      }
      .padding(.top, 4)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [stateGreen, AppColors.primary], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 16))
  }

  private func cardBackground(error: Bool = false) -> some View {
    RoundedRectangle(cornerRadius: 16).fill(.white)
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(error ? Color(hex: 0xF3B9B4) : cardBorder))
  }

  private var photoCard: some View {
    let error = errors[.photo]
    return HStack(spacing: 16) {
      Button {
        focus = nil
        choosingPhotoSource = true
      } label: {
        ZStack(alignment: .bottomTrailing) {
          Group {
            if let photo, let image = UIImage(data: photo) {
              Image(uiImage: image).resizable().scaledToFill()
            } else {
              Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Color(hex: 0xB7C0C7))
            }
          }
          .frame(width: 76, height: 76)
          .background(Color(hex: 0xEEF2F4))
          .clipShape(Circle())
          .overlay(Circle().stroke(error != nil ? errorColor : .white, lineWidth: 3))
          .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
          Image(systemName: photo == nil ? "camera" : "pencil").font(.system(size: 12)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(AppColors.primary, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .offset(x: 2, y: 2)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(photo == nil ? "Add profile photo" : "Change profile photo")
      VStack(alignment: .leading, spacing: 4) {
        Text("Profile photo").font(.inter(15, .semibold)).foregroundStyle(ink)
        Text(error ?? "A clear photo helps students recognise and trust you.").font(.inter(12.5))
          .foregroundStyle(error != nil ? errorColor : muted).lineSpacing(3)
        Button(photo == nil ? "Upload photo" : "Change photo") {
          focus = nil
          choosingPhotoSource = true
        }
        .font(.inter(13.5, .semibold)).foregroundStyle(AppColors.primary).padding(.vertical, 4).padding(.top, 2)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .background(cardBackground(error: error != nil))
  }

  private func section<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.inter(15, .bold)).foregroundStyle(ink)
      Text(subtitle).font(.inter(12.5)).foregroundStyle(muted).padding(.top, 2).padding(.bottom, 14)
      content()
    }
    .padding(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground())
  }

  /// Field label above a box, with an inline error or helper below.
  private func frame<Content: View>(_ label: String, error: String?, helper: String? = nil, @ViewBuilder _ content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.inter(13, .semibold)).foregroundStyle(labelColor)
      content()
      if let note = error ?? helper {
        HStack(alignment: .top, spacing: 4) {
          if error != nil { Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(errorColor) }
          Text(note).font(.inter(12)).foregroundStyle(error != nil ? errorColor : muted)
        }
        .padding(.leading, 2)
      }
    }
    .padding(.bottom, 14)
  }

  private func boxBorder(error: Bool, focused: Bool) -> some View {
    RoundedRectangle(cornerRadius: 12).stroke(
      error ? errorColor : focused ? AppColors.primary : fieldBorder, lineWidth: error || focused ? 1.5 : 1)
  }

  private func textInput(
    _ field: Field, _ label: String, _ placeholder: String, _ text: Binding<String>, prefix: String? = nil,
    suffix: String? = nil, numeric: Bool = false, helper: String? = nil
  ) -> some View {
    frame(label, error: errors[field], helper: helper) {
      HStack(spacing: 8) {
        if let prefix { Text(prefix).font(.inter(15, .semibold)).foregroundStyle(ink) }
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(hint))
          .font(.inter(15, .medium)).foregroundStyle(ink)
          .keyboardType(numeric ? .numberPad : .default)
          .textInputAutocapitalization(numeric ? .never : .words)
          .textContentType(numeric ? nil : .name)
          .focused($focus, equals: field)
          .onChangeCompat(of: text.wrappedValue) { _, new in if !numeric, new.count > 60 { text.wrappedValue = String(new.prefix(60)) } }
        if let suffix { Text(suffix).font(.inter(14)).foregroundStyle(muted) }
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 52)
      .background(fieldFill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(boxBorder(error: errors[field] != nil, focused: focus == field))
      .id(field)
    }
  }

  private func selectInput(
    _ field: Field?, _ label: String, _ placeholder: String, _ value: String?, sheet: Bool = false, disabled: Bool = false,
    locked: Bool = false, action: @escaping () -> Void
  ) -> some View {
    let error = field.flatMap { errors[$0] }
    return frame(label, error: error) {
      Button {
        focus = nil
        action()
      } label: {
        HStack(spacing: 8) {
          Text(value ?? placeholder).font(.inter(15, value != nil ? .medium : .regular))
            .foregroundStyle(value != nil ? (locked ? muted : ink) : hint)
          Spacer()
          Image(systemName: locked ? "lock" : sheet ? "chevron.down" : "chevron.right")
            .font(.system(size: locked ? 14 : 15, weight: .medium)).foregroundStyle(disabled || locked ? hint : muted)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 10))
        .frame(minHeight: 52)
        .background(disabled || locked ? Color(hex: 0xF2F4F5) : fieldFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(boxBorder(error: error != nil, focused: false))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(locked)
      .accessibilityLabel("\(label), \(value ?? placeholder)")
      .id(field)
    }
  }

  /// Selected expertise as removable chips, plus an add/edit chip.
  private var expertsInput: some View {
    let error = errors[.experts]
    return frame("Expertise", error: error) {
      FlowStack(spacing: 8, lineSpacing: 8) {
        ForEach(experts) { e in
          HStack(spacing: 4) {
            Text(e.name).font(.inter(13, .semibold)).foregroundStyle(AppColors.primary)
            Button {
              experts.removeAll { $0.id == e.id }
              revalidate()
            } label: {
              Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(AppColors.primary).padding(3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(e.name)")
          }
          .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 6))
          .background(Color(hex: 0xE6F2ED), in: Capsule())
        }
        Button {
          focus = nil
          pickingExperts = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: experts.isEmpty ? "plus" : "pencil").font(.system(size: 13, weight: .semibold))
            Text(experts.isEmpty ? "Add expertise" : "Edit").font(.inter(13, .semibold))
          }
          .foregroundStyle(AppColors.primary)
          .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12))
          .background(.white, in: Capsule())
          .overlay(Capsule().stroke(AppColors.primary))
        }
        .buttonStyle(.plain)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(fieldFill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(boxBorder(error: error != nil, focused: false))
      .id(Field.experts)
    }
  }

  /// The sticky bottom bar: Submit and the terms note.
  private var submitBar: some View {
    VStack(spacing: 8) {
      Button(action: submit) {
        HStack(spacing: 12) {
          if submitting { ProgressView().tint(.white) }
          Text(submitting ? "Submitting…" : "Submit application").font(.inter(16, .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(submitting ? Color(hex: 0x5E8A82) : AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .disabled(submitting)
      NavigationLink {
        LegalDocumentView(doc: .terms)
      } label: {
        (Text("By submitting, you agree to our ") + Text("Terms & Conditions").foregroundColor(AppColors.primary).fontWeight(.semibold))
          .font(.inter(12)).foregroundStyle(muted).multilineTextAlignment(.center)
      }
      .buttonStyle(.plain)
    }
    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    .background(.white)
    .overlay(alignment: .top) { Rectangle().fill(cardBorder).frame(height: 1) }
  }
}

extension Notification.Name {
  fileprivate static let mentorFormScroll = Notification.Name("MentorFormScroll")
}

/// The system photo picker / camera with the square crop editor.
private struct SquarePhotoPicker: UIViewControllerRepresentable {
  let source: UIImagePickerController.SourceType
  let onImage: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = source
    picker.allowsEditing = true
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: SquarePhotoPicker
    init(_ parent: SquarePhotoPicker) { self.parent = parent }

    func imagePickerController(
      _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      // Backing out of the editor keeps the current photo.
      if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.onImage(image) }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
  }
}

// MARK: - Pickers

/// Shared picker chrome: green header with a rounded search box, then a list.
private struct PickerScaffold<Body: View, Bottom: View>: View {
  let title: String
  @Binding var query: String
  @ViewBuilder let content: Body
  @ViewBuilder let bottom: Bottom
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).padding(8)
          }
          .accessibilityLabel("Back")
          Text(title).font(.inter(18, .bold)).foregroundStyle(.white).lineLimit(1)
          Spacer()
        }
        .padding(.leading, 8)
        .frame(height: 56)
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").foregroundStyle(muted)
          TextField("", text: $query, prompt: Text("Search").foregroundColor(hint)).font(.inter(15)).foregroundStyle(ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
      }
      .background(AppColors.primary)
      content.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
      bottom
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

private func pickRow(_ name: String, _ checked: Bool, multi: Bool = false, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    HStack(spacing: 12) {
      Text(name).font(.inter(15, checked ? .semibold : .medium)).foregroundStyle(checked ? AppColors.primary : ink)
        .multilineTextAlignment(.leading).padding(.vertical, 14)
      Spacer()
      if multi {
        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
          .opacity(checked ? 1 : 0)
          .frame(width: 22, height: 22)
          .background(checked ? AppColors.primary : .white, in: RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(checked ? AppColors.primary : Color(hex: 0xC7CBD1), lineWidth: 1.5))
      } else if checked {
        Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(AppColors.primary)
      }
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 54)
    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF0F2F2)).frame(height: 1) }
    .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .accessibilityAddTraits(checked ? .isSelected : [])
}

private func pickerMessage(_ icon: String, _ text: String) -> some View {
  VStack(spacing: 12) {
    Image(systemName: icon).font(.system(size: 36)).foregroundStyle(hint)
    Text(text).font(.inter(14)).foregroundStyle(muted).multilineTextAlignment(.center)
  }
  .padding(32)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// Single-select options (speciality, designation, state, institute).
private struct OptionPickerView: View {
  let title: String
  let endpoint: String
  let query: [String: String]
  let selected: String?
  let onPick: (String) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var all: [Expert]?
  @State private var search = ""

  var body: some View {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = (all ?? []).filter { q.isEmpty || $0.name.lowercased().contains(q) }
    PickerScaffold(title: title, query: $search) {
      if all == nil {
        ProgressView().tint(AppColors.primary).controlSize(.large)
      } else if all!.isEmpty {
        pickerMessage("tray", "Nothing to show right now")
      } else if shown.isEmpty {
        pickerMessage("magnifyingglass", "No matches for your search")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(shown) { item in
              pickRow(item.name, item.name == selected) {
                onPick(item.name)
                dismiss()
              }
            }
          }
        }
      }
    } bottom: {
      EmptyView()
    }
    .task {
      let json = try? await app.api.get(endpoint, query: query)
      all = json.map(items) ?? []
    }
  }
}

/// Multi-select expertise over the paged list.
private struct ExpertsPickerView: View {
  let selected: [Expert]
  let onDone: ([Expert]) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var all: [Expert] = []
  @State private var chosen: [Int: Expert] = [:]
  @State private var search = ""
  @State private var page = 1
  @State private var hasNext = true
  @State private var loading = false
  @State private var loadedOnce = false

  var body: some View {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = all.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    PickerScaffold(title: "Select expertise", query: $search) {
      if !loadedOnce {
        ProgressView().tint(AppColors.primary).controlSize(.large)
      } else if all.isEmpty {
        pickerMessage("tray", "Nothing to show right now")
      } else if shown.isEmpty {
        pickerMessage("magnifyingglass", "No matches for your search")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
              pickRow(item.name, chosen[item.id] != nil, multi: true) {
                if chosen.removeValue(forKey: item.id) == nil { chosen[item.id] = item }
              }
              .onAppear { if index >= shown.count - 5 { Task { await load() } } }
            }
            if loading { ProgressView().tint(AppColors.primary).padding(16) }
          }
          .padding(.bottom, 8)
        }
      }
    } bottom: {
      Button {
        guard !chosen.isEmpty else { return app.show("Please select at least one") }
        // Keep the order they appear in the list.
        onDone(all.filter { chosen[$0.id] != nil } + chosen.values.filter { e in !all.contains(e) })
        dismiss()
      } label: {
        Text(chosen.isEmpty ? "Done" : "Done · \(chosen.count) selected").font(.inter(16, .bold)).foregroundStyle(.white)
          .frame(maxWidth: .infinity).frame(height: 52)
          .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
      .background(.white)
      .overlay(alignment: .top) { Rectangle().fill(cardBorder).frame(height: 1) }
    }
    .task {
      chosen = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      await load()
    }
  }

  private func load() async {
    guard !loading, hasNext else { return }
    loading = true
    do {
      let json = try await app.api.get("college/counsellor-expert/", query: ["page": "\(page)", "limit": "50"])
      hasNext = json.object("data")?.bool("next") == true
      page += 1
      var seen = Set(all.map(\.id))
      all += items(json).filter { seen.insert($0.id).inserted }
    } catch {
      hasNext = false
    }
    loading = false
    loadedOnce = true
  }
}
