import Foundation
import RxCocoa
import RxSwift

extension ObservableType {
    public func cancellable(id: AnyHashable, cancelInFlight: Bool = false) -> Observable<Element> {
        return .deferred { () -> Observable<Element> in
            let subject = PublishSubject<Element>()
            let uuid = UUID()

            var isCleaningUp = false

            cancellablesLock.sync {
                if cancelInFlight {
                    cancellationCancellables[id]?.forEach { _, cancellable in cancellable.dispose() }
                    cancellationCancellables[id] = nil
                }

                let cancellable = self.asObservable().bind(to: subject)

                cancellationCancellables[id] = cancellationCancellables[id] ?? [:]
                cancellationCancellables[id]?[uuid] = Disposables.create {
                    cancellable.dispose()
                    if !isCleaningUp {
                        subject.onCompleted()
                    }
                }
            }

            func cleanup() {
                isCleaningUp = true
                cancellablesLock.sync {
                    cancellationCancellables[id]?[uuid] = nil
                    if cancellationCancellables[id]?.isEmpty == true {
                        cancellationCancellables[id] = nil
                    }
                }
            }

            return subject.do(
                onCompleted: cleanup,
                onDispose: cleanup
            )
        }
    }

    public static func cancel(id: AnyHashable) -> Observable<Element> {
        .fireAndForget {
            cancellablesLock.sync {
                cancellationCancellables[id]?.forEach { _, cancellable in cancellable.dispose() }
                cancellationCancellables[id] = nil
            }
        }
    }
}

extension SharedSequence {
    public func cancellable(id: AnyHashable, cancelInFlight: Bool = false) -> SharedSequence {
        return asObservable().cancellable(id: id, cancelInFlight: cancelInFlight)
            .asSharedSequence(onErrorDriveWith: .empty())
    }

    public static func cancel(id: AnyHashable) -> SharedSequence {
        return Observable.cancel(id: id).asSharedSequence(onErrorDriveWith: .empty())
    }
}

extension NSRecursiveLock {
    @inlinable
    internal func sync(work: () -> Void) {
        lock()
        defer { self.unlock() }
        work()
    }
}

internal var cancellationCancellables: [AnyHashable: [UUID: Disposable]] = [:]
internal let cancellablesLock = NSRecursiveLock()
