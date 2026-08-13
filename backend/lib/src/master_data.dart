/// The reference lists every screen validates and its dropdowns against.
///
/// Fixed reference data rather than a store: these change when the bank
/// reorganises, not when a case moves, so there is no repository behind them
/// and nothing writes to them. Served whole by `/api/getMasterData` — the
/// client reads one call and holds the answer for the session.
///
/// Keyed the way the wire spells it, so the route can hand the map straight to
/// the envelope without restating a single name.
///
/// These lived on the client until now, as `MockData`'s `static const` lists.
/// The values are carried over verbatim: a case already stored names a CPU or
/// a team by one of these spellings, and changing one here would orphan every
/// row that used it.
const masterData = <String, List<String>>{
  /// Processing units a case can be reassigned to, and what an uploaded CPU is
  /// checked against.
  'cpus': [
    'Ahmedabad',
    'Chennai',
    'Gurgaon',
    'Kolkata',
    'Mohali',
    'Mumbai',
  ],

  /// Destination teams offered in the reassign dialog, and what an uploaded
  /// team is checked against.
  'teams': [
    'Agri Foreclosure Team',
    'Cam Renewal Team',
    'Cam Updation Team',
    'Centralized Mis Team',
    'Disbursement Team',
    'Foreclosure Team',
    'Gift City Team',
    'Guarantee Team',
    'Insurance Team',
    'Inventory funding team',
    'LAD Team',
    'LMS Team',
    'Pmt- Property Management',
    'Retail Lc- Bg Team',
    'StaffLoan Team',
    'Stock Statement Team',
    'Trade/ Limit Setting Team',
  ],

  /// An uploaded row naming anything else is flagged in the validation report.
  'exceptionCategories': ['Exception', 'Exclusion'],

  /// Checked the same way on upload.
  'healthCheckCategories': [
    'CAM Expiry Health Check',
    'LMM vs UBS Mismatch',
    'FD Exceptions',
    'Stock Statement Health Check',
    'Insurance Expiry Health Check',
    'Legal Document Health Check',
  ],

  /// Offered in the detail panel's Reassign tab. Which of the workflow's own
  /// answers the reviewer picked, as against the note they typed.
  'reassignReasons': [
    'Incorrect CPU mapping',
    'Incorrect team mapping',
    'Workload rebalancing',
    'Requires specialist review',
    'Raised in error',
  ],
};
