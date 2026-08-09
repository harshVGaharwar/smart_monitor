import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/case_item.dart';

import '../models/cases_response.dart';
import '../models/update_response.dart';
import '../models/pending_case.dart';
import '../models/update_request.dart';
import '../models/upload_response.dart';

class Api {
  final ApiClient _client;

  Api(this._client);

  Future<CasesResponse> fetchSmartPointer() async {
    final body = await _client.get(ApiEndpoints.smartPointer);
    final response = CasesResponse.fromBody(body);

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

  Future<UpdatedCasesResponse> updateCase(CaseItem item) async {
    final body = await _client.post(
      ApiEndpoints.upddateCase,
      body:
          UpdateRequestModel(
            rows: [UpdateRequestRow.fromCaseItem(item)],
          ).toJson(),
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
