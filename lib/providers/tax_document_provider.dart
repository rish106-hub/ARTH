import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_document.dart';
import '../models/payslip_tax_prefill.dart';
import '../models/form16_tax_prefill.dart';
import '../services/tax_document_service.dart';
import 'user_profile_provider.dart';

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

  Future<TaxDocument> upload({
    required String documentType,
    required String filename,
    required String mimeType,
    required List<int> bytes,
    String? ocrText,
  }) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    final uploaded = await _service.uploadDocument(
      documentType: documentType,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
      ocrText: ocrText,
    );
    state = AsyncData([
      uploaded,
      ...previous.where((doc) => doc.id != uploaded.id),
    ]);
    return uploaded;
  }

  Future<void> delete(String id) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    await _service.deleteDocument(id);
    state = AsyncData(previous.where((doc) => doc.id != id).toList());
  }

  Future<void> updateMetadata(
    String id, {
    String? userLabel,
    String? notes,
    List<String>? tags,
    String? vaultStatus,
    String? reviewStatus,
  }) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    final updated = await _service.updateDocument(
      id,
      userLabel: userLabel,
      notes: notes,
      tags: tags,
      vaultStatus: vaultStatus,
      reviewStatus: reviewStatus,
    );
    state = AsyncData([
      for (final doc in previous) doc.id == id ? updated : doc,
    ]);
  }

  Future<TaxDocument> confirmParsedFields(
    String id, {
    Map<String, dynamic>? fields,
  }) async {
    final previous = state.asData?.value ?? const <TaxDocument>[];
    final confirmed = await _service.confirmParsedFields(id, fields: fields);
    state = AsyncData([
      for (final doc in previous) doc.id == id ? confirmed : doc,
    ]);
    return confirmed;
  }
}

final taxDocumentProvider =
    AsyncNotifierProvider<TaxDocumentNotifier, List<TaxDocument>>(
  TaxDocumentNotifier.new,
);

final payslipTaxPrefillProvider = Provider<PayslipTaxPrefill?>((ref) {
  final documents = ref.watch(taxDocumentProvider).asData?.value;
  if (documents == null) return null;
  final monthsWorked = ref.watch(
    userProfileProvider.select((profile) => profile.jobDurationMonths),
  );
  return payslipTaxPrefillFromDocuments(documents, monthsWorked: monthsWorked);
});

/// Prefill from the latest confirmed Form 16 (employer's annual statement).
final form16TaxPrefillProvider = Provider<Form16TaxPrefill?>((ref) {
  final documents = ref.watch(taxDocumentProvider).asData?.value;
  if (documents == null) return null;
  return form16TaxPrefillFromDocuments(documents);
});
