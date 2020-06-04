import Foundation
import RxSwift
import XCTest

@testable import RxComposableArchitecture

public final class TestStore<State, LocalState, Action: Equatable, LocalAction, Environment> {
  private var environment: Environment
  private let fromLocalAction: (LocalAction) -> Action
  private let reducer: Reducer<State, Action, Environment>
  private var state: State
  private let toLocalState: (State) -> LocalState

  private init(
    initialState: State,
    reducer: Reducer<State, Action, Environment>,
    environment: Environment,
    state toLocalState: @escaping (State) -> LocalState,
    action fromLocalAction: @escaping (LocalAction) -> Action
  ) {
    state = initialState
    self.reducer = reducer
    self.environment = environment
    self.toLocalState = toLocalState
    self.fromLocalAction = fromLocalAction
  }
}

extension TestStore where State == LocalState, Action == LocalAction {
  /// Initializes a test store from an initial state, a reducer, and an initial environment.
  ///
  /// - Parameters:
  ///   - initialState: The state to start the test from.
  ///   - reducer: A reducer.
  ///   - environment: The environment to start the test from.
  public convenience init(
    initialState: State,
    reducer: Reducer<State, Action, Environment>,
    environment: Environment
  ) {
    self.init(
      initialState: initialState,
      reducer: reducer,
      environment: environment,
      state: { $0 },
      action: { $0 }
    )
  }
}

extension TestStore where LocalState: Equatable {
  /// Asserts against a script of actions.
  public func assert(
    _ steps: Step...,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    var receivedActions: [Action] = []

    var cancellables = Set<UUID>()
    let disposeBag = DisposeBag()

    func runReducer(state: inout State, action: Action) {
      let effect = reducer.callAsFunction(&state, action, environment)
      var isComplete = false

      let uuid = UUID()

      effect.drive(
        onNext: {
          receivedActions.append($0)
        },
        onCompleted: {
          isComplete = true

          cancellables.remove(uuid)
        }
      ).disposed(by: disposeBag)

      if !isComplete {
        cancellables.insert(uuid)
      }
    }

    for step in steps {
      var expectedState = toLocalState(state)

      switch step.type {
      case let .send(action, update):
        if !receivedActions.isEmpty {
          XCTFail(
            """
            Must handle \(receivedActions.count) received \
            action\(receivedActions.count == 1 ? "" : "s") before sending an action: …

            Unhandled actions: \(debugOutput(receivedActions))
            """,
            file: step.file, line: step.line
          )
        }
        runReducer(state: &state, action: fromLocalAction(action))
        update(&expectedState)

      case let .receive(expectedAction, update):
        guard !receivedActions.isEmpty else {
          XCTFail(
            """
            Expected to receive an action, but received none.
            """,
            file: step.file,
            line: step.line
          )
          break
        }
        let receivedAction = receivedActions.removeFirst()
        if expectedAction != receivedAction {
          let diff =
            debugDiff(expectedAction, receivedAction)
            .map { ": …\n\n\($0.indent(by: 4))\n\n(Expected: −, Actual: +)" }
            ?? ""
          XCTFail(
            """
            Received unexpected action\(diff)
            """,
            file: step.file,
            line: step.line
          )
        }
        runReducer(state: &state, action: receivedAction)
        update(&expectedState)

      case let .environment(work):
        if !receivedActions.isEmpty {
          XCTFail(
            """
            Must handle \(receivedActions.count) received \
            action\(receivedActions.count == 1 ? "" : "s") before performing this work: …

            Unhandled actions: \(debugOutput(receivedActions))
            """,
            file: step.file, line: step.line
          )
        }

        work(&environment)
      }

      let actualState = toLocalState(state)
      if expectedState != actualState {
        let diff =
          debugDiff(expectedState, actualState)
          .map { ": …\n\n\($0.indent(by: 4))\n\n(Expected: −, Actual: +)" }
          ?? ""
        XCTFail(
          """
          State change does not match expectation\(diff)
          """,
          file: step.file,
          line: step.line
        )
      }
    }

    if !receivedActions.isEmpty {
      XCTFail(
        """
        Received \(receivedActions.count) unexpected \
        action\(receivedActions.count == 1 ? "" : "s"): …

        Unhandled actions: \(debugOutput(receivedActions))
        """,
        file: file,
        line: line
      )
    }
    if !cancellables.isEmpty {
      XCTFail(
        """
        Some effects are still running. All effects must complete by the end of the assertion.

        This can happen for a few reasons:

        • If you are using a scheduler in your effect, then make sure that you wait enough time \
        for the effect to finish. If you are using a test scheduler, then make sure you advance \
        the scheduler so that the effects complete.

        • If you are using long-living effects (for example timers, notifications, etc.), then \
        ensure those effects are completed by returning an `Effect.cancel` effect from a \
        particular action in your reducer, and sending that action in the test.
        """,
        file: file,
        line: line
      )
    }
  }
}

