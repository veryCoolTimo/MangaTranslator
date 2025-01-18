//
//  ContentView.swift
//  MangaTranslator
//
//  Created by Тимофей Булаев on 17.01.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = MangaTranslatorViewModel()
    @State private var isShowingSettings = false
    @State private var isDropTargeted = false
    
    var body: some View {
        NavigationSplitView {
            VStack {
                if viewModel.mangaPages.isEmpty {
                    emptyStateView
                } else {
                    pageListView
                }
                
                if let progress = viewModel.exportProgress {
                    ProgressView(value: progress) {
                        Text("Экспорт страниц...")
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: selectFiles) {
                        Label("Add Pages", systemImage: "plus")
                    }
                    
                    Button(action: { isShowingSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                    
                    Button {
                        Task {
                            await viewModel.exportPages()
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.mangaPages.isEmpty || viewModel.isProcessing)
                    
                    Button(action: viewModel.clearPages) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(viewModel.mangaPages.isEmpty)
                }
            }
        } detail: {
            if let selectedPage = viewModel.selectedPage {
                ResultView(page: selectedPage)
            } else {
                Text("Выберите страницу для просмотра результата")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .navigationTitle("Manga Translator")
        .alert("Ошибка", isPresented: .constant(viewModel.currentError != nil)) {
            Button("OK") {
                viewModel.currentError = nil
            }
        } message: {
            if let error = viewModel.currentError {
                Text(error)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Drag and drop manga pages here")
                .font(.title2)
            
            Text("or")
                .foregroundStyle(.secondary)
            
            Button("Select Files") {
                selectFiles()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2), 
                       style: StrokeStyle(lineWidth: 2, dash: [10]))
                .padding()
        )
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            let group = DispatchGroup()
            
            for provider in providers {
                group.enter()
                Task {
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier),
                       let data = item as? Data,
                       let image = NSImage(data: data) {
                        await viewModel.addPage(image: image)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                isDropTargeted = false
            }
            return true
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let image = NSImage(contentsOf: url) {
                    Task { @MainActor in
                        viewModel.addPage(image: image)
                    }
                }
            }
        }
    }
    
    private var pageListView: some View {
        List(viewModel.mangaPages, selection: $viewModel.selectedPageId) { page in
            PageRow(page: page)
                .padding(.vertical, 5)
        }
    }
}

#Preview {
    ContentView()
} 