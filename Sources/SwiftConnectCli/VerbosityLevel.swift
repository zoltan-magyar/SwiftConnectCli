import ArgumentParser

enum VerbosityLevel: String, EnumerableFlag {
    case info
    case debug
    case trace

    static func name(for value: VerbosityLevel) -> NameSpecification {
        switch value {
        case .info: return .customLong("oc-info")
        case .debug: return .customLong("oc-debug")
        case .trace: return .customLong("oc-trace")
        }
    }

    static func help(for value: VerbosityLevel) -> ArgumentHelp? {
        switch value {
        case .info: return "OpenConnect INFO level"
        case .debug: return "OpenConnect DEBUG level (default)"
        case .trace: return "OpenConnect TRACE level"
        }
    }

    var openConnectLevel: Int32 {
        switch self {
        case .info: return 0
        case .debug: return 1
        case .trace: return 2
        }
    }
}
