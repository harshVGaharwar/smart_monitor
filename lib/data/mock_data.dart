import '../models/mis_report.dart';

/// Static sample data standing in for the reconciliation backend.
///
/// Only the MIS register is left. The master lists this class used to carry —
/// CPUs, teams and the three category sets — now come from the server; see
/// `MasterData` and `Api.fetchMasterData`.
class MockData {
  MockData._();

  /// Rows of the MIS Data register.
  static final List<MisReport> misReports = [
    MisReport(
      srNo: 1,
      reportName: 'TL backed by FD (SNA Exceptions)',
      recdFrom: 'MIS',
      frequency: 'Daily',
      category: 'FD related',
      employeeName: 'Sujeet Tiwari',
      tickDate: DateTime(2026, 5, 27),
      lastPublishedDate: DateTime(2026, 5, 27),
    ),
    MisReport(
      srNo: 2,
      reportName: 'Basel - FD reconciliation',
      recdFrom: 'Manually preparation',
      frequency: 'Monthly',
      category: 'Monitoring / Regulatory',
      employeeName: 'Amol Jaiswal',
      tickDate: DateTime(2026, 7, 4),
      lastPublishedDate: DateTime(2026, 7, 4),
    ),
    MisReport(
      srNo: 4,
      reportName: 'FD Exceptions',
      recdFrom: 'MIS',
      frequency: 'Daily',
      category: 'FD related',
      employeeName: 'Swati Kadam',
      tickDate: DateTime(2026, 7, 21),
      lastPublishedDate: DateTime(2026, 7, 21),
    ),
    MisReport(
      srNo: 5,
      reportName: 'FD ROI mismatch b/w LMM & Core',
      recdFrom: 'MIS',
      frequency: 'Daily',
      category: 'ROI related',
      employeeName: 'Swati Kadam',
      tickDate: DateTime(2026, 7, 21),
      lastPublishedDate: DateTime(2026, 7, 21),
    ),
    MisReport(
      srNo: 6,
      reportName: 'OOO NPA / Collateral header maintenance',
      recdFrom: 'MIS',
      frequency: 'Daily',
      category: 'Maintenance',
      employeeName: 'Amol Jaiswal',
      tickDate: DateTime(2026, 7, 28),
      lastPublishedDate: DateTime(2026, 7, 28),
    ),
    MisReport(
      srNo: 7,
      reportName: 'CAM Expiry (CPU / Local Ops)',
      recdFrom: 'CRE',
      frequency: 'Daily',
      category: 'Expiry related',
      employeeName: 'Prashant Rane',
      tickDate: DateTime(2026, 7, 28),
      lastPublishedDate: DateTime(2026, 7, 28),
    ),
    MisReport(
      srNo: 8,
      reportName: 'Flex cube TOD regularization',
      recdFrom: 'MIS',
      frequency: 'Daily',
      category: 'TOD related',
      employeeName: 'Reshma Suvarna',
      tickDate: DateTime(2026, 7, 28),
      lastPublishedDate: DateTime(2026, 7, 28),
    ),
    MisReport(
      srNo: 9,
      reportName: 'Stock statement overdue',
      recdFrom: 'MIS',
      frequency: 'Monthly',
      category: 'Monitoring / Regulatory',
      employeeName: 'Sujeet Tiwari',
      tickDate: DateTime(2026, 7, 25),
      lastPublishedDate: DateTime(2026, 7, 25),
    ),
    MisReport(
      srNo: 10,
      reportName: 'Insurance expiry tracker',
      recdFrom: 'Manually preparation',
      frequency: 'Weekly',
      category: 'Expiry related',
      employeeName: 'Reshma Suvarna',
      tickDate: DateTime(2026, 7, 27),
      lastPublishedDate: DateTime(2026, 7, 27),
    ),
    MisReport(
      srNo: 11,
      reportName: 'Guarantee invocation register',
      recdFrom: 'CRE',
      frequency: 'Weekly',
      category: 'Maintenance',
      employeeName: 'Prashant Rane',
      tickDate: DateTime(2026, 7, 26),
      lastPublishedDate: DateTime(2026, 7, 26),
    ),
  ];
}
