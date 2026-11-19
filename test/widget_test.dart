import 'package:flutter_test/flutter_test.dart';
import 'package:cocbasepro/ios_backend.dart';
void main() {
  test('Backend is HTTPS', () {
    expect(Uri.parse(IosBackend.origin).scheme, 'https');
    expect(Uri.parse(IosBackend.origin).host, 'ios-api.basecoc.net');
  });
}
