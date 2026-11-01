import PhotosUI
import SwiftUI
import UIKit

// Back-deployment to iOS 15. Each helper uses the current API where the OS
// has it, so newer iPhones behave exactly as before, and an iOS 15
// equivalent elsewhere.

enum Compat {
  /// Debug builds launched with `-compatLegacy` take every iOS 15 fallback on
  /// a newer iPhone, to test them where no iOS 15 device or simulator exists.
  #if DEBUG
    static let legacy = ProcessInfo.processInfo.arguments.contains("-compatLegacy")
  #else
    static let legacy = false
  #endif
}

// MARK: - Concurrency

extension Task where Success == Never, Failure == Never {
  /// Task.sleep(for: .seconds(x)) needs iOS 16.
  static func sleep(seconds: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
  }
}

// MARK: - View helpers

extension View {
  /// Applies `transform`, which can branch on `#available` for newer modifiers.
  @ViewBuilder func modify<T: View>(@ViewBuilder _ transform: (Self) -> T) -> T { transform(self) }

  /// .toolbar(.hidden, for: .navigationBar) needs iOS 16.
  @ViewBuilder func hiddenNavigationBar() -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      toolbar(.hidden, for: .navigationBar)
    } else {
      navigationBarHidden(true)
    }
  }

  /// The iOS 17 two-value onChange; earlier, the old value is remembered here.
  func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V, V) -> Void) -> some View {
    modifier(ChangeObserver(value: value, action: action))
  }

  /// .safeAreaPadding(.top / .bottom) needs iOS 17: the window's inset before.
  @ViewBuilder func safeAreaEdgePadding(_ edge: Edge) -> some View {
    if #available(iOS 17, *), !Compat.legacy {
      safeAreaPadding(edge == .top ? .top : .bottom)
    } else {
      let insets = UIApplication.shared.topViewController?.view.window?.safeAreaInsets
      padding(edge == .top ? .top : .bottom, (edge == .top ? insets?.top : insets?.bottom) ?? 0)
    }
  }

  /// .kerning on any view (a TextField) needs iOS 16.
  @ViewBuilder func kerningIfAvailable(_ value: CGFloat) -> some View {
    if #available(iOS 16, *), !Compat.legacy { kerning(value) } else { self }
  }

  /// .scrollDismissesKeyboard(.interactively) needs iOS 16.
  @ViewBuilder func dismissesKeyboardInteractively() -> some View {
    if #available(iOS 16, *), !Compat.legacy { scrollDismissesKeyboard(.interactively) } else { self }
  }
}

private struct ChangeObserver<V: Equatable>: ViewModifier {
  let value: V
  let action: (V, V) -> Void
  @State private var old: V?

  func body(content: Content) -> some View {
    if #available(iOS 17, *), !Compat.legacy {
      content.onChange(of: value) { old, new in action(old, new) }
    } else {
      content
        .onAppear { old = value }
        .onChange(of: value) { new in
          action(old ?? new, new)
          old = new
        }
    }
  }
}

extension View {
  /// .lineLimit(n, reservesSpace: true) needs iOS 16: text always as tall as
  /// `lines` lines of `font`.
  @ViewBuilder func reservingLines(_ lines: Int, font: Font, lineSpacing: CGFloat = 0) -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      lineLimit(lines, reservesSpace: true)
    } else {
      ZStack(alignment: .top) {
        // An invisible block of `lines` lines in the same font sets the height.
        Text(Array(repeating: " ", count: lines).joined(separator: "\n")).font(font).lineSpacing(lineSpacing)
          .lineLimit(lines).hidden()
        lineLimit(lines)
      }
    }
  }
}

// MARK: - Text input

/// TextField(axis: .vertical), growing up to `lines`, needs iOS 16; a
/// one-line field before.
@ViewBuilder func MultilineTextField(_ text: Binding<String>, prompt: Text, lines: ClosedRange<Int>? = nil) -> some View {
  if #available(iOS 16, *), !Compat.legacy {
    if let lines {
      TextField("", text: text, prompt: prompt, axis: .vertical).lineLimit(lines)
    } else {
      TextField("", text: text, prompt: prompt, axis: .vertical)
    }
  } else {
    TextField("", text: text, prompt: prompt)
  }
}

