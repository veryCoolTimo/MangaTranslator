import SwiftUI
import UniformTypeIdentifiers

struct ImagePicker: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MangaTranslatorViewModel
    
    var body: some View {
        VStack {
            Text("Выберите изображения")
                .font(.headline)
                .padding()
            
            SelectFileButton(viewModel: viewModel, dismiss: dismiss)
                .padding()
        }
    }
}

struct SelectFileButton: View {
    let viewModel: MangaTranslatorViewModel
    let dismiss: DismissAction
    
    var body: some View {
        Button("Выбрать файлы") {
            selectFiles()
        }
        .buttonStyle(.borderedProminent)
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    if let image = NSImage(contentsOf: url) {
                        Task { @MainActor in
                            viewModel.addPage(image: image)
                        }
                    }
                }
                Task { @MainActor in
                    dismiss()
                }
            }
        }
    }
} 