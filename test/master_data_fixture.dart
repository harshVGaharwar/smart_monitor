// The master lists, for tests that need them loaded.
//
// `MasterData` starts empty and is filled by a `/getMasterData` call the real
// app makes once per session. A test that drives a dropdown or checks that an
// uploaded CPU resolved needs it filled first, or it is asserting against an
// outage rather than against the screen.
//
// Two ways in, for the two kinds of test here:
//
//  * [seedMasterData] fills the cache directly — for a widget built on its own,
//    with no `DashboardPage` above it to do the fetching.
//  * [masterDataBody] is the response body — for a `MockClient` that should
//    answer the call the page actually makes.
import 'dart:convert';

import 'package:smart_monitor/data/master_data.dart';
import 'package:smart_monitor/models/master_data_response.dart';

/// The same values the local server serves, so a test that passes here is not
/// passing on a list only the tests have.
const masterCpus = [
  'Ahmedabad',
  'Chennai',
  'Gurgaon',
  'Kolkata',
  'Mohali',
  'Mumbai',
];

const masterTeams = [
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
];

const masterExceptionCategories = ['Exception', 'Exclusion'];

const masterHealthCheckCategories = [
  'CAM Expiry Health Check',
  'LMM vs UBS Mismatch',
  'FD Exceptions',
  'Stock Statement Health Check',
  'Insurance Expiry Health Check',
  'Legal Document Health Check',
];

const masterReassignReasons = [
  'Incorrect CPU mapping',
  'Incorrect team mapping',
  'Workload rebalancing',
  'Requires specialist review',
  'Raised in error',
];

/// The lists as `data`, for a stubbed response.
const masterDataPayload = <String, List<String>>{
  'cpus': masterCpus,
  'teams': masterTeams,
  'exceptionCategories': masterExceptionCategories,
  'healthCheckCategories': masterHealthCheckCategories,
  'reassignReasons': masterReassignReasons,
};

/// A `GET /getMasterData` response body, enveloped as the server sends it.
String masterDataBody() => jsonEncode({
  'code': 0,
  'message': 'Master Data Loaded',
  'success': true,
  'data': masterDataPayload,
});

/// Fills [MasterData] without going through a call.
///
/// Pair it with `addTearDown(MasterData.reset)` so the next test starts from
/// the empty cache the app itself starts from — a test that only passes
/// because an earlier one loaded the lists is not testing anything.
void seedMasterData() {
  MasterData.apply(
    const MasterDataResponse(
      cpus: masterCpus,
      teams: masterTeams,
      exceptionCategories: masterExceptionCategories,
      healthCheckCategories: masterHealthCheckCategories,
      reassignReasons: masterReassignReasons,
    ),
  );
}