extension TestStore {
  /// Scopes a store to assert against more local state and actions.
  ///
  /// - Parameters:
  ///   - toLocalState: A function that transforms the reducer's state into more local state. This
  ///     state will be asserted against as it is mutated by the reducer. Useful for testing view
  ///     store state transformations.
  ///   - fromLocalAction: A function that wraps a more local action in the reducer's action.
  ///     Local actions can be "sent" to the store, while any reducer action may be received.
  ///     Useful for testing view store action transformations.
  public func scope<S, A>(
    state toLocalState: @escaping (LocalState) -> S,
    action fromLocalAction: @escaping (A) -> LocalAction
  ) -> TestStore<State, S, Action, A, Environment> {
    .init(
      initialState: state,
      reducer: reducer,
      environment: environment,
      state: { toLocalState(self.toLocalState($0)) },
      action: { self.fromLocalAction(fromLocalAction($0)) }
    )
  }

  /// Scopes a store to assert against more local state.
  ///
  /// - Parameter toLocalState: A function that transforms the reducer's state into more local
  ///   state. This state will be asserted against as it is mutated by the reducer. Useful for
  ///   testing view store state transformations.
  public func scope<S>(
    state toLocalState: @escaping (LocalState) -> S
  ) -> TestStore<State, S, Action, LocalAction, Environment> {
    scope(state: toLocalState, action: { $0 })
  }

  /// A single step of a `TestStore` assertion.
  public struct Step {
    fileprivate let type: StepType
    fileprivate let file: StaticString
    fileprivate let line: UInt

    private init(
      _ type: StepType,
      file: StaticString = #file,
      line: UInt = #line
    ) {
      self.type = type
      self.file = file
      self.line = line
    }

    /// A step that describes an action sent to a store and asserts against how the store's state
    /// is expected to change.
    ///
    /// - Parameters:
    ///   - action: An action to send to the test store.
    ///   - update: A function that describes how the test store's state is expected to change.
    /// - Returns: A step that describes an action sent to a store and asserts against how the
    ///   store's state is expected to change.
    public static func send(
      _ action: LocalAction,
      file: StaticString = #file,
      line: UInt = #line,
      _ update: @escaping (inout LocalState) -> Void = { _ in }
    ) -> Step {
      Step(.send(action, update), file: file, line: line)
    }

    /// A step that describes an action received by an effect and asserts against how the store's
    /// state is expected to change.
    ///
    /// - Parameters:
    ///   - action: An action the test store should receive by evaluating an effect.
    ///   - update: A function that describes how the test store's state is expected to change.
    /// - Returns: A step that describes an action received by an effect and asserts against how
    ///   the store's state is expected to change.
    public static func receive(
      _ action: Action,
      file: StaticString = #file,
      line: UInt = #line,
      _ update: @escaping (inout LocalState) -> Void = { _ in }
    ) -> Step {
      Step(.receive(action, update), file: file, line: line)
    }

    /// A step that updates a test store's environment.
    ///
    /// - Parameter update: A function that updates the test store's environment for subsequent
    ///   steps.
    /// - Returns: A step that updates a test store's environment.
    public static func environment(
      file: StaticString = #file,
      line: UInt = #line,
      _ update: @escaping (inout Environment) -> Void
    ) -> Step {
      Step(.environment(update), file: file, line: line)
    }

    /// A step that captures some work to be done between assertions
    ///
    /// - Parameter work: A function that is called between steps.
    /// - Returns: A step that captures some work to be done between assertions.
    public static func `do`(
      file: StaticString = #file,
      line: UInt = #line,
      _ work: @escaping () -> Void
    ) -> Step {
      environment(file: file, line: line) { _ in work() }
    }

    fileprivate enum StepType {
      case send(LocalAction, (inout LocalState) -> Void)
      case receive(Action, (inout LocalState) -> Void)
      case environment((inout Environment) -> Void)
    }
  }
}
