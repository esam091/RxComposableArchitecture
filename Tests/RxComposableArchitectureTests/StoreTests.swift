import Foundation
import RxCocoa
import RxComposableArchitecture
import RxSwift
import XCTest

final class StoreTests: XCTestCase {
  private let disposeBag = DisposeBag()

  func testScopedStoreReceivesUpdatesFromParent() {
    let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
      state += 1
      return .empty()
    }

    let parentStore = Store(initialState: 0, reducer: counterReducer, environment: ())
    let childStore = parentStore.scope(state: String.init)

    var values: [String] = []
    childStore.subscribe { $0 }
      .drive(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    XCTAssertEqual(values, ["0"])

    parentStore.send(())

    XCTAssertEqual(values, ["0", "1"])
  }

  func testParentStoreReceivesUpdatesFromChild() {
    let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
      state += 1
      return .empty()
    }

    let parentStore = Store(initialState: 0, reducer: counterReducer, environment: ())
    let childStore = parentStore.scope(state: String.init)

    var values: [Int] = []

    parentStore.subscribe { $0 }
      .drive(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    XCTAssertEqual(values, [0])

    childStore.send(())

    XCTAssertEqual(values, [0, 1])
  }

  // TODO: testScopeWithPublisherTransform

  func testScopeCallCount() {
    let counterReducer = Reducer<Int, Void, Void> { state, _, _ in state += 1
      return .empty()
    }

    var numCalls1 = 0
    _ = Store(initialState: 0, reducer: counterReducer, environment: ())
      .scope(state: { (count: Int) -> Int in
        numCalls1 += 1
        return count
      })

    XCTAssertEqual(numCalls1, 2)
  }

  func testScopeCallCount2() {
    let counterReducer = Reducer<Int, Void, Void> { state, _, _ in
      state += 1
      return .empty()
    }

    var numCalls1 = 0
    var numCalls2 = 0
    var numCalls3 = 0

    let store = Store(initialState: 0, reducer: counterReducer, environment: ())
      .scope(state: { (count: Int) -> Int in
        numCalls1 += 1
        return count
      })
      .scope(state: { (count: Int) -> Int in
        numCalls2 += 1
        return count
      })
      .scope(state: { (count: Int) -> Int in
        numCalls3 += 1
        return count
      })

    XCTAssertEqual(numCalls1, 2)
    XCTAssertEqual(numCalls2, 2)
    XCTAssertEqual(numCalls3, 2)

    store.send(())

    XCTAssertEqual(numCalls1, 4)
    XCTAssertEqual(numCalls2, 5)
    XCTAssertEqual(numCalls3, 6)

    store.send(())

    XCTAssertEqual(numCalls1, 6)
    XCTAssertEqual(numCalls2, 8)
    XCTAssertEqual(numCalls3, 10)

    store.send(())

    XCTAssertEqual(numCalls1, 8)
    XCTAssertEqual(numCalls2, 11)
    XCTAssertEqual(numCalls3, 14)
  }

  func testSynchronousEffectsSentAfterSinking() {
    enum Action {
      case tap
      case next1
      case next2
      case end
    }
    var values: [Int] = []
    let counterReducer = Reducer<Void, Action, Void> { _, action, _ in
      switch action {
      case .tap:
        return .merge(
          .just(.next1),
          .just(.next2),
          Driver.just(()).flatMap {
            values.append(1)
            return .empty()
          }
        )
      case .next1:
        return .merge(
          .just(.end),
          Driver.just(()).flatMap {
            values.append(2)
            return .empty()
          }
        )
      case .next2:
        return Driver.just(()).flatMap {
          values.append(3)

          return .empty()
        }

      case .end:
        return Driver.just(()).flatMap {
          values.append(4)

          return .empty()
        }
      }
    }

    let store = Store(initialState: (), reducer: counterReducer, environment: ())

    store.send(.tap)

    XCTAssertEqual(values, [1, 2, 3, 4])
  }

  func testLotsOfSynchronousActions() {
    enum Action { case incr, noop }
    let reducer = Reducer<Int, Action, ()> { state, action, _ in
      switch action {
      case .incr:
        state += 1
        return state >= 10000 ? Driver.just(.noop) : Driver.just(.incr)
      case .noop:
        return .empty()
      }
    }

    let store = Store(initialState: 0, reducer: reducer, environment: ())
    store.send(.incr)
    XCTAssertEqual(store.state, 10000)
  }
}