extension View {
  /// .defaultScrollAnchor(.bottom) needs iOS 17 (the chat also scrolls to
  /// the newest message itself).
  @ViewBuilder func defaultScrollAnchorBottom() -> some View {
    if #available(iOS 17, *), !Compat.legacy { defaultScrollAnchor(.bottom) } else { self }
  }
}

// MARK: - Pull to refresh

extension View {
  /// .refreshable on a ScrollView needs iOS 16 (iOS 15 only refreshes Lists);
  /// a UIRefreshControl on the same scroll view before.
  @ViewBuilder func pullToRefresh(_ action: @escaping @Sendable () async -> Void) -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      // SwiftUI cancels a refresh's task when the screen redraws mid-refresh,
      // which cancelled its requests and emptied lists: the reload runs in its
      // own task, and the spinner still waits for it.
      refreshable { await Task { await action() }.value }
    } else {
      background(RefreshControlInstaller(action: action))
    }
  }
}

/// Finds the UIScrollView this background sits behind (same frame) and gives
/// it a UIRefreshControl that runs `action`.
private struct RefreshControlInstaller: UIViewRepresentable {
  let action: () async -> Void

  func makeUIView(context: Context) -> InstallerView {
    let view = InstallerView()
    view.isUserInteractionEnabled = false
    view.coordinator = context.coordinator
    return view
  }

  func updateUIView(_ view: InstallerView, context: Context) { context.coordinator.action = action }

  func makeCoordinator() -> Coordinator { Coordinator(action: action) }

  final class Coordinator: NSObject {
    var action: () async -> Void
    init(action: @escaping () async -> Void) { self.action = action }

    @objc func refresh(_ control: UIRefreshControl) {
      let action = action
      Task { @MainActor in
        await action()
        control.endRefreshing()
      }
    }
  }

  final class InstallerView: UIView {
    weak var coordinator: Coordinator?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.install() }
    }

    private func install() {
      guard let window, let coordinator else { return }
      let mine = convert(bounds, to: window)
      var ancestor = superview
      for _ in 0..<8 {
        guard let current = ancestor else { return }
        if let scroll = scrollView(in: current, frame: mine, window: window) {
          guard scroll.refreshControl == nil else { return }
          let control = UIRefreshControl()
          control.addTarget(coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
          scroll.refreshControl = control
          return
        }
        ancestor = current.superview
      }
    }

    private func scrollView(in root: UIView, frame: CGRect, window: UIWindow) -> UIScrollView? {
      var queue = [root]
      while !queue.isEmpty {
        let view = queue.removeFirst()
        if let scroll = view as? UIScrollView, scroll.alwaysBounceVertical || scroll.contentSize.height >= scroll.bounds.height,
          abs(scroll.convert(scroll.bounds, to: window).minY - frame.minY) < 2,
          abs(scroll.bounds.height - frame.height) < 2
        {
          return scroll
        }
        queue += view.subviews
      }
      return nil
    }
  }
}

// MARK: - Sheets

/// A sheet height (PresentationDetent needs iOS 16; on iOS 15 sheets open full
/// height).
enum SheetDetent: Hashable {
  case medium, large
  case fraction(CGFloat)
  case height(CGFloat)

  @available(iOS 16, *)
  var detent: PresentationDetent {
    switch self {
    case .medium: .medium
    case .large: .large
    case .fraction(let f): .fraction(f)
    case .height(let h): .height(h)
    }
  }
}

extension View {
  /// .presentationDetents (iOS 16).
  @ViewBuilder func sheetDetents(_ detents: [SheetDetent]) -> some View {
    if #available(iOS 16, *), !Compat.legacy { presentationDetents(Set(detents.map(\.detent))) } else { self }
  }

  /// .presentationDragIndicator(.visible) (iOS 16).
  @ViewBuilder func sheetDragIndicatorVisible() -> some View {
    if #available(iOS 16, *), !Compat.legacy { presentationDragIndicator(.visible) } else { self }
  }

  /// .presentationCornerRadius (iOS 16.4).
  @ViewBuilder func sheetCornerRadius(_ radius: CGFloat) -> some View {
    if #available(iOS 16.4, *), !Compat.legacy { presentationCornerRadius(radius) } else { self }
  }
}

// MARK: - Shapes

