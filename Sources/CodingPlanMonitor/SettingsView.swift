import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: MonitorViewModel

    var body: some View {
        Form {
            Section("GLM Coding（智谱）") {
                SecureField("API Key", text: $vm.glmAPIKey)
                    .textFieldStyle(.roundedBorder)
                Picker("平台", selection: $vm.glmPlatform) {
                    Text("国内（bigmodel.cn）").tag("bigmodel")
                    Text("国际（z.ai）").tag("zai")
                }
                Link("获取 API Key →", destination: URL(string: "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys")!)
                    .font(.caption)
            }
            Section("Kimi Coding（月之暗面）") {
                SecureField("API Key", text: $vm.kimiAPIKey)
                    .textFieldStyle(.roundedBorder)
                Link("获取 API Key →", destination: URL(string: "https://platform.moonshot.cn/console/api-keys")!)
                    .font(.caption)
            }
            Section("刷新") {
                Stepper("自动刷新间隔：\(vm.refreshMinutes) 分钟", value: $vm.refreshMinutes, in: 1...60)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 400)
        .onChange(of: vm.glmAPIKey) { Task { await vm.refresh() } }
        .onChange(of: vm.kimiAPIKey) { Task { await vm.refresh() } }
        .onChange(of: vm.glmPlatform) { Task { await vm.refresh() } }
    }
}
