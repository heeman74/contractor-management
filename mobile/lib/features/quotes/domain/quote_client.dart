/// A client on the company's roster, as the quote flow needs them.
///
/// Only the fields required to choose one and show who was chosen — the CRM
/// record carries much more, and pulling it all in would couple the quote
/// screens to a shape they do not use.
class QuoteClient {
  const QuoteClient({
    required this.userId,
    required this.email,
    this.firstName,
    this.lastName,
  });

  final String userId;
  final String email;
  final String? firstName;
  final String? lastName;

  /// What to show in a list. Falls back to the email, which every client has —
  /// a contractor can add a client before knowing their name.
  String get displayName {
    final name = [firstName, lastName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return name.isEmpty ? email : name;
  }

  /// Shapes are checked, never cast, so a changed payload fails with a readable
  /// FormatException instead of a type error somewhere further down.
  factory QuoteClient.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException(
        'Expected a JSON object for QuoteClient, got ${json.runtimeType}',
      );
    }

    final userId = json['user_id'];
    if (userId is! String || userId.isEmpty) {
      throw FormatException(
        'QuoteClient JSON missing a valid string "user_id" '
        '(got ${userId.runtimeType})',
      );
    }

    final email = json['email'];
    if (email is! String || email.isEmpty) {
      throw FormatException(
        'QuoteClient JSON missing a valid string "email" '
        '(got ${email.runtimeType})',
      );
    }

    final firstName = json['first_name'];
    final lastName = json['last_name'];

    return QuoteClient(
      userId: userId,
      email: email,
      firstName: firstName is String ? firstName : null,
      lastName: lastName is String ? lastName : null,
    );
  }
}
