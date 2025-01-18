import SwiftUI

struct PageRow: View {
    let page: MangaPage
    @StateObject private var state = PagePreviewState()
    
    var preview: some View {
        VStack {
            PagePreview(page: page)
                .frame(height: 200)
            
            if state.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            if let error = state.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    var body: some View {
        preview
            .onAppear {
                state.startUpdating(from: page)
            }
            .onDisappear {
                state.stopUpdating()
            }
    }
} 
