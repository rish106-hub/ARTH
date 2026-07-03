import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_document.dart';
import '../services/tax_document_service.dart';

final taxDocumentServiceProvider = Provider<TaxDocumentService>(
  (ref) => TaxDocumentService(),
);

class TaxDocumentNotifier extends AsyncNotifier<List<TaxDocument>> {
  late final TaxDocumentService _service;

  @override
  Future<List<TaxDocument>> build() async {
    _service = ref.read(taxDocumentServiceProvider);
    return _service.fetchDocuments();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.fetchDocuments);
  }

  Future<void> upload({
    required String documentType,
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    final uploaded = await _service.uploadDocument(
      documentType: documentType,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
    );
    state = AsyncData([
      uploaded,
      ...previous.where((doc) => doc.id != uploaded.id),
    ]);
  }

  Future<void> delete(String id) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    await _service.deleteDocument(id);
    state = AsyncData(previous.where((doc) => doc.id != id).toList());
  }
}

final taxDocumentProvider =
    AsyncNotifierProvider<TaxDocumentNotifier, List<TaxDocument>>(
  TaxDocumentNotifier.new,
);
