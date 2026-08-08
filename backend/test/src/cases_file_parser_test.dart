import 'dart:convert';
import 'dart:typed_data';

import 'package:backend/src/cases_file_parser.dart';
import 'package:test/test.dart';

/// The required columns, in the order the fixtures below fill them.
const _columns = [
  'Client id',
  'Customer name',
  'Account no',
  'Line no',
  'Health Check Category',
  'Sub category',
  'Support system',
  'Core system',
  'Exception category',
  'Reason',
  'CPU',
  'Actionable Team',
  'Maker',
  'Checker',
];

const _values = [
  '4943581',
  'ACME',
  '50200031339584',
  '5',
  'CAM Expiry Health Check',
  'Sub',
  'LMM',
  'FC',
  'Exception',
  'Renewal pending',
  'Mumbai',
  'Cam Renewal Team',
  'mk',
  'ck',
];

final _headers = _columns.join(',');
final _row = _values.join(',');

/// [_row] with individual columns overridden, keyed by header name.
String _rowWith(Map<String, String> overrides) {
  final cells = [..._values];
  overrides.forEach((column, value) {
    cells[_columns.indexOf(column)] = value;
  });
  return cells.join(',');
}

Uint8List _csv(String text) => Uint8List.fromList(utf8.encode(text));

List<Map<String, dynamic>> _parse(String text, {String type = 'csv'}) =>
    CasesFileParser.parse(extension: type, bytes: _csv(text));

void main() {
  group('CasesFileParser', () {
    test('reads the data rows under the header', () {
      final rows = _parse('$_headers\n$_row');

      expect(rows, hasLength(1));
      expect(rows.single['client_id'], '4943581');
      expect(rows.single['customer_name'], 'ACME');
      expect(rows.single['team'], 'Cam Renewal Team');
      // Numbered over data rows so the client's ID column runs 1, 2, 3 …
    });

    test('optional columns come back blank rather than missing', () {
      final rows = _parse('$_headers\n$_row');

      // The client reads these unconditionally, so the keys have to exist.
      expect(rows.single['segment'], '');
      expect(rows.single['facility'], '');
      expect(rows.single['sr_no'], '');
      expect(rows.single['ls_srm_date'], '');
    });

    test('a quoted field may contain the delimiter', () {
      final row = _rowWith({'Reason': '"Renewal pending, urgent"'});
      final rows = _parse('$_headers\n$row');

      expect(rows.single['reason'], 'Renewal pending, urgent');
    });

    test('spreadsheet stand-ins for empty are read as empty', () {
      final row = _rowWith({'Core system': 'nan', 'Reason': 'null'});
      final rows = _parse('$_headers\n$row');

      expect(rows.single['core_system'], '');
      expect(rows.single['reason'], '');
    });

    test('a title row above the header does not break the read', () {
      final rows = _parse('Health check export\n\n$_headers\n$_row');

      expect(rows, hasLength(1));
      expect(rows.single['client_id'], '4943581');
    });

    test('header aliases resolve onto the canonical column', () {
      final aliased = _headers
          .replaceFirst('Health Check Category', 'Health Check')
          .replaceFirst('CPU', 'Unit')
          .replaceFirst('Actionable Team', 'Action Team');

      final rows = _parse('$aliased\n$_row');

      expect(rows.single['health_check_category'], 'CAM Expiry Health Check');
      expect(rows.single['cpu'], 'Mumbai');
      expect(rows.single['team'], 'Cam Renewal Team');
    });

    test('semicolon-separated exports are read too', () {
      final rows = _parse(
        '${_headers.replaceAll(',', ';')}\n${_row.replaceAll(',', ';')}',
      );

      expect(rows.single['customer_name'], 'ACME');
    });

    test('values are returned unjudged, for the client to validate', () {
      final row = _rowWith({
        'Health Check Category': 'Not A Real Category',
        'CPU': 'Atlantis',
        'Actionable Team': 'Ghost Team',
      });
      final rows = _parse('$_headers\n$row');

      // The master data lives on the client; nothing here rejects a value.
      expect(rows.single['cpu'], 'Atlantis');
      expect(rows.single['team'], 'Ghost Team');
      expect(rows.single['health_check_category'], 'Not A Real Category');
    });

    test('blank rows between data rows are skipped', () {
      final rows = _parse('$_headers\n$_row\n\n$_row\n');

      expect(rows, hasLength(2));
      expect(rows.last['client_id'], '4943581');
    });

    group('rejects', () {
      test('a file missing required columns, naming them', () {
        expect(
          () => _parse('Client id,Customer name\n1,ACME'),
          throwsA(
            isA<CasesFileException>().having(
              (e) => e.message,
              'message',
              allOf(contains('Account no'), contains('Actionable Team')),
            ),
          ),
        );
      });

      test('a header with no data under it', () {
        expect(
          () => _parse(_headers),
          throwsA(
            isA<CasesFileException>().having(
              (e) => e.message,
              'message',
              contains('no data rows'),
            ),
          ),
        );
      });

      test('an empty file', () {
        expect(() => _parse(''), throwsA(isA<CasesFileException>()));
      });

      test('legacy .xls, telling the user how to fix it', () {
        expect(
          () => _parse('$_headers\n$_row', type: 'xls'),
          throwsA(
            isA<CasesFileException>().having(
              (e) => e.message,
              'message',
              contains('Save the file as .xlsx'),
            ),
          ),
        );
      });

      test('an unsupported extension', () {
        expect(
          () => _parse('$_headers\n$_row', type: 'pdf'),
          throwsA(
            isA<CasesFileException>().having(
              (e) => e.message,
              'message',
              contains('Unsupported file type: .pdf'),
            ),
          ),
        );
      });

      test('a .xlsx that is not a zip archive at all', () {
        expect(
          () => _parse('not a workbook', type: 'xlsx'),
          throwsA(isA<CasesFileException>()),
        );
      });
    });
  });
}
