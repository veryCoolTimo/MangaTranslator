import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MangaTranslatorViewModel
    
    var body: some View {
        Form {
            Section(header: Text("Язык перевода")) {
                Picker("Язык перевода", selection: $viewModel.targetLanguage) {
                    Text("Русский").tag("Russian")
                    Text("Английский").tag("English")
                }
            }
        }
        .padding()
    }
} 