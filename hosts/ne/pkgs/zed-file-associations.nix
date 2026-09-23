{
  runCommandCC,
  swift,
  writeText,
}:

runCommandCC "zed-file-associations"
  {
    nativeBuildInputs = [ swift ];
  }
  ''
    mkdir -p "$out/bin"
    swiftc ${writeText "zed-file-associations.swift" ''
      import AppKit
      import UniformTypeIdentifiers

      Task { @MainActor in
          guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed") else {
              fputs("Zed must be installed before setting file associations.\n", stderr)
              exit(1)
          }
          do {
              for ext in CommandLine.arguments.dropFirst() {
                  guard let type = UTType(filenameExtension: ext) else {
                      fputs("No content type for .\(ext)\n", stderr)
                      exit(1)
                  }
                  if NSWorkspace.shared.urlForApplication(toOpen: type) == app { continue }
                  try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
                  print(".\(ext) → Zed")
              }
              exit(0)
          } catch {
              fputs("Could not set Zed file associations: \(error)\n", stderr)
              exit(1)
          }
      }
      RunLoop.main.run()
    ''} -o "$out/bin/zed-file-associations"
  ''
