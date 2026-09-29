import SwiftUI

@main struct StageChaseMacApp: App {
  @State private var model = AppModel()
  @AppStorage("textScale") private var textScale = 1.0
  var body: some Scene {
    WindowGroup("StageChase") {
      RootView().environment(model).environment(\.stageTextScale, textScale).font(
        .system(size: 13 * textScale)
      )
      .frame(minWidth: 1050, minHeight: 620)
      .tint(.indigo)
    }.defaultSize(width: 1560, height: 900)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button("New Task…") { model.sheet = .newTask(.inbox) }.keyboardShortcut("n").disabled(
            model.selectedProject == nil)
          Button("New Project…") { model.sheet = .newProject }.keyboardShortcut(
            "n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
          Button("Show Activity") {
            model.selectedTaskID = nil
            model.showActivity.toggle()
          }.keyboardShortcut("a", modifiers: [.command, .shift])
          Divider()
          Button("Larger Text") { textScale = min(1.4, textScale + 0.05) }.keyboardShortcut("+")
          Button("Smaller Text") { textScale = max(0.85, textScale - 0.05) }.keyboardShortcut("-")
          Button("Actual Text Size") { textScale = 1 }.keyboardShortcut("0")
        }
      }
    Settings {
      AppSettings().environment(model).environment(\.stageTextScale, textScale)
        .font(.system(size: 13 * textScale))
    }
  }
}
