import 'api_envelope.dart';
import 'case_item.dart';

/// One attached file as the service stores it.
///
/// Read defensively, the same rule the case and comment models follow: a
/// missing key yields a default rather than throwing, so one odd row does not
/// take the whole list down.
class RemoteDocument {
  final String clientId;

  /// The employee code of whoever posted the note this file came with.
  final String userId;

  /// The name of the file. The name only — the bytes live wherever the service
  /// put them, and nothing here serves them back.
  final String fileName;

  /// Who to show as the uploader: the template they posted under, falling back
  /// to their code, so the line is never blank. The service already resolves
  /// this, and it is taken as sent rather than worked out again here.
  final String uploadedBy;

  /// When the service stored it. Null when the stamp was missing or
  /// unreadable, which is why the list falls back to the order it arrived in.
  final DateTime? uploadedDate;

  const RemoteDocument({
    this.clientId = '',
    this.userId = '',
    this.fileName = '',
    this.uploadedBy = '',
    this.uploadedDate,
  });

  factory RemoteDocument.fromJson(Map<String, dynamic> json) => RemoteDocument(
    clientId: '${json['clientId'] ?? ''}',
    // Both spellings, so a server sending either fills the row.
    userId: '${json['userID'] ?? json['userId'] ?? ''}',
    fileName: '${json['fileName'] ?? json['file_name'] ?? ''}',
    uploadedBy: '${json['uploadedBy'] ?? ''}',
    uploadedDate: DateTime.tryParse('${json['uploadedDate'] ?? ''}')?.toLocal(),
  );

  /// The file in the shape the panel draws.
  ///
  /// The stamp falls back to now rather than to nothing: the row is about to be
  /// rendered beside a date, and a missing one would read as an error rather
  /// than as a server that did not say.
  CaseDocument toCaseDocument() => CaseDocument(
    name: fileName,
    uploadedBy: uploadedBy.isEmpty ? userId : uploadedBy,
    uploadedAt: uploadedDate ?? DateTime.now(),
  );
}

/// The body of `GET /getDocuments` — one case's files, oldest first.
class DocumentsResponse {
  final String? message;

  /// Why the read failed, or null when it worked. Set from the envelope, which
  /// can report a failure on a 200.
  final String? failure;

  final List<RemoteDocument> documents;

  const DocumentsResponse({
    this.message,
    this.failure,
    this.documents = const [],
  });

  factory DocumentsResponse.fromBody(Object? body) {
    final envelope = ApiEnvelope(body);
    final data = envelope.data;
    // Read whether the payload wrapped the list or sent it bare — the service
    // has been seen doing both, and either is unambiguous here.
    final raw = data is List ? data : (data is Map ? data['documents'] : null);

    return DocumentsResponse(
      message: envelope.message,
      failure: envelope.failure,
      documents: [
        if (raw is List)
          for (final item in raw)
            if (item is Map<String, dynamic>) RemoteDocument.fromJson(item),
      ],
    );
  }

  bool get isSuccess => failure == null;
}
