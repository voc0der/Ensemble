class MissingClientCertificateException implements Exception {
  final String message;
  MissingClientCertificateException([this.message = 'A client certificate was expected but not sent.']);

  @override
  String toString() => 'MissingClientCertificateException: $message';
}
