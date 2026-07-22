import 'dart:convert';
import 'dart:io';

class CityImageResult {
  const CityImageResult({
    required this.imageUrl,
    required this.artist,
    required this.license,
  });

  final String imageUrl;
  final String artist;
  final String license;
}

class CityImageService {
  CityImageService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, CityImageResult?> _cache = {};

  static const _landmarkQueries = <String, String>{
    'Chennai': 'Marina Beach Chennai',
    'Bengaluru': 'Vidhana Soudha Bengaluru',
    'Hyderabad': 'Charminar Hyderabad',
    'Pune': 'Shaniwar Wada Pune',
    'Ahmedabad': 'Sabarmati Ashram Ahmedabad',
    'Jaipur': 'Hawa Mahal Jaipur',
    'Indore': 'Rajwada Indore',
    'Bhopal': 'Upper Lake Bhopal',
    'Chandigarh': 'Open Hand Monument Chandigarh',
    'Kochi': 'Chinese fishing nets Kochi',
    'Surat': 'Surat Castle',
    'Nagpur': 'Deekshabhoomi Nagpur',
    'Coimbatore': 'Coimbatore city India',
    'Visakhapatnam': 'Visakhapatnam beach',
    'Vadodara': 'Laxmi Vilas Palace Vadodara',
  };

  Future<CityImageResult?> find(String city) async {
    final normalized = city.trim();
    if (normalized.isEmpty || normalized == 'Other') return null;
    if (_cache.containsKey(normalized)) return _cache[normalized];
    try {
      final query =
          _landmarkQueries[normalized] ?? '$normalized India landmark';
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': query,
        'gsrnamespace': '6',
        'gsrlimit': '5',
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata',
        'iiurlwidth': '1200',
        'format': 'json',
        'origin': '*',
      });
      final request = await _client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ARTH/1.0 (city onboarding; contact via github.com/rish106-hub/ARTH)',
      );
      final response = await request.close();
      if (response.statusCode != 200) return _cache[normalized] = null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final pages = (decoded['query'] as Map<String, dynamic>?)?['pages']
          as Map<String, dynamic>?;
      if (pages == null || pages.isEmpty) return _cache[normalized] = null;
      for (final page in pages.values.whereType<Map<String, dynamic>>()) {
        final info = (page['imageinfo'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .firstOrNull;
        final url = info?['thumburl']?.toString() ?? info?['url']?.toString();
        if (url == null || url.isEmpty) continue;
        final metadata =
            info?['extmetadata'] as Map<String, dynamic>? ?? const {};
        final artist = _metadataValue(metadata['Artist']);
        final license = _metadataValue(metadata['LicenseShortName']);
        return _cache[normalized] = CityImageResult(
          imageUrl: url,
          artist: _stripHtml(artist.isEmpty ? 'Wikimedia contributor' : artist),
          license: license.isEmpty ? 'Wikimedia Commons' : license,
        );
      }
      return _cache[normalized] = null;
    } catch (_) {
      return _cache[normalized] = null;
    }
  }

  static String _metadataValue(Object? value) {
    if (value is Map<String, dynamic>) return value['value']?.toString() ?? '';
    return '';
  }

  static String _stripHtml(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .trim();
}
