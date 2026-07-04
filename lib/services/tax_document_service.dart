import '../models/tax_document.dart';
import 'auth_service.dart';
import 'server_api_service.dart';

class TaxDocumentService {
  final ServerApiService _api;
  final AuthService _auth;

  TaxDocumentService({
    ServerApiService? api,
    AuthService? auth,
  })  : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  Future<List<TaxDocument>> fetchDocuments() async {
    final token = await _auth.getValidAccessToken();
    if (token == null) return const [];
    final response = await _api.getJson('/documents', bearerToken: token);
    final documents = response['documents'] as List<dynamic>? ?? const [];
    return documents
        .map((item) => TaxDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TaxDocument> updateDocument(
    String id, {
    String? userLabel,
    String? notes,
    List<String>? tags,
    String? vaultStatus,
    String? reviewStatus,
  }) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final body = <String, dynamic>{};
    if (userLabel != null) body['userLabel'] = userLabel;
    if (notes != null) body['notes'] = notes;
    if (tags != null) body['tags'] = tags;
    if (vaultStatus != null) body['vaultStatus'] = vaultStatus;
    if (reviewStatus != null) body['reviewStatus'] = reviewStatus;
    final response = await _api.patchJson(
      '/documents/$id',
      bearerToken: token,
      body: body,
    );
    return TaxDocument.fromJson(
      response['document'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<TaxDocument> uploadDocument({
    required String documentType,
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final response = await _api.uploadMultipart(
      '/documents',
      bearerToken: token,
      fields: {'documentType': documentType},
      fieldName: 'file',
      filename: filename,
      contentType: mimeType,
      bytes: bytes,
    );
    return TaxDocument.fromJson(
      response['document'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> deleteDocument(String id) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    await _api.delete('/documents/$id', bearerToken: token);
  }

  Future<TaxDocument> confirmParsedFields(String id) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final response = await _api.postJson(
      '/documents/$id/confirm',
      bearerToken: token,
    );
    return TaxDocument.fromJson(
      response['document'] as Map<String, dynamic>? ?? const {},
    );
  }
}
