import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as image;

class PreparedDocumentImage {
  const PreparedDocumentImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final List<int> bytes;
  final String filename;
  final String mimeType;
}

class OnDeviceDocumentOcrService {
  Future<String?> extractLatinText(String filePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = InputImage.fromFilePath(filePath);
      final result = await recognizer.processImage(image);
      final text = result.text.trim();
      return text.length >= 40 ? text : null;
    } finally {
      await recognizer.close();
    }
  }

  PreparedDocumentImage prepareForUpload({
    required List<int> bytes,
    required String filename,
  }) {
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      return PreparedDocumentImage(
        bytes: bytes,
        filename: filename,
        mimeType: 'image/jpeg',
      );
    }
    const maxDimension = 2400;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest > maxDimension
        ? decoded.width >= decoded.height
            ? image.copyResize(
                decoded,
                width: maxDimension,
                interpolation: image.Interpolation.linear,
              )
            : image.copyResize(
                decoded,
                height: maxDimension,
                interpolation: image.Interpolation.linear,
              )
        : decoded;
    final baseName = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return PreparedDocumentImage(
      bytes: image.encodeJpg(resized, quality: 84),
      filename: '$baseName.jpg',
      mimeType: 'image/jpeg',
    );
  }
}
