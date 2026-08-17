/// Typed result type — use instead of throwing exceptions from service calls.
///
/// Every network call should return `Result<T>`. Callers can pattern-match
/// with [when] or check [isSuccess]/[isFailure] and read [dataOrNull]/[errorOrNull].
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get dataOrNull => switch (this) {
        Success<T> s => s.data,
        Failure<T> _ => null,
      };

  AppError? get errorOrNull => switch (this) {
        Success<T> _ => null,
        Failure<T> f => f.error,
      };

  R when<R>({
    required R Function(T data) success,
    required R Function(AppError error) failure,
  }) =>
      switch (this) {
        Success<T> s => success(s.data),
        Failure<T> f => failure(f.error),
      };
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

final class Failure<T> extends Result<T> {
  final AppError error;
  const Failure(this.error);
}

// ─── Error type ──────────────────────────────────────────────────────────────

enum AppErrorKind { offline, timeout, serverError, unknown }

class AppError {
  final AppErrorKind kind;
  final String message;
  final int? statusCode;

  const AppError({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  factory AppError.offline() => const AppError(
        kind: AppErrorKind.offline,
        message: "You're offline. Showing cached data.",
      );

  factory AppError.timeout() => const AppError(
        kind: AppErrorKind.timeout,
        message: 'Request timed out. Check your connection and try again.',
      );

  factory AppError.server(int statusCode, String body) => AppError(
        kind: AppErrorKind.serverError,
        message: 'Server error ($statusCode): $body',
        statusCode: statusCode,
      );

  factory AppError.unknown(Object e) => AppError(
        kind: AppErrorKind.unknown,
        message: e.toString(),
      );

  @override
  String toString() => 'AppError(${kind.name}: $message)';
}
