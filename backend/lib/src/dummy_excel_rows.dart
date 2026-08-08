/// Rows `POST /api/read-excel` answers with when it could not read the file.
///
/// The upload screen cannot be worked on without a spreadsheet that satisfies
/// the parser's column contract, and the first thing anyone uploads locally is
/// whatever .xlsx they happen to have. Rather than leaving the screen stuck on
/// an error banner, an unreadable file falls back to these — see
/// `readExcelFallback` in `routes/api/read-excel.dart`, and `READ_EXCEL_DUMMY=0`
/// to turn the fallback off and get the parser's real complaint instead.
///
/// Written in the parser's output shape — every value text, the response keys
/// as column names — so they go through `smartRow` exactly as parsed rows do
/// and cannot drift from what a real read returns. No `status` or
/// `imported_at`: read-excel stores nothing, and those two only exist once a
/// case has been imported.
///
/// The first row is the one UAT returns verbatim. The last two carry a CPU, a
/// team and a category the client's master data does not recognise, so the
/// validation report has flagged rows to show rather than a uniformly green
/// table — the red, editable cells are the part of that screen worth looking
/// at.
const dummyExcelRows = <Map<String, dynamic>>[
  {
    'client_id': '3332125',
    'customer_name': 'LEHRY INSTRUMENTATION AND VALVES PVT LTD',
    'account_no': '11424036',
    'line_no': '50301271033004',
    'health_check_category': 'FD Exceptions',
    'sub_category': 'Excess lien marked in Core',
    'support_system': '787920',
    'core_system': '986920',
    'exception_category': 'Exception',
    'reason': 'Fd Lien Amount Mismatch Between Lmm And Core; To Be Reviewed '
        'And Rectified',
    'cpu': 'Chennai',
    'team': 'Disbursement Team',
    'segment': '',
    'facility': '',
    'sr_no': '',
    'maker': 'OFF550975',
    'checker': 'r14878',
    'ls_srm_date': '',
  },
  {
    'client_id': '1130488',
    'customer_name': 'TRANSIT ELECTRONICS LTD',
    'account_no': '11264580',
    'line_no': '50301271033011',
    'health_check_category': 'CAM Expiry Health Check',
    'sub_category': 'CAM expired, renewal pending',
    'support_system': 'LMM',
    'core_system': 'FC',
    'exception_category': 'Exception',
    'reason': 'Cam Validity Lapsed; Renewal Note To Be Submitted',
    'cpu': 'Mumbai',
    'team': 'Cam Renewal Team',
    'segment': 'Corporate',
    'facility': 'Cash Credit',
    'sr_no': '1',
    'maker': 'OFF455430',
    'checker': 'r14878',
    'ls_srm_date': '2026-06-18',
  },
  {
    'client_id': '4943581',
    'customer_name': 'ACME ENGINEERING PVT LTD',
    'account_no': '50200031339584',
    'line_no': '50301271033027',
    'health_check_category': 'Stock Statement Health Check',
    'sub_category': 'Stock statement overdue',
    'support_system': 'LMM',
    'core_system': 'FC',
    'exception_category': 'Exception',
    'reason': 'Stock Statement Not Received For Two Consecutive Months',
    'cpu': 'Gurgaon',
    'team': 'Stock Statement Team',
    'segment': 'SME',
    'facility': 'Working Capital',
    'sr_no': '2',
    'maker': 'OFF807292',
    'checker': 'r22104',
    'ls_srm_date': '2026-07-02',
  },
  {
    'client_id': '5518890',
    'customer_name': 'VERTEX AGRO INDUSTRIES LTD',
    'account_no': '11002348',
    'line_no': '50301271033058',
    'health_check_category': 'Legal Document Health Check',
    'sub_category': 'Document pending execution',
    'support_system': 'LMM',
    'core_system': 'FC',
    'exception_category': 'Exclusion',
    'reason': 'Mortgage Deed Pending Registration; Excluded Till Legal Sign '
        'Off',
    'cpu': 'Mohali',
    'team': 'LAD Team',
    'segment': 'Agri',
    'facility': 'Overdraft',
    'sr_no': '3',
    'maker': 'OFF498090',
    'checker': 'r19052',
    'ls_srm_date': '2026-04-16',
  },
  // Unrecognised CPU and team: both cells land red and editable.
  {
    'client_id': '7761203',
    'customer_name': 'SILVERLINE TEXTILES PVT LTD',
    'account_no': '11557781',
    'line_no': '50301271033046',
    'health_check_category': 'LMM vs UBS Mismatch',
    'sub_category': 'Limit mismatch between systems',
    'support_system': '450000',
    'core_system': '400000',
    'exception_category': 'Exception',
    'reason': 'Sanctioned Limit In Lmm Does Not Match Ubs; To Be Reconciled',
    'cpu': 'Hyderabad',
    'team': 'Limit Setting',
    'segment': 'SME',
    'facility': 'Letter of Credit',
    'sr_no': '4',
    'maker': 'OFF756549',
    'checker': 'r19052',
    'ls_srm_date': '2026-07-11',
  },
  // Unrecognised health check and exception category, same idea.
  {
    'client_id': '2287410',
    'customer_name': 'NORTHGATE LOGISTICS LIMITED',
    'account_no': '11930442',
    'line_no': '50301271033039',
    'health_check_category': 'Insurance Health Check',
    'sub_category': 'Policy lapsed',
    'support_system': 'LMM',
    'core_system': 'FC',
    'exception_category': 'Deviation',
    'reason': 'Insurance Policy Expired; Renewed Copy To Be Obtained',
    'cpu': 'Kolkata',
    'team': 'Insurance Team',
    'segment': 'Corporate',
    'facility': 'Term Loan',
    'sr_no': '5',
    'maker': 'OFF159515',
    'checker': 'r22104',
    'ls_srm_date': '2026-05-29',
  },
];
