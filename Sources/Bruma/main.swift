import AppKit

let application = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.diagnose()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-check") {
    let path = CommandLine.arguments.count > index+1 ? CommandLine.arguments[index+1] : "build/render-check"
    do { try Diagnostics.renderChecks(directory: path) }
    catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else {
    MainActor.assumeIsolated {
        let delegate = BrumaApp()
        application.delegate = delegate
        application.run()
    }
}