/// UnevenRoundedRectangle needs iOS 16.
struct RoundedCornersShape: Shape {
  var topLeadingRadius: CGFloat = 0
  var bottomLeadingRadius: CGFloat = 0
  var bottomTrailingRadius: CGFloat = 0
  var topTrailingRadius: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let maxR = min(rect.width, rect.height) / 2
    let tl = min(topLeadingRadius, maxR), tr = min(topTrailingRadius, maxR)
    let bl = min(bottomLeadingRadius, maxR), br = min(bottomTrailingRadius, maxR)
    var p = Path()
    p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
    p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
    p.closeSubpath()
    return p
  }
}

// MARK: - Navigation

/// NavigationStack needs iOS 16; NavigationView (stack style) before.
struct CompatNavigationStack<Root: View>: View {
  @ViewBuilder let root: () -> Root

  var body: some View {
    if #available(iOS 16, *), !Compat.legacy {
      NavigationStack(root: root)
    } else {
      NavigationView(content: root).navigationViewStyle(.stack)
    }
  }
}

extension View {
  /// navigationDestination(isPresented:) needs iOS 16; a hidden
  /// NavigationLink pushes it before.
  @ViewBuilder func compatDestination<D: View>(
    isPresented: Binding<Bool>, @ViewBuilder destination: @escaping () -> D
  ) -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      navigationDestination(isPresented: isPresented, destination: destination)
    } else {
      background(NavigationLink(isActive: isPresented, destination: destination) { EmptyView() }.hidden())
    }
  }

  /// navigationDestination(item:) needs iOS 17: pushes while `item` is set,
  /// and setting it to nil pops.
  func compatDestination<Item: Hashable, D: View>(
    item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> D
  ) -> some View {
    modifier(ItemDestination(item: item, destination: destination))
  }
}

private struct ItemDestination<Item: Hashable, D: View>: ViewModifier {
  @Binding var item: Item?
  let destination: (Item) -> D
  /// The pushed item, kept through the pop animation after `item` is cleared.
  @State private var shown: Item?

  func body(content: Content) -> some View {
    content
      .compatDestination(
        isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } })
      ) {
        if let value = item ?? shown { destination(value) }
      }
      .onAppear { shown = item }
      .onChangeCompat(of: item) { _, new in if let new { shown = new } }
  }
}

// MARK: - Text alert

/// One text field of a compatTextAlert.
struct CompatAlertField {
  let placeholder: String
  let text: Binding<String>
  var keyboardType: UIKeyboardType = .numberPad
}

extension View {
  /// A TextField inside .alert needs iOS 16 (iOS 15 silently drops it); a
  /// UIAlertController before. The fields' bindings are set before `onConfirm`.
  func compatTextAlert(
    _ title: String, isPresented: Binding<Bool>, fields: [CompatAlertField], confirm: String,
    onConfirm: @escaping () -> Void
  ) -> some View {
    modifier(TextAlertModifier(title: title, isPresented: isPresented, fields: fields, confirm: confirm, onConfirm: onConfirm))
  }
}

private struct TextAlertModifier: ViewModifier {
  let title: String
  @Binding var isPresented: Bool
  let fields: [CompatAlertField]
  let confirm: String
  let onConfirm: () -> Void

  func body(content: Content) -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      content.alert(title, isPresented: $isPresented) {
        ForEach(fields.indices, id: \.self) { index in
          TextField(fields[index].placeholder, text: fields[index].text).keyboardType(fields[index].keyboardType)
        }
        Button("Cancel", role: .cancel) {}
        Button(confirm, action: onConfirm)
      }
    } else {
      content.onChangeCompat(of: isPresented) { _, shown in if shown { present() } }
    }
  }

  private func present() {
    guard let top = UIApplication.shared.topViewController else {
      isPresented = false
      return
    }
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    for field in fields {
      alert.addTextField { input in
        input.placeholder = field.placeholder
        input.text = field.text.wrappedValue
        input.keyboardType = field.keyboardType
      }
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in isPresented = false })
    alert.addAction(
      UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
        for (index, field) in fields.enumerated() {
          field.text.wrappedValue = alert?.textFields?[index].text ?? ""
        }
        isPresented = false
        onConfirm()
      })
    top.present(alert, animated: true)
  }
}

// MARK: - Sharing

/// ShareLink needs iOS 16; the share sheet is presented directly before.
struct CompatShareLink<Label: View>: View {
  let item: String
  let subject: String
  @ViewBuilder let label: () -> Label

