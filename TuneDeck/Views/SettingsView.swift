import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.resolverURL) private var resolverURL = ""
    @AppStorage(SettingsKey.resolverToken) private var resolverToken = ""
    @AppStorage(SettingsKey.resolverProxy) private var resolverProxy = true

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://resolver.example.com", text: $resolverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Access token (optional)", text: $resolverToken)
                    Toggle("Stream audio through the server", isOn: $resolverProxy)

                    Button {
                        isTesting = true
                        Task {
                            testResult = await RemoteStreamResolver.check(baseURLText: resolverURL, token: resolverToken)
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(resolverURL.trimmed.isEmpty || isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Stream resolver")
                } footer: {
                    Text("YouTube increasingly blocks direct audio requests from apps. A resolver server you run (see server/README) fetches the audio for you. Streaming through the server keeps playback working when your phone and server have different IP addresses.")
                }

                Section("About") {
                    Text("TuneDeck is an unofficial client and is not affiliated with or endorsed by YouTube or Google. Search and radio use YouTube Music's private web API, which can change without notice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .miniPlayerInset()
    }
}
