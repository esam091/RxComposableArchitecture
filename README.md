# RxComposableArchitecture

This a RxSwift implementation of [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) and is optimized for UIKit.

Some notable differences compared to the original:
1. It uses `Driver` instead of `Effect` type so that actions from side effects will always be delivered to the main thread.
2. Has no `ViewStore`. ViewStore was created for ergonomic reasons in SwiftUI and since SwiftUI is not supported, there's no reason for it to exist.
3. To subscribe to state updates, you can use the `subscribe` method
```swift
class Store<State, Action> {
  public func subscribe<LocalState: Equatable>(
    _ toLocalState: @escaping (State) -> LocalState
  ) -> Driver<LocalState>
}

struct Person {
  var name: String
}

store
  .subscribe(\Person.name)
  .drive(label.rx.text)
  .disposed(by: disposeBag)
```

## Contributing
This library is still in active development, so I happily accept feedbacks, issues and code contributions.
