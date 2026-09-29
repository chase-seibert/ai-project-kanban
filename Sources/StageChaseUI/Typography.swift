import SwiftUI

private struct StageTextScaleKey: EnvironmentKey {
  static let defaultValue = 1.0
}

extension EnvironmentValues {
  var stageTextScale: Double {
    get { self[StageTextScaleKey.self] }
    set { self[StageTextScaleKey.self] = newValue }
  }
}

extension View {
  func stageFont(
    _ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default
  ) -> some View {
    modifier(StageFont(style: style, weight: weight, design: design))
  }
}

private struct StageFont: ViewModifier {
  @Environment(\.stageTextScale) private var scale
  let style: Font.TextStyle
  let weight: Font.Weight?
  let design: Font.Design
  func body(content: Content) -> some View {
    #if os(macOS)
      content.font(
        .system(
          size: NSFont.preferredFont(forTextStyle: nativeStyle, options: [:]).pointSize * scale,
          weight: weight ?? (style == .headline ? .semibold : .regular), design: design))
    #else
      content.font(
        .system(style, design: design).weight(weight ?? (style == .headline ? .semibold : .regular))
      )
    #endif
  }
  #if os(macOS)
    private var nativeStyle: NSFont.TextStyle {
      switch style {
      case .largeTitle: .largeTitle
      case .title: .title1
      case .title2: .title2
      case .title3: .title3
      case .headline: .headline
      case .subheadline: .subheadline
      case .callout: .callout
      case .footnote: .footnote
      case .caption: .caption1
      case .caption2: .caption2
      default: .body
      }
    }
  #endif
}
