import os.signpost
import RxCocoa

extension Reducer {
    /// Instruments the reducer with
    ///
    /// ⚠️ Only works on iOS 12 or newer
    ///
    /// [signposts](https://developer.apple.com/documentation/os/logging/recording_performance_data).
    /// Each invocation of the reducer will be measured by an interval, and the lifecycle of its
    /// effects will be measured with interval and event signposts.
    ///
    /// To use, build your app for Instruments (⌘I), create a blank instrument, and then use the "+"
    /// icon at top right to add the signpost instrument. Start recording your app (red button at top
    /// left) and then you should see timing information for every action sent to the store and every
    /// effect executed.
    ///
    /// Effect instrumentation can be particularly useful for inspecting the lifecycle of long-living
    /// effects. For example, if you start an effect (e.g. a location manager) in `onAppear` and
    /// forget to tear down the effect in `onDisappear`, it will clearly show in Instruments that the
    /// effect never completed.
    ///
    /// - Parameters:
    ///   - prefix: A string to print at the beginning of the formatted message for the signpost.
    ///   - log: An `OSLog` to use for signposts.
    /// - Returns: A reducer that has been enhanced with instrumentation.
    public func signpost(
        _ prefix: String = "",
        log: OSLog = OSLog(
            subsystem: "com.tokopedia.Tokopedia",
            category: "Reducer Instrumentation"
        )
    ) -> Self {
        if #available(iOS 12.0, *) {
            guard log.signpostsEnabled else { return self }

            // NB: Prevent rendering as "N/A" in Instruments
            let zeroWidthSpace = "\u{200B}"

            let prefix = prefix.isEmpty ? zeroWidthSpace : "[\(prefix)] "

            return Self { state, action, environment in
                var actionOutput: String!
                if log.signpostsEnabled {
                    actionOutput = debugCaseOutput(action)
                    os_signpost(.begin, log: log, name: "Action", "%s%s", prefix, actionOutput)
                }
                let effects = self.run(&state, action, environment)
                if log.signpostsEnabled {
                    os_signpost(.end, log: log, name: "Action")
                    return
                        effects
                        .effectSignpost(prefix, log: log, actionOutput: actionOutput)
                }
                return effects
            }
        } else {
            return self
        }
    }
}

extension Driver {
    @available(iOS 12.0, *)
    internal func effectSignpost(_ prefix: String, log: OSLog, actionOutput: String) -> Self {
        let sid = OSSignpostID(log: log)

        return `do`(
            onNext: { _ in
                os_signpost(.event, log: log, name: "Effect Output", "%sOutput from %s", prefix, actionOutput)
            },
            onCompleted: {
                os_signpost(.end, log: log, name: "Effect", signpostID: sid, "%sFinished", prefix)
            },
            onSubscribe: {
                os_signpost(.begin, log: log, name: "Effect", signpostID: sid, "%sStarting from %s", prefix, actionOutput)
            },
            onSubscribed: {
                os_signpost(.begin, log: log, name: "Effect", signpostID: sid, "%sStarted from %s", prefix, actionOutput)
            },
            onDispose: {
                os_signpost(.end, log: log, name: "Effect", signpostID: sid, "%sDisposed", prefix)
            }
        )
    }
}

private func debugCaseOutput(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .enum:
        guard let child = mirror.children.first else {
            let childOutput = "\(value)"
            return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
        }
        let childOutput = debugCaseOutput(child.value)
        return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
    case .tuple:
        return mirror.children.map { label, value in
            let childOutput = debugCaseOutput(value)
            return "\(label.map { "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
        }
        .joined(separator: ", ")
    default:
        return ""
    }
}