import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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
}
