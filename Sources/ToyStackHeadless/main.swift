import Engine
import Foundation

guard let options: HeadlessOptions = parseArguments() else { usage() }

MainActor.assumeIsolated {
    runScene(options)
}
