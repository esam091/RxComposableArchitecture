import CasePaths
import Foundation
import RxCocoa

public struct Reducer<State, Action, Environment> {
    private let reducer: (inout State, Action, Environment) -> Driver<Action>

    public init(_ reducer: @escaping (inout State, Action, Environment) -> Driver<Action>) {
        self.reducer = reducer
    }

    public static var empty: Reducer {
        Self { _, _, _ in .empty() }
    }

    public static func combine(_ reducers: Reducer...) -> Reducer {
        .combine(reducers)
    }

    public static func combine(_ reducers: [Reducer]) -> Reducer {
        Self { value, action, environment in
            .merge(reducers.map { $0.reducer(&value, action, environment) })
        }
    }

    public func pullback<GlobalState, GlobalAction, GlobalEnvironment>(
        state toLocalState: WritableKeyPath<GlobalState, State>,
        action toLocalAction: CasePath<GlobalAction, Action>,
        environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment
    ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
        .init { globalState, globalAction, globalEnvironment in
            guard let localAction = toLocalAction.extract(from: globalAction) else { return .empty() }
            return self.reducer(
                &globalState[keyPath: toLocalState],
                localAction,
                toLocalEnvironment(globalEnvironment)
            )
            .map(toLocalAction.embed)
        }
    }

    public var optional: Reducer<State?, Action, Environment> {
        .init { state, action, environment in
            guard state != nil else { return .empty() }
            return self.reducer(&state!, action, environment)
        }
    }

    public func forEach<GlobalState, GlobalAction, GlobalEnvironment>(
        state toLocalState: WritableKeyPath<GlobalState, [State]>,
        action toLocalAction: CasePath<GlobalAction, (Int, Action)>,
        environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment
    ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
        .init { globalState, globalAction, globalEnvironment in
            guard let (index, localAction) = toLocalAction.extract(from: globalAction) else {
                return .empty()
            }
            // NB: This does not need to be a fatal error because of the index subscript that follows it.
            assert(
                index < globalState[keyPath: toLocalState].endIndex,
                """
                Index out of range. This can happen when a reducer that can remove the last element from \
                an array is then combined with a "forEach" from that array. To avoid this and other \
                index-related gotchas, combine \
                your reducers so that the "forEach" comes before any reducer that can remove elements from \
                its array.
                """
            )
            return self.reducer(
                &globalState[keyPath: toLocalState][index],
                localAction,
                toLocalEnvironment(globalEnvironment)
            )
            .map { toLocalAction.embed((index, $0)) }
        }
    }

    public func forEach<GlobalState, GlobalAction, GlobalEnvironment, Key>(
        state toLocalState: WritableKeyPath<GlobalState, [Key: State]>,
        action toLocalAction: CasePath<GlobalAction, (Key, Action)>,
        environment toLocalEnvironment: @escaping (GlobalEnvironment) -> Environment
    ) -> Reducer<GlobalState, GlobalAction, GlobalEnvironment> {
        .init { globalState, globalAction, globalEnvironment in
            guard let (key, localAction) = toLocalAction.extract(from: globalAction) else { return .empty() }
            return self.optional
                .reducer(
                    &globalState[keyPath: toLocalState][key],
                    localAction,
                    toLocalEnvironment(globalEnvironment)
                )
                .map { toLocalAction.embed((key, $0)) }
        }
    }

    public func callAsFunction(
        _ state: inout State,
        _ action: Action,
        _ environment: Environment
    ) -> Driver<Action> {
        reducer(&state, action, environment)
    }

    public func combined(with other: Reducer) -> Reducer {
        .combine(self, other)
    }

    /// Runs the reducer.
    ///
    /// - Parameters:
    ///   - state: Mutable state.
    ///   - action: An action.
    ///   - environment: An environment.
    ///   - debug: any additional action when executing reducer
    /// - Returns: An effect that can emit zero or more actions.
    public func run(
        _ state: inout State,
        _ action: Action,
        _ environment: Environment,
        _ debug: (State) -> Void = { _ in }
    ) -> Driver<Action> {
        let reducer = self.reducer(&state, action, environment)
        debug(state)

        return reducer
    }
}

extension Reducer where Environment == Void {
    public func callAsFunction(
        _ state: inout State,
        _ action: Action
    ) -> Driver<Action> {
        callAsFunction(&state, action, ())
    }
}
