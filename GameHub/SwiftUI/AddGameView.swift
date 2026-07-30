import SwiftUI

struct AddGameView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("TEST - Add Game View")
                .font(.largeTitle)
                .foregroundColor(.red)
            Button("Dismiss") { dismiss() }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.yellow)
    }
}
