import '../models/tax_document.dart';
import 'auth_service.dart';
import 'server_api_service.dart';

class TaxDocumentService {
  final ServerApiService _api;
  final AuthService _auth;

  TaxDocumentService({ServerApiService? api, AuthService? auth})
      : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  Future<List<TaxDocument>> fetchDocuments() async {
    final token = await _auth.getValidAccessToken();
    if (token == null || token.isEmpty) return const [];
    final response = await _auth.withFreshAccessToken(
      (token) => _api.getJson('/documents', bearerToken: token),
    );
    final documents = response['documents'] as List<dynamic>? ?? const [];
    return documents
        .map((item) => TaxDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<int>> downloadDocument(String id) async {
    return _auth.withFreshAccessToken(
      (token) => _api.getBytes('/documents/$id/download', bearerToken: token),
    );
  }

  Future<TaxDocument> updateDocument(
    String id, {
    String? userLabel,
    String? notes,
    List<String>? tags,
    String? vaultStatus,
    String? reviewStatus,
  }) async {
    final body = <String, dynamic>{};
    if (userLabel != null) body['userLabel'] = userLabel;
    if (notes != null) body['notes'] = notes;
    if (tags != null) body['tags'] = tags;
    if (vaultStatus != null) body['vaultStatus'] = vaultStatus;
    if (reviewStatus != null) body['reviewStatus'] = reviewStatus;
    final response = await _auth.withFreshAccessToken(
      (token) =>
          _api.patchJson('/documents/$id', bearerToken: token, body: body),
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
    String? ocrText,
  }) async {
    final response = await _auth.withFreshAccessToken(
      (token) => _api.uploadMultipart(
        '/documents',
        bearerToken: token,
        fields: {
          'documentType': documentType,
          if (ocrText != null) 'ocrText': ocrText,
        },
        fieldName: 'file',
        filename: filename,
        contentType: mimeType,
        bytes: bytes,
      ),
    );
    return TaxDocument.fromJson(
      response['document'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> deleteDocument(String id) async {
    await _auth.withFreshAccessToken(
      (token) => _api.delete('/documents/$id', bearerToken: token),
    );
  }

  Future<TaxDocument> confirmParsedFields(
    String id, {
    Map<String, dynamic>? fields,
  }) async {
    final response = await _auth.withFreshAccessToken(
      (token) => _api.postJson(
        '/documents/$id/confirm',
        body: fields == null ? null : {'fields': fields},
        bearerToken: token,
      ),
    );
    return TaxDocument.fromJson(
      response['document'] as Map<String, dynamic>? ?? const {},
    );
  }
}
