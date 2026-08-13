import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/constants.dart';

import '../models/add_comment_request.dart';
import '../models/cases_response.dart';
import '../models/comment_response.dart';
import '../models/document_response.dart';
import '../models/get_comments_request.dart';
import '../models/get_documents_request.dart';
import '../models/login_request.dart';
import '../models/login_response.dart';
import '../models/master_data_response.dart';
import '../models/update_response.dart';
import '../models/pending_case.dart';
import '../models/smart_pointer_request.dart';
import '../models/update_request.dart';
import '../models/reassign_request.dart';
import '../models/reassign_response.dart';
import '../models/upload_response.dart';
import '../models/verify_request.dart';

class Api {
  final ApiClient _client;

  Api(this._client);

  /// Signs [name] in and hands back the session.
  ///
  /// The response is raw rather than enveloped, so there is no success flag to
  /// read: a refused sign-in arrives as a non-2xx and [ApiClient] has already
  /// turned the server's message into an [ApiException] by the time it lands
  /// here.
  Future<LoginResponse> login({
    required String name,
    required String password,
  }) async {
    final body = await _client.post(
      ApiEndpoints.login,
      body: LoginRequest(name: name, password: password).toJson(),
    );

    if (body is! Map<String, dynamic>) {
      throw const ApiException(
        'The sign-in service sent an unexpected response.',
      );
    }

    final response = LoginResponse.fromJson(body);
    // A 200 carrying no token is a failed sign-in the service did not flag.
    // Letting it through would push a dashboard that cannot authenticate a
    // single call, which reads as an outage rather than a bad password.
    if (response.token.isEmpty) {
      throw const ApiException(
        'Sign-in failed. Check your username and password.',
      );
    }
    return response;
  }

  /// The signed-in user's queue — the cases [request] names, and no others.
  ///
  /// The request is required because the endpoint has no unfiltered read: the
  /// server picks the rows from the employee code and role, so asking without
  /// them is not a wider question but a malformed one.
  Future<CasesResponse> fetchSmartPointer(SmartPointerRequest request) async {
    final body = await _client.get(
      ApiEndpoints.smartPointer,
      query: request.toQuery(),
    );
    final response = CasesResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// The reference lists every screen validates and its dropdowns against.
  ///
  /// No request object: the lists are the same for every user and every
  /// screen, so there is nothing to narrow them by. Read once per session —
  /// see `MasterData`.
  Future<MasterDataResponse> fetchMasterData() async {
    final body = await _client.get(ApiEndpoints.masterData);
    final response = MasterDataResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// Routes one record to another CPU and team.
  ///
  /// A reassignment carrying a document goes up as multipart, the file under
  /// `document`; one without stays a plain JSON post.
  Future<ReassignResponse> reassignCase(ReassignRequest request) async {
    final file = request.document;

    final body =
        file == null
            ? await _client.post(ApiEndpoints.reassign, body: request.toJson())
            : await _client.uploadBytes(
              ApiEndpoints.reassign,
              bytes: file.bytes,
              filename: file.filename,
              field: 'document',
              fields: request.toFields(),
            );

    final response = ReassignResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// The comment thread on one case, oldest first.
  ///
  /// Read before the composer is used: the thread is the server's, and a
  /// panel that only ever showed what this session posted would open empty on
  /// a record two people have been discussing for a week.
  Future<CommentsResponse> fetchComments(GetCommentsRequest request) async {
    final body = await _client.get(
      ApiEndpoints.getComments,
      query: request.toQuery(),
    );
    final response = CommentsResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// The files attached to one case, oldest first.
  ///
  /// Read when the drawer opens rather than assembled from what this session
  /// happened to upload: a panel that only showed the latter would open empty
  /// on a record two people have been attaching evidence to for a week.
  ///
  /// Not gated on a template, and deliberately so — see [GetDocumentsRequest].
  Future<DocumentsResponse> fetchDocuments(GetDocumentsRequest request) async {
    final body = await _client.get(
      ApiEndpoints.getDocuments,
      query: request.toQuery(),
    );
    final response = DocumentsResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// Adds one comment to that thread, and hands back what was stored.
  ///
  /// A note with a supporting document goes up as multipart, the file under
  /// `supportDocument`; one without stays a plain JSON post, so nothing
  /// changes for the common case of a comment on its own.
  Future<AddCommentResponse> addComment(AddCommentRequest request) async {
    final file = request.supportDocument;

    final body =
        file == null
            ? await _client.post(
              ApiEndpoints.addComment,
              body: request.toJson(),
            )
            : await _client.uploadBytes(
              ApiEndpoints.addComment,
              bytes: file.bytes,
              filename: file.filename,
              field: 'supportDocument',
              fields: request.toFields(),
            );

    final response = AddCommentResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  Future<UploadResponse> uploadCasesFile({
    required Uint8List bytes,
    required String filename,
  }) async {
    final body = await _client.uploadBytes(
      ApiEndpoints.uploadCases,
      bytes: bytes,
      filename: filename,
      field: 'file',

      fields: {'fileType': fileExtension(filename)},
    );

    final response = UploadResponse.fromBody(body);

    if (!response.isSuccess) throw ApiException(response.failure!);
    if (response.isEmpty) {
      throw const ApiException(
        'The server accepted the file but returned no rows.',
      );
    }
    return response;
  }

  Future<UpdatedCasesResponse> updateCases(List<PendingCase> rows) async {
    if (rows.isEmpty) {
      throw const ApiException('There were no rows to import.');
    }

    final body = await _client.post(
      ApiEndpoints.upddateCase,
      body:
          UpdateRequestModel(
            rows: [
              for (final row in rows) UpdateRequestRow.fromPendingCase(row),
            ],
          ).toJson(),
    );
    final response = UpdatedCasesResponse.fromJson(
      body,
      sentCount: rows.length,
    );

    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// Signs one record off.
  ///
  /// Answers in the same envelope as the import — `data` a plain count of the
  /// rows written — so [UpdatedCasesResponse] reads it rather than a second
  /// model saying the same thing.
  /// A note carrying a supporting document goes up as multipart, the file
  /// under `supportDocument`; one without stays a plain JSON post — the same
  /// two shapes [addComment] posts in.
  Future<UpdatedCasesResponse> verifyCase(VerifyRequest request) async {
    final file = request.supportDocument;

    final body =
        file == null
            ? await _client.post(ApiEndpoints.verify, body: request.toJson())
            : await _client.uploadBytes(
              ApiEndpoints.verify,
              bytes: file.bytes,
              filename: file.filename,
              field: 'supportDocument',
              fields: request.toFields(),
            );
    final response = UpdatedCasesResponse.fromJson(body, sentCount: 1);
    if (!response.isSuccess) throw ApiException(response.failure!);
    return response;
  }

  /// The extension of [filename], lowercased and without the dot — `xlsx` for
  /// `Health Check Aug.xlsx`. Empty when the name carries no extension.
  static String fileExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }
}
