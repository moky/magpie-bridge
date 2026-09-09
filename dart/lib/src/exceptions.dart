/// Exception thrown when a packet fails validation or cannot be parsed.
class ProtocolException implements Exception {
  final String message;

  const ProtocolException(this.message);

  @override
  String toString() => 'ProtocolException: $message';
}
