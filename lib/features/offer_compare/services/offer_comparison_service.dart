import '../../../services/auth_service.dart';
import '../../../services/server_api_service.dart';
import '../models/offer_comparison_models.dart';

/// Result of submitting answers.
///
/// Answers are saved on the server even when advice cannot be produced, so the
/// two outcomes are modelled separately rather than as success and failure. The
/// candidate must never be asked to type five answers again because a model was
/// unavailable.
class OfferAnswersResult {
  const OfferAnswersResult({
    required this.comparison,
    required this.adviceUnavailable,
  });

  final OfferComparison comparison;
  final bool adviceUnavailable;
}

class OfferComparisonService {
  OfferComparisonService({ServerApiService? api, AuthService? auth})
      : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  final ServerApiService _api;
  final AuthService _auth;

  /// Opens a comparison over stored offer letters, in the order given. That order
  /// is what "Offer A" means from here on.
  Future<OfferComparison> startComparison(List<String> documentIds) async {
    final response = await _auth.withFreshAccessToken(
      (token) => _api.postJson(
        '/offers/compare',
        body: {'documentIds': documentIds},
        bearerToken: token,
      ),
    );
    return OfferComparison.fromJson(
      response['comparison'] as Map<String, dynamic>,
    );
  }

  Future<OfferComparison> fetchComparison(String id) async {
    final response = await _auth.withFreshAccessToken(
      (token) => _api.getJson('/offers/compare/$id', bearerToken: token),
    );
    return OfferComparison.fromJson(
      response['comparison'] as Map<String, dynamic>,
    );
  }

  Future<OfferAnswersResult> submitAnswers(
    String id,
    Map<String, String> answers,
  ) async {
    try {
      final response = await _auth.withFreshAccessToken(
        (token) => _api.postJson(
          '/offers/compare/$id/answers',
          body: {
            'answers': [
              for (final entry in answers.entries)
                {'id': entry.key, 'answer': entry.value},
            ],
          },
          bearerToken: token,
        ),
      );
      return OfferAnswersResult(
        comparison: OfferComparison.fromJson(
          response['comparison'] as Map<String, dynamic>,
        ),
        adviceUnavailable: false,
      );
    } on ServerApiException catch (error) {
      // 503 means the answers were stored and only the advice is missing. The
      // error body is not surfaced by the API client, so the saved session is
      // read back instead of being reconstructed from the request.
      if (error.statusCode != 503) rethrow;
      return OfferAnswersResult(
        comparison: await fetchComparison(id),
        adviceUnavailable: true,
      );
    }
  }
}
