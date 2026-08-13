/// The rows a signed-in template is answerable for.
///
/// `status` is the bucket that template works, and `ownerColumn` is the column
/// on the case carrying whose record it is — the maker raised it, the checker
/// is handling it. A queue is both together: the status alone would hand a
/// maker every record waiting on the health check rather than their own.
typedef RoleQueue = ({String status, String ownerColumn});

/// The queue [role] works, or null for a template this build cannot name.
///
/// A null is answered with no rows rather than with everybody's — role text is
/// free-form on the wire, and a spelling this server does not know must not
/// fall through to somebody else's records.
///
/// Matched forgivingly: the text is the sign-in service's, not this server's,
/// so `Health Check` casing and punctuation do not decide whether a user gets
/// their rows. The client normalises the same way — see
/// `PendingCase.matchOption`.
RoleQueue? queueForRole(String role) => switch (_normalise(role)) {
  'maker' => (status: 'Pending with Health Checker', ownerColumn: 'maker'),
  'checker' => (status: 'Pending with CPU', ownerColumn: 'checker'),
  _ => null,
};

/// Whether [role] is the health check side — the only template that signs a
/// record off.
///
/// Read the same forgiving way [queueForRole] reads it, and false for a
/// template this server cannot name: verifying is not something to fall
/// through to on a spelling nobody recognises.
bool isMakerRole(String role) => _normalise(role) == 'maker';

/// Whether [role] is the CPU side — the template that approves a record on to
/// the health check.
///
/// Read the same way [isMakerRole] is, and false for a template this server
/// cannot name.
bool isCheckerRole(String role) => _normalise(role) == 'checker';

/// The two columns [queueForRole] can name. Anything else must never reach a
/// SQL statement — see `CasesRepository.casesForOwner`.
const ownerColumns = <String>{'maker', 'checker'};

String _normalise(String s) =>
    s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
