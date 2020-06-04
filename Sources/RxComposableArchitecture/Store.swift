import CasePaths
import Foundation
import RxCocoa
import RxSwift

public final class Store<State, Action> {
    public private(set) var state: State {
        didSet {
            relay.accept(state)
        }
    }

    private var isSending = false
    private var synchronousActionsToSend: [Action] = []

    private let reducer: (inout State, Action) -> Driver<Action>

    private let disposeBag = DisposeBag()
    private let relay: BehaviorRelay<State>

    private init(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Driver<Action>
    ) {
        self.reducer = reducer
        state = initialState
        relay = BehaviorRelay(value: state)
    }

    public convenience init<Environment>(
        initialState: State,
        reducer: Reducer<State, Action, Environment>,
        environment: Environment
    ) {
        self.init(
            initialState: initialState,
            reducer: { reducer.callAsFunction(&$0, $1, environment) }
        )
    }

    public func send(_ action: Action) {
        synchronousActionsToSend.append(action)

        while !synchronousActionsToSend.isEmpty {
            let action = synchronousActionsToSend.removeFirst()
            if isSending {
                assertionFailure(
                    """
                    The store was sent an action recursively. This can occur when you run an effect directly \
                    in the reducer, rather than returning it from the reducer. Check the stack (⌘7) to find \
                    frames corresponding to one of your reducers. That code should be refactored to not invoke \
                    the effect directly.
                    """
                )
            }
            isSending = true
            let effect = reducer(&state, action)
            isSending = false

            var isProcessingEffects = true
            effect.drive(
                onNext: { [weak self] action in
                    if isProcessingEffects {
                        self?.synchronousActionsToSend.append(action)
                    } else {
                        self?.send(action)
                    }
                }
            ).disposed(by: disposeBag)

            isProcessingEffects = false
        }
    }

    public func scope<LocalState, LocalAction>(
        state toLocalState: @escaping (State) -> LocalState,
        action fromLocalAction: @escaping (LocalAction) -> Action
    ) -> Store<LocalState, LocalAction> {
        let localStore = Store<LocalState, LocalAction>(
            initialState: toLocalState(state),
            reducer: { localState, localAction in
                self.send(fromLocalAction(localAction))
                localState = toLocalState(self.state)
                return .empty()
            }
        )

        relay
            .asDriver()
            .drive(onNext: { [weak localStore] newValue in
                localStore?.state = toLocalState(newValue)
            })
            .disposed(by: localStore.disposeBag)

        return localStore
    }

    public func scope<LocalState>(
        state toLocalState: @escaping (State) -> LocalState
    ) -> Store<LocalState, Action> {
        scope(state: toLocalState, action: { $0 })
    }

    public func subscribe<LocalState>(
        _ toLocalState: @escaping (State) -> LocalState,
        removeDuplicates isDuplicate: @escaping (LocalState, LocalState) -> Bool
    ) -> Driver<LocalState> {
        return relay.asDriver().map(toLocalState).distinctUntilChanged(isDuplicate)
    }

    public func subscribe<LocalState: Equatable>(
        _ toLocalState: @escaping (State) -> LocalState
    ) -> Driver<LocalState> {
        return relay.asDriver().map(toLocalState).distinctUntilChanged()
    }
}
