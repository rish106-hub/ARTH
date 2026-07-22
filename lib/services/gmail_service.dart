import 'dart:convert';
import 'dart:io';

/// A Gmail message reduced to what the invoice parser needs.
typedef RawEmail = ({String from, String subject, String snippet, DateTime date});

class GmailException implements Exception {
  GmailException(this.message);
  final String message;
  @override
  String toString() => 'GmailException: $message';
}

/// Reads invoice / receipt emails via the Gmail REST API using a readonly
/// OAuth access token. Only metadata + snippet are fetched (never full bodies
/// or attachments), and parsing happens on-device.
class GmailService {
  GmailService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const _host = 'gmail.googleapis.com';

  /// Gmail search query targeting spend-related mail from the last ~120 days.
  static const _query =
      '(invoice OR receipt OR "order confirmation" OR "payment received" OR "you paid" OR "your order") newer_than:120d';

  Future<List<RawEmail>> fetchInvoices({
    required String accessToken,
    int maxResults = 40,
  }) async {
    final ids = await _listMessageIds(accessToken, maxResults);
    final emails = <RawEmail>[];
    for (final id in ids) {
      final email = await _fetchMetadata(accessToken, id);
      if (email != null) emails.add(email);
    }
    return emails;
  }

  Future<List<String>> _listMessageIds(String accessToken, int maxResults) async {
    final uri = Uri.https(_host, '/gmail/v1/users/me/messages', {
      'q': _query,
      'maxResults': '$maxResults',
    });
    final json = await _getJson(uri, accessToken);
    final messages = json['messages'] as List<dynamic>? ?? const [];
    return messages
        .whereType<Map<String, dynamic>>()
        .map((m) => m['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<RawEmail?> _fetchMetadata(String accessToken, String id) async {
    final uri = Uri.https(_host, '/gmail/v1/users/me/messages/$id', {
      'format': 'metadata',
      'metadataHeaders': ['From', 'Subject'],
    });
    final json = await _getJson(uri, accessToken);
    final payload = json['payload'] as Map<String, dynamic>?;
    final headers = (payload?['headers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    String header(String name) {
      for (final h in headers) {
        if ((h['name']?.toString().toLowerCase() ?? '') == name.toLowerCase()) {
          return h['value']?.toString() ?? '';
        }
      }
      return '';
    }

    final snippet = json['snippet']?.toString() ?? '';
    final internalDate = int.tryParse(json['internalDate']?.toString() ?? '');
    final date = internalDate != null
        ? DateTime.fromMillisecondsSinceEpoch(internalDate)
        : DateTime.now();

    final subject = header('Subject');
    final from = header('From');
    if (subject.isEmpty && snippet.isEmpty) return null;
    return (from: from, subject: subject, snippet: snippet, date: date);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, String accessToken) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw GmailException(
        'Gmail access denied (${response.statusCode}). Re-check the '
        'gmail.readonly scope and consent.',
      );
    }
    if (response.statusCode >= 400) {
      throw GmailException('Gmail request failed (${response.statusCode}).');
    }
    if (body.isEmpty) return const {};
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
