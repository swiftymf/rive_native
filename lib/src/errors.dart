/// A base class for all Rive errors.
class RiveError extends Error {
  RiveError(this.message);

  /// An error thrown when a pointer is invalid.
  RiveError.nullNativePointer()
      : message = "Null Native Pointer, object may be disposed";

  final String message;

  @override
  String toString() => "RiveError: $message";
}
