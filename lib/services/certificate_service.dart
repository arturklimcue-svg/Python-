import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CertificateService {
  static Future<Uint8List> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData!.buffer.asUint8List();
  }

  static Future<File> saveToTemp(Uint8List png, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png);
    return file;
  }

  static Future<void> share(File file, String text) async {
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: text,
    );
    if (result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed) {
      // ok
    }
  }
}