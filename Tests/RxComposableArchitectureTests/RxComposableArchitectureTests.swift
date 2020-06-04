import RxCocoa
import RxComposableArchitecture
import RxComposableArchitectureTestSupport
import XCTest

class RxComposableArchitectureTests: XCTestCase {
  func testEmptyEffect_doesNotNeedAssertion() {
    enum Action: Equatable {
      case doSomething
      case receiveSomething
      case doEmptyEffect
    }

    let reducer = Reducer<Int, Action, Void> { state, action, _ in
      switch action {
      case .doSomething:
        state += 1

        return .just(.receiveSomething)

      case .doEmptyEffect:
        state += 2

        return .empty()
      default: return .empty()
      }
    }

    let store = TestStore(initialState: 0, reducer: reducer, environment: ())

    store.assert(
      .send(.doSomething) {
        $0 = 1
      },
      .receive(.receiveSomething),
      .send(.doEmptyEffect) {
        $0 = 3
      }
    )
  }

  func testAsyncEffectWithWaiter() {
    enum Action: Equatable {
      case doSomething
      case receiveSomething
      case doEmptyEffect
    }

    let reducer = Reducer<Int, Action, Void> { state, action, _ in
      switch action {
      case .doSomething:
        state += 1

        return Driver.just(.receiveSomething).delay(.milliseconds(10))

      case .doEmptyEffect:
        state += 2

        return .empty()
      default: return .empty()
      }
    }

    let waiter = XCTWaiter()
    let expectation = XCTestExpectation(description: "async effect done")

    let store = TestStore(initialState: 0, reducer: reducer, environment: ())

    store.assert(
      .send(.doSomething) {
        $0 = 1
      },
      .do {
        waiter.wait(for: [expectation], timeout: 0.02)
      },
      .receive(.receiveSomething)
    )
  }
}
