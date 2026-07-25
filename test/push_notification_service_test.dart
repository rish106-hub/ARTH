import 'package:arth/services/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps only supported notification destinations', () {
    expect(
      notificationRouteForData({'screen': 'spend-map'}),
      '/spend-map',
    );
    expect(notificationRouteForData({'screen': 'unknown'}), isNull);
    expect(notificationRouteForData({}), isNull);
  });
}
