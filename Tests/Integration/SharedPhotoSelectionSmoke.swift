import Foundation

@main
enum SharedPhotoSelectionSmoke {
  static func main() {
    let first = SharedPhotoProject(id: UUID(), name: "First")
    let second = SharedPhotoProject(id: UUID(), name: "Second")

    precondition(SharedPhotoIntake.selectedProject(from: [first, second], rememberedID: nil) == first)
    precondition(
      SharedPhotoIntake.selectedProject(from: [first, second], rememberedID: second.id) == second)
    precondition(
      SharedPhotoIntake.selectedProject(from: [first, second], rememberedID: UUID()) == first)
    precondition(SharedPhotoIntake.selectedProject(from: [], rememberedID: first.id) == nil)
  }
}