  var body: some View {
    if #available(iOS 16, *), !Compat.legacy {
      ShareLink(item: item, subject: Text(subject), label: label)
    } else {
      Button {
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        sheet.setValue(subject, forKey: "subject")
        UIApplication.shared.topViewController?.present(sheet, animated: true)
      } label: {
        label()
      }
    }
  }
}

extension UIApplication {
  /// The view controller on top, to present UIKit sheets from SwiftUI.
  var topViewController: UIViewController? {
    let scene = connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

// MARK: - Photo picking

extension View {
  /// .photosPicker(isPresented:selection:matching: .images) needs iOS 16;
  /// PHPickerViewController before (the photo comes back as JPEG). Calls back
  /// with the image data and its file extension.
  func compatPhotoPicker(isPresented: Binding<Bool>, onPick: @escaping (Data, String) -> Void) -> some View {
    modifier(PhotoPickerModifier(isPresented: isPresented, onPick: onPick))
  }
}

private struct PhotoPickerModifier: ViewModifier {
  @Binding var isPresented: Bool
  let onPick: (Data, String) -> Void
  /// A PhotosPickerItem (iOS 16), stored untyped so the struct exists on iOS 15.
  @State private var item: Any?

  func body(content: Content) -> some View {
    if #available(iOS 16, *), !Compat.legacy {
      content
        .photosPicker(
          isPresented: $isPresented,
          selection: Binding(get: { item as? PhotosPickerItem }, set: { item = $0 }),
          matching: .images)
        .onChange(of: item as? PhotosPickerItem) { picked in
          guard let picked else { return }
          item = nil
          Task {
            guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
            onPick(data, picked.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
          }
        }
    } else {
      content.sheet(isPresented: $isPresented) {
        PHPickerSheet { image in
          isPresented = false
          if let data = image?.jpegData(compressionQuality: 0.92) { onPick(data, "jpg") }
        }
        .ignoresSafeArea()
      }
    }
  }
}

private struct PHPickerSheet: UIViewControllerRepresentable {
  let done: (UIImage?) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(done: done) }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let done: (UIImage?) -> Void
    init(done: @escaping (UIImage?) -> Void) { self.done = done }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
        return done(nil)
      }
      provider.loadObject(ofClass: UIImage.self) { object, _ in
        DispatchQueue.main.async { self.done(object as? UIImage) }
      }
    }
  }
}

// MARK: - Flow layout

/// FlowLayout (a Layout, iOS 16) where available; alignment guides before.
struct FlowStack<Content: View>: View {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(iOS 16, *), !Compat.legacy {
      FlowLayout(spacing: spacing, lineSpacing: lineSpacing)(content)
    } else {
      _VariadicView.Tree(FlowRoot(spacing: spacing, lineSpacing: lineSpacing), content: content)
    }
  }
}

private struct FlowRoot: _VariadicView_MultiViewRoot {
  let spacing: CGFloat
  let lineSpacing: CGFloat

  func body(children: _VariadicView.Children) -> some View {
    FlowFallback(children: children, spacing: spacing, lineSpacing: lineSpacing)
  }
}

private struct FlowFallback: View {
  let children: _VariadicView.Children
  let spacing: CGFloat
  let lineSpacing: CGFloat
  @State private var height: CGFloat = 0

  var body: some View {
    GeometryReader { geo in
      flow(width: geo.size.width)
    }
    .frame(height: height)
  }

  private func flow(width: CGFloat) -> some View {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    let lastId = children.last?.id
    return ZStack(alignment: .topLeading) {
      ForEach(children) { child in
        child
          .fixedSize()
          .alignmentGuide(.leading) { d in
            if x > 0, x + d.width > width {
              x = 0
              y += lineHeight + lineSpacing
              lineHeight = 0
            }
            let result = -x
            lineHeight = max(lineHeight, d.height)
            x += d.width + spacing
            if child.id == lastId { x = 0 }
            return result
          }
          .alignmentGuide(.top) { _ in
            let result = -y
            if child.id == lastId {
              let total = y + lineHeight
              DispatchQueue.main.async { if height != total { height = total } }
              y = 0
              lineHeight = 0
            }
            return result
          }
      }
    }
    .frame(width: width, alignment: .topLeading)
  }
}
