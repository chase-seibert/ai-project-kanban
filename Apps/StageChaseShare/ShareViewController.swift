import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
  private var projects: [SharedPhotoProject] = []
  private var selectedProject: SharedPhotoProject?
  private var imageData: Data?
  private var imageName = "Shared image"
  private var mediaType = ""
  private let preview = UIImageView()
  private let projectButton = UIButton(type: .system)
  private let titleField = UITextField()
  private let descriptionField = UITextView()
  private let statusLabel = UILabel()
  private let saveButton = UIButton(type: .system)
  private let cancelButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    projects = Self.loadProjects()
    selectedProject = projects.first
    buildForm()
    loadSharedImage()
  }

  private static func loadProjects() -> [SharedPhotoProject] {
    guard let data = UserDefaults(suiteName: SharedPhotoIntake.appGroup)?.data(
      forKey: SharedPhotoIntake.projectsKey),
      let projects = try? JSONDecoder().decode([SharedPhotoProject].self, from: data)
    else { return [] }
    return projects
  }

  private func buildForm() {
    preview.contentMode = .scaleAspectFit
    preview.backgroundColor = .secondarySystemBackground
    preview.layer.cornerRadius = 12
    preview.clipsToBounds = true
    preview.heightAnchor.constraint(equalToConstant: 180).isActive = true
    preview.accessibilityLabel = "Shared photo preview"
    preview.accessibilityIdentifier = "shared-task-photo-preview"

    projectButton.contentHorizontalAlignment = .leading
    projectButton.setTitleColor(.label, for: .normal)
    projectButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
    projectButton.addTarget(self, action: #selector(chooseProject), for: .touchUpInside)
    updateProjectButton()

    titleField.placeholder = "Task title"
    titleField.borderStyle = .roundedRect
    titleField.returnKeyType = .next
    titleField.delegate = self
    titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
    titleField.accessibilityIdentifier = "shared-task-title"

    descriptionField.font = .preferredFont(forTextStyle: .body)
    descriptionField.backgroundColor = .secondarySystemBackground
    descriptionField.layer.cornerRadius = 8
    descriptionField.text = ""
    descriptionField.heightAnchor.constraint(equalToConstant: 64).isActive = true
    descriptionField.delegate = self
    descriptionField.accessibilityLabel = "Task description"
    descriptionField.accessibilityIdentifier = "shared-task-description"
    descriptionField.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)

    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 0
    statusLabel.isHidden = true

    var config = UIButton.Configuration.filled()
    config.title = "Add task"
    config.cornerStyle = .large
    saveButton.configuration = config
    saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
    saveButton.isEnabled = false
    saveButton.accessibilityIdentifier = "shared-task-save"

    cancelButton.configuration = .plain()
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

    let header = UIStackView(arrangedSubviews: [cancelButton, saveButton])
    header.axis = .horizontal
    header.alignment = .center
    header.distribution = .equalSpacing
    header.translatesAutoresizingMaskIntoConstraints = false

    let descriptionLabel = UILabel()
    descriptionLabel.text = "Description (optional)"
    descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
    let stack = UIStackView(arrangedSubviews: [projectButton, titleField,
      descriptionLabel, descriptionField, statusLabel, preview])
    stack.axis = .vertical
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false

    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.keyboardDismissMode = .interactive
    scroll.addSubview(stack)
    view.addSubview(header)
    view.addSubview(scroll)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])

    let keyboardToolbar = UIToolbar()
    keyboardToolbar.sizeToFit()
    keyboardToolbar.items = [
      UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard)),
    ]
    descriptionField.inputAccessoryView = keyboardToolbar
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === titleField {
      descriptionField.becomeFirstResponder()
    } else {
      textField.resignFirstResponder()
    }
    return true
  }

  @objc private func dismissKeyboard() {
    view.endEditing(true)
  }

  private func loadSharedImage() {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
      let identifier = provider.registeredTypeIdentifiers.first(where: {
        UTType($0)?.conforms(to: .image) == true
      }), let type = UTType(identifier),
      let mime = type.preferredMIMEType, ["image/jpeg", "image/png", "image/heic"].contains(mime)
    else {
      statusLabel.text = "This share does not contain a supported JPEG, PNG, or HEIC photo."
      statusLabel.isHidden = false
      return
    }
    imageName = provider.suggestedName ?? "Shared image"
    titleField.text = Self.taskTitle(for: imageName)
    mediaType = mime
    statusLabel.text = "Loading photo…"
    statusLabel.isHidden = false
    provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, error in
      Task { @MainActor in
        guard let self else { return }
        guard let data, let image = UIImage(data: data) else {
          self.statusLabel.text = error?.localizedDescription ?? "The shared photo could not be read."
          self.statusLabel.isHidden = false
          return
        }
        do {
          try SharedPhotoIntake.validateForShare(image: data, mediaType: mime)
          self.imageData = data
          self.preview.image = image
          self.statusLabel.text = self.projects.isEmpty
            ? "Open Build Chase once to load the available projects."
            : nil
          self.statusLabel.isHidden = !self.projects.isEmpty
          self.updateSaveState()
        } catch {
          self.statusLabel.text = error.localizedDescription
          self.statusLabel.isHidden = false
        }
      }
    }
  }

  @objc private func chooseProject() {
    guard !projects.isEmpty else { return }
    let alert = UIAlertController(title: "Choose a project", message: nil, preferredStyle: .actionSheet)
    for project in projects {
      alert.addAction(UIAlertAction(title: project.name, style: .default) { [weak self] _ in
        self?.selectedProject = project
        self?.updateProjectButton()
        self?.updateSaveState()
      })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController { popover.sourceView = projectButton; popover.sourceRect = projectButton.bounds }
    present(alert, animated: true)
  }

  private func updateProjectButton() {
    let title = selectedProject.map { "Project: \($0.name)  ▾" } ?? "Choose project"
    projectButton.setTitle(title, for: .normal)
  }

  private static func taskTitle(for imageName: String) -> String {
    let suggestedTitle = URL(fileURLWithPath: imageName)
      .deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return suggestedTitle.isEmpty || suggestedTitle == "Shared image"
      ? "Photo task"
      : String(suggestedTitle.prefix(500))
  }

  private func updateSaveState() {
    saveButton.isEnabled = imageData != nil && selectedProject != nil
      && !(titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @objc private func titleChanged() { updateSaveState() }

  @objc private func save() {
    guard let imageData, let selectedProject else { return }
    do {
      try SharedPhotoIntake.stage(
        image: imageData, projectID: selectedProject.id, title: titleField.text ?? "",
        description: descriptionField.text ?? "", displayName: imageName, mediaType: mediaType)
      extensionContext?.completeRequest(returningItems: nil)
    } catch {
      statusLabel.text = error.localizedDescription
      statusLabel.isHidden = false
    }
  }

  @objc private func cancel() {
    extensionContext?.cancelRequest(withError: NSError(domain: "SharedPhotoIntake", code: 2))
  }
}

private extension UIFont {
  func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
