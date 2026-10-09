import 'package:clearsafe/data/native_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_scanner/safe_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(NativeSource.channel, null),
  );
  for (final access in Access.values) {
    test(
      'Native permission preserves ${access.name} without widening',
      () async {
        messenger.setMockMethodCallHandler(NativeSource.channel, (call) async {
          expect(call.method, 'requestPermission');
          expect((call.arguments as Map)['scope'], 'media');
          return access.name;
        });
        expect(await NativeSource().permission('media', request: true), access);
      },
    );
  }
  test('Unknown permission fails closed', () async {
    messenger.setMockMethodCallHandler(
      NativeSource.channel,
      (_) async => 'unexpected',
    );
    expect(await NativeSource().permission('contacts'), Access.unavailable);
  });
  test('Native stream closes handle after successful read', () async {
    var reads = 0;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NativeSource.channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'open':
          return 'opaque-handle';
        case 'read':
          return Uint8List.fromList(reads++ == 0 ? [1, 2, 3] : []);
        case 'close':
          return null;
        default:
          throw StateError('Unexpected operation');
      }
    });
    final data = await NativeSource()
        .read('opaque-id')
        .expand((x) => x)
        .toList();
    expect(data, [1, 2, 3]);
    expect(calls, ['open', 'read', 'read', 'close']);
  });
  test('Revocation during stream still closes handle', () async {
    var closed = false;
    messenger.setMockMethodCallHandler(NativeSource.channel, (call) async {
      if (call.method == 'open') return 'handle';
      if (call.method == 'close') {
        closed = true;
        return null;
      }
      throw PlatformException(code: 'revoked');
    });
    await expectLater(
      NativeSource().read('id').toList(),
      throwsA(isA<PlatformException>()),
    );
    expect(closed, isTrue);
  });
}
