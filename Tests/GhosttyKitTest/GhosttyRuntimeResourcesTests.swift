import Darwin
import Foundation
@testable import GhosttyTerminal
import Testing

struct GhosttyRuntimeResourcesTests {
    @Test
    func `runtime resource layout matches Ghostty exec expectations`() throws {
        let resources = try #require(GhosttyRuntimeResources.directoryURL)
        let terminfo = try #require(GhosttyRuntimeResources.terminfoDirectoryURL)
        let fileManager = FileManager.default

        #expect(fileManager.fileExists(
            atPath: resources
                .appendingPathComponent("shell-integration/zsh/ghostty-integration")
                .path
        ))
        #expect(fileManager.fileExists(
            atPath: terminfo.appendingPathComponent("78/xterm-ghostty").path
        ))
        #expect(
            resources.deletingLastPathComponent()
                .appendingPathComponent("terminfo")
                .standardizedFileURL
                == terminfo.standardizedFileURL
        )
    }

    /// The bundle ships into every host app, so it may hold only the files
    /// we wrote or vendored under MIT: upstream's bash and zsh integration is
    /// GPLv3 and came back once already (see Script/check-licenses.sh).
    @Test
    func `bundled shell integration is exactly the MIT set and carries no GPL text`() throws {
        let resources = try #require(GhosttyRuntimeResources.directoryURL)
        let integration = resources.appendingPathComponent("shell-integration")
        let enumerator = try #require(FileManager.default.enumerator(
            at: integration,
            includingPropertiesForKeys: [.isRegularFileKey]
        ))

        var files: [String] = []
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files.append(url.path.replacingOccurrences(of: integration.path + "/", with: ""))

            let text = try String(contentsOf: url, encoding: .utf8)
            // Split so the license name itself never appears in this tree.
            #expect(!text.localizedCaseInsensitiveContains("General Public " + "License"), "\(url.lastPathComponent)")
        }

        #expect(files.sorted() == [
            "bash/LICENSE-bash-preexec.md",
            "bash/bash-preexec.sh",
            "bash/ghostty.bash",
            "zsh/.zshenv",
            "zsh/ghostty-integration",
        ])
    }

    @Test(arguments: [
        (features: "cursor", expected: "\u{1B}[1 q\u{1B}[5 q"),
        (features: "cursor:steady", expected: "\u{1B}[2 q\u{1B}[6 q"),
    ])
    func `zsh vi keymaps select block and bar cursors`(
        features: String,
        expected: String
    ) throws {
        let resources = try #require(GhosttyRuntimeResources.directoryURL)
        let integration = resources
            .appendingPathComponent("shell-integration/zsh/ghostty-integration")

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-dfi",
            "-c",
            "source \"$GHOSTTY_INTEGRATION_PATH\"; "
                + "KEYMAP=vicmd; _ghostty_zle_cursor_shape; "
                + "KEYMAP=viins; _ghostty_zle_cursor_shape",
        ]
        process.environment = [
            "GHOSTTY_INTEGRATION_PATH": integration.path,
            "GHOSTTY_SHELL_FEATURES": features,
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        #expect(String(decoding: data, as: UTF8.self) == expected)
    }

    @Test
    func `configuration exports Ghostty resource root`() throws {
        let previous = getenv("GHOSTTY_RESOURCES_DIR").map { String(cString: $0) }
        defer {
            if let previous {
                setenv("GHOSTTY_RESOURCES_DIR", previous, 1)
            } else {
                unsetenv("GHOSTTY_RESOURCES_DIR")
            }
        }

        GhosttyRuntimeResources.configureEnvironment()

        let resources = try #require(GhosttyRuntimeResources.directoryURL)
        let exported = try #require(getenv("GHOSTTY_RESOURCES_DIR"))
        #expect(String(cString: exported) == resources.path)
    }
}
