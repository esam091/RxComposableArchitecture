import Foundation
import RxCocoa
import RxSwift

extension ObservableType {
    public static func fireAndForget(_ work: @escaping () -> Void) -> Observable<Element> {
        return Observable<Element>.deferred { () -> Observable<Self.Element> in
            work()
            return .empty()
        }
    }
}

extension SharedSequence {
    public static func fireAndForget(_ work: @escaping () -> Void) -> SharedSequence<SharingStrategy, Element> {
        return SharedSequence.deferred { () -> SharedSequence<SharingStrategy, Element> in
            work()
            return .empty()
        }
    }
}

extension ObservableType where Element == Never {
    public func fireAndForget<T>() -> Observable<T> {
        func absurd<A>(_: Never) -> A {}
        return map(absurd)
    }
}

extension SharedSequence where Element == Never {
    public func fireAndForget<T>() -> SharedSequence<SharingStrategy, T> {
        return asObservable().fireAndForget().asSharedSequence(onErrorDriveWith: .empty())
    }
}
