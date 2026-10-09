import 'package:flutter/services.dart';

class VisualSource {
  static const channel = MethodChannel('clearsafe/visuals');
  Future<bool> supported() async =>
      await channel.invokeMethod<bool>('supported') ?? false;
  Future<Uint8List?> preview(String id) =>
      channel.invokeMethod<Uint8List>('preview', {'id': id});
  Future<Map<dynamic, dynamic>> details(String id) async =>
      await channel.invokeMapMethod<dynamic, dynamic>('details', {'id': id}) ??
      {};
  Future<Map<dynamic, dynamic>> signature(String id) async =>
      await channel.invokeMapMethod<dynamic, dynamic>('signature', {
        'id': id,
      }) ??
      {};
  Future<void> view(String id) =>
      channel.invokeMethod<void>('view', {'id': id});
}
