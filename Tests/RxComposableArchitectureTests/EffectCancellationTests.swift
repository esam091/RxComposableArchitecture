import RxComposableArchitectureTestSupport
import RxSwift
import XCTest

@testable import RxComposableArchitecture

final class EffectCancellationTests: XCTestCase {
  let disposeBag = DisposeBag()

  override func setUp() {
    super.setUp()
    resetCancellables()
  }

  func testCancellation() {
    struct CancelToken: Hashable {}
    var values: [Int] = []

    let subject = PublishSubject<Int>()
    let effect =
      subject
      .cancellable(id: CancelToken())

    effect.subscribe(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    XCTAssertEqual(values, [])
    subject.onNext(1)
    XCTAssertEqual(values, [1])
    subject.onNext(2)
    XCTAssertEqual(values, [1, 2])

    Observable<Never>.cancel(id: CancelToken())
      .subscribe()
      .disposed(by: disposeBag)

    subject.onNext(3)
    XCTAssertEqual(values, [1, 2])
  }

  func testCancelInFlight() {
    struct CancelToken: Hashable {}
    var values: [Int] = []

    let subject = PublishSubject<Int>()
    subject
      .cancellable(id: CancelToken(), cancelInFlight: true)
      .subscribe(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    XCTAssertEqual(values, [])
    subject.onNext(1)
    XCTAssertEqual(values, [1])
    subject.onNext(2)
    XCTAssertEqual(values, [1, 2])

    subject
      .cancellable(id: CancelToken(), cancelInFlight: true)
      .subscribe(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    subject.onNext(3)
    XCTAssertEqual(values, [1, 2, 3])
    subject.onNext(4)
    XCTAssertEqual(values, [1, 2, 3, 4])
  }

  func testCancellationAfterDelay() {
    struct CancelToken: Hashable {}
    var value: Int?

    Observable.just(1)
      .delay(.milliseconds(500), scheduler: MainScheduler.instance)
      .cancellable(id: CancelToken())
      .subscribe(onNext: { value = $0 })
      .disposed(by: disposeBag)

    XCTAssertEqual(value, nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      _ = Observable<Never>.cancel(id: CancelToken())
        .subscribe()
        .disposed(by: self.disposeBag)
    }

    _ = XCTWaiter.wait(for: [self.expectation(description: "")], timeout: 0.1)

    XCTAssertEqual(value, nil)
  }

  func testCancellationAfterDelay_WithTestScheduler() {
    struct CancelToken: Hashable {}

    let scheduler = TestScheduler(initialClock: 0)

    var value: Int?

    Observable.just(1)
      .delay(.seconds(2), scheduler: scheduler)
      .cancellable(id: CancelToken())
      .subscribe(onNext: { value = $0 })
      .disposed(by: disposeBag)

    XCTAssertEqual(value, nil)

    scheduler.advance(by: .seconds(1))

    Observable<Never>.cancel(id: CancelToken())
      .subscribe()
      .disposed(by: disposeBag)

    scheduler.advance(to: 1000)

    XCTAssertEqual(value, nil)
  }

  func testCancellablesCleanUp_OnComplete() {
    Observable.just(1)
      .cancellable(id: 1)
      .subscribe()
      .disposed(by: disposeBag)

    XCTAssertTrue(cancellationCancellables.isEmpty)
  }

  func testCancellablesCleanUp_OnCancel() {
    let scheduler = TestScheduler(initialClock: 0)

    Observable.just(1)
      .delay(.seconds(1), scheduler: scheduler)
      .cancellable(id: 1)
      .subscribe()
      .disposed(by: disposeBag)

    Observable<Never>.cancel(id: 1)
      .subscribe()
      .disposed(by: disposeBag)

    XCTAssertTrue(cancellationCancellables.isEmpty)
  }

  func testDoubleCancellation() {
    struct CancelToken: Hashable {}
    var values: [Int] = []

    let subject = PublishSubject<Int>()
    let effect =
      subject
      .cancellable(id: CancelToken())
      .cancellable(id: CancelToken())

    effect
      .subscribe(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    XCTAssertEqual(values, [])
    subject.onNext(1)
    XCTAssertEqual(values, [1])

    _ = Observable<Never>.cancel(id: CancelToken())
      .subscribe()
      .disposed(by: disposeBag)

    subject.onNext(2)
    XCTAssertEqual(values, [1])
  }

  func testCompleteBeforeCancellation() {
    struct CancelToken: Hashable {}
    var values: [Int] = []

    let subject = PublishSubject<Int>()
    let effect =
      subject
      .cancellable(id: CancelToken())

    effect
      .subscribe(onNext: { values.append($0) })
      .disposed(by: disposeBag)

    subject.onNext(1)
    XCTAssertEqual(values, [1])

    subject.onCompleted()
    XCTAssertEqual(values, [1])

    Observable<Never>.cancel(id: CancelToken())
      .subscribe()
      .disposed(by: disposeBag)

    XCTAssertEqual(values, [1])
  }

  func testConcurrentCancels() {
    let queues: [SchedulerType] = [
      MainScheduler.instance,
      ConcurrentDispatchQueueScheduler(qos: .background),
      ConcurrentDispatchQueueScheduler(qos: .default),
      ConcurrentDispatchQueueScheduler(qos: .unspecified),
      ConcurrentDispatchQueueScheduler(qos: .userInitiated),
      ConcurrentDispatchQueueScheduler(qos: .userInteractive),
      ConcurrentDispatchQueueScheduler(qos: .utility),
    ]

    let effect = Observable.merge(
      (1...10000).map { idx -> Observable<Int> in
        let id = idx % 10

        return Observable.merge(
          Observable.just(idx)
            .delay(
              .microseconds(.random(in: 1...100)), scheduler: queues.randomElement()!
            )
            .cancellable(id: id),

          Observable.just(())
            .delay(
              .microseconds(.random(in: 1...100)), scheduler: queues.randomElement()!
            )
            .flatMap { Observable.cancel(id: id) }
        )
      }
    )

    let expectation = self.expectation(description: "wait")

    effect.subscribe(onCompleted: { expectation.fulfill() })
      .disposed(by: disposeBag)

    wait(for: [expectation], timeout: 999)

    XCTAssertTrue(cancellationCancellables.isEmpty)
  }
}

func resetCancellables() {
  for (id, _) in cancellationCancellables {
    cancellationCancellables[id] = [:]
  }
  cancellationCancellables = [:]
}
