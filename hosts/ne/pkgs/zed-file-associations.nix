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
          guard CommandLine.arguments.count > 1,
                let bundle = Bundle(path: CommandLine.arguments[1]),
                bundle.bundleIdentifier == "dev.zed.Zed" else {
              fputs("Expected the managed Zed.app path before file extensions.\n", stderr)
              exit(1)
          }
          let app = bundle.bundleURL
          do {
              for ext in CommandLine.arguments.dropFirst(2) {
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
