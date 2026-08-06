/// A single row of the MIS Data register.
class MisReport {
  final int srNo;
  final String reportName;
  final String recdFrom; // MIS / CRE / Manually preparation …
  final String frequency; // Daily / Monthly …
  final String category;
  final String employeeName;
  final bool ticked;
  final DateTime? tickDate;
  final DateTime? lastPublishedDate;

  const MisReport({
    required this.srNo,
    required this.reportName,
    required this.recdFrom,
    required this.frequency,
    required this.category,
    required this.employeeName,
    this.ticked = false,
    this.tickDate,
    this.lastPublishedDate,
  });

  MisReport copyWith({bool? ticked, DateTime? tickDate}) {
    return MisReport(
      srNo: srNo,
      reportName: reportName,
      recdFrom: recdFrom,
      frequency: frequency,
      category: category,
      employeeName: employeeName,
      ticked: ticked ?? this.ticked,
      tickDate: tickDate ?? this.tickDate,
      lastPublishedDate: lastPublishedDate,
    );
  }
}
