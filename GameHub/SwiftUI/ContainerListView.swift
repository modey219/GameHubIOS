import SwiftUI

struct ContainerListView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @State private var showNewContainer = false

    var body: some View {
        NavigationStack {
            List {
                if containerManager.containers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "shippingbox").font(.system(size: 50)).foregroundColor(.gray)
                        Text("No Containers").font(.title3)
                        Text("Create a container to run Windows applications")
                            .font(.subheadline).foregroundColor(.secondary)
                        Button("Create Container") { showNewContainer = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(containerManager.containers) { container in
                        ContainerRow(container: container)
                    }
                    .onDelete(perform: deleteContainers)
                }
            }
            .navigationTitle("Containers")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewContainer = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNewContainer) { NewContainerView() }
        }
    }

    private func deleteContainers(at offsets: IndexSet) {
        for index in offsets {
            containerManager.deleteContainer(containerManager.containers[index])
        }
    }
}

struct ContainerRow: View {
    let container: ContainerManager.Container
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name).font(.headline)
                if container.executablePath.isEmpty {
                    Text("No executable set").font(.caption).foregroundColor(.red)
                } else {
                    Text(container.executablePath).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                HStack {
                    Label(container.graphicsConfig.renderer.uppercased(), systemImage: "cpu")
                        .font(.caption2).foregroundColor(.blue)
                    if container.graphicsConfig.useDXVK {
                        Text("DXVK").font(.caption2).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2)).cornerRadius(4)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NewContainerView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @Environment(\.dismiss) var dismiss
    @State private var containerName = ""
    @State private var selectedRenderer = "vulkan"
    @State private var useDXVK = true
    @State private var useVKD3D = true
    @State private var maxFPS = 60

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Container Name")) {
                    TextField("My Container", text: $containerName)
                }
                Section(header: Text("Graphics")) {
                    Picker("Renderer", selection: $selectedRenderer) {
                        Text("Vulkan (MoltenVK)").tag("vulkan")
                        Text("OpenGL ES").tag("opengl")
                        Text("DXVK (DX11)").tag("dxvk")
                        Text("VKD3D (DX12)").tag("vkd3d")
                    }
                    Toggle("Use DXVK", isOn: $useDXVK)
                    Toggle("Use VKD3D", isOn: $useVKD3D)
                    Stepper("Max FPS: \(maxFPS)", value: $maxFPS, in: 30...120, step: 10)
                }
                Section {
                    Button(action: createContainer) {
                        Text("Create Container").frame(maxWidth: .infinity)
                    }
                    .disabled(containerName.isEmpty)
                }
            }
            .navigationTitle("New Container")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createContainer() {
        let _ = containerManager.createContainer(name: containerName, executablePath: "")
        dismiss()
    }
}
