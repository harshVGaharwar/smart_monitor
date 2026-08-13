import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../data/master_data.dart';
import '../models/add_comment_request.dart';
import '../models/case_item.dart';
import '../models/get_comments_request.dart';
import '../models/get_documents_request.dart';
import '../models/pending_case.dart';
import '../models/reassign_request.dart';
import '../models/reassign_response.dart';
import '../models/verify_request.dart';
import '../models/user_rights.dart';
import '../services/case_api.dart';
import '../theme/app_theme.dart';
import 'searchable_dropdown.dart';
import 'status_badge.dart';

/// Tabs of the case detail drawer, in display order. Public so the grid's
/// action icons can open the drawer straight onto Verify or Reassign.
enum CaseDetailTab {
  basicInfo('Basic Info'),
  verify('Verify'),
  reassign('Reassign'),
  comments('Comments'),
  documents('Documents'),
  activity('Activity');

  final String label;
  const CaseDetailTab(this.label);
}

/// The tabs [rights] unlock, in enum order.
///
/// Basic Info, Comments and Documents are everyone's — they only read, and
/// every template may comment. Verify and Reassign are the two tabs that
/// change a record, so each appears only for the templates granted it: Verify
/// for the health check side, Reassign for the CPU side.
///
/// Activity is off for now — for both templates, and so for the row actions
/// too, which gate on this same list. The tab's own code is left in place;
/// putting it back is adding the line below rather than rebuilding it.
List<CaseDetailTab> tabsFor(UserRights rights) => [
  CaseDetailTab.basicInfo,
  if (rights.canVerify) CaseDetailTab.verify,
  if (rights.canReassign) CaseDetailTab.reassign,
  CaseDetailTab.comments,
  CaseDetailTab.documents,
];

/// Right-hand drawer showing one record, across the tabs its reader may open.
class CaseDetailPanel extends StatefulWidget {
  final CaseItem caseItem;
  final CaseDetailTab initialTab;

  /// The tabs to offer, from [tabsFor]. Passed in rather than derived here:
  /// the grid gates its row actions on the same list, and deriving it twice is
  /// how the two drift apart.
  final List<CaseDetailTab> tabs;

  final String currentUser;

  /// The signed-in user's employee code, and the template they are working
  /// under. Both ride on every comment: the thread records who said a thing
  /// and which side of the handover they said it from.
  final String userId;
  final String role;

  /// Fired with the edited record so the dashboard can refresh its row.
  final ValueChanged<CaseItem> onChanged;

  final VoidCallback onClose;

  /// Used to read and write the thread, and to write a verified record back.
  /// Supplied by the dashboard, which already owns a client; tests pass a
  /// stand-in.
  final Api api;

  const CaseDetailPanel({
    super.key,
    required this.caseItem,
    required this.initialTab,
    required this.tabs,
    required this.currentUser,
    required this.userId,
    required this.role,
    required this.onChanged,
    required this.onClose,
    required this.api,
  });

  @override
  State<CaseDetailPanel> createState() => _CaseDetailPanelState();
}

class _CaseDetailPanelState extends State<CaseDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late CaseItem _case;

  final _verifyCommentCtrl = TextEditingController();
  final _reassignCommentCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  /// Where the record is going. Both start on where it already is, so the
  /// reviewer changes the one that is wrong rather than restating both.
  String? _newCpu;
  String? _newTeam;
  String? _reassignReason;

  /// True while the verify write is in flight, so the button cannot be hit
  /// twice and post the same case again.
  bool _verifying = false;

  /// The same, for the routing write.
  bool _reassigning = false;

  /// Files staged on the Reassign tab before submitting. Supporting documents
  /// are attached from the Documents tab instead, where they land on the
  /// record straight away.
  final List<PlatformFile> _reassignFiles = [];

  /// Files staged against the comment being written. They go up with it, so a
  /// note and the evidence behind it land as one act rather than two.
  final List<PlatformFile> _commentFiles = [];
  String? _error;

  /// The thread as the server holds it. Loaded rather than carried on the
  /// record: comments outlive the imports that overwrite a case, so the
  /// service is the only place the whole thread exists.
  List<CaseComment> _comments = const [];
  bool _loadingComments = true;

  /// Why the thread could not be read, shown in place of it with a retry.
  String? _commentsError;

  /// The files as the server holds them. Loaded for the same reason the thread
  /// is: an attachment outlives the import that overwrites its case, so a panel
  /// showing only what this session uploaded would open empty on a record
  /// people have been attaching evidence to for a week.
  ///
  /// Read by everyone — whichever side attached a file, the other side has to
  /// be able to see it, so this is not gated on a template.
  List<CaseDocument> _documents = const [];
  bool _loadingDocuments = true;

  /// Why the files could not be read, shown in place of them with a retry.
  String? _documentsError;

  /// True while a comment is in flight, so the button cannot post it twice.
  bool _posting = false;

  /// What the CPU side is doing with the record it is commenting on. Null
  /// until they choose — and null for good on every other template, which has
  /// no such decision to make here. The post button stays dead until a checker
  /// chooses: passing a record on is not something to do by not noticing a
  /// dropdown.
  ApprovalStatus? _approval;

  @override
  void initState() {
    super.initState();
    _case = widget.caseItem;
    _readAssignment();
    _tabs = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: _indexOf(widget.initialTab),
    );
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _loadComments();
    _loadDocuments();
  }

  @override
  void didUpdateWidget(CaseDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The drawer is reused across rows; reset when a different record opens.
    if (oldWidget.caseItem.exceptionCode != widget.caseItem.exceptionCode) {
      _case = widget.caseItem;
      _readAssignment();
      _verifyCommentCtrl.clear();
      _reassignCommentCtrl.clear();
      _commentCtrl.clear();
      _newCpu = null;
      _newTeam = null;
      _reassignReason = null;
      _reassignFiles.clear();
      _commentFiles.clear();
      _error = null;
      _comments = const [];
      _documents = const [];
      _approval = null;
      _loadComments();
      _loadDocuments();
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _tabs.index = _indexOf(widget.initialTab);
    }
  }

  /// Where [tab] sits among the offered tabs, or the first one when this
  /// reader has no such tab — a caller may ask for one their role dropped.
  int _indexOf(CaseDetailTab tab) {
    final index = widget.tabs.indexOf(tab);
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _verifyCommentCtrl.dispose();
    _reassignCommentCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  /// Opens the routing dropdowns on the record's own assignment.
  ///
  /// Matched forgivingly against the workflow's lists: a stored value they do
  /// not name leaves the dropdown empty rather than asserting on a value it
  /// cannot show.
  void _readAssignment() {
    _newCpu = PendingCase.matchOption(_case.cpu, MasterData.cpus);
    _newTeam = PendingCase.matchOption(_case.team, MasterData.teams);
  }

  /// Whether the reader is the CPU side, which decides on a record from the
  /// comment box rather than from a tab of its own.
  bool get _isChecker => AppRole.parse(widget.role) == AppRole.checker;

  /// Whether the reader is the health check side, whose decision is the
  /// verify. Only they say anything about `isVerified`; for everyone else it
  /// goes out null, the way `status` does for everyone but the CPU side.
  bool get _isMaker => AppRole.parse(widget.role) == AppRole.maker;

  /// Whether the composer has everything it needs to post.
  bool get _canPost =>
      !_posting &&
      _commentCtrl.text.trim().isNotEmpty &&
      (!_isChecker || _approval != null);

  String get _displayName {
    final u = widget.currentUser.isEmpty ? 'ninad.thakur' : widget.currentUser;
    return u
        .replaceAll('.', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  void _apply(CaseItem updated) {
    setState(() => _case = updated);
    widget.onChanged(updated);
  }

  /// Confirms an action that changed the record, and waits to be dismissed.
  ///
  /// A dialog rather than a toast for these: each one is a decision, most of
  /// them take the row out of the grid, and a message that slides away on its
  /// own is a poor place to say so. Failures stay on the toast — they change
  /// nothing, and the panel is still there to try again in.
  Future<void> _confirmed(String title, String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            title: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 20, 16),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _toast(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 2),
        content: Text(message),
      ),
    );
  }

  // --- Actions ------------------------------------------------------------

  /// Picks the one document a reassignment carries. Singular for the same
  /// reason the comment's is: the key on the wire is.
  Future<void> _pickReassignFile() async {
    final picked = <PlatformFile>[];
    await _pickFiles(picked, allowMultiple: false);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _reassignFiles
        ..clear()
        ..add(picked.first);
    });
  }

  /// Picks the one supporting document a comment carries.
  ///
  /// Single rather than multiple: the wire key is singular, so a second file
  /// would have nowhere to go. Re-picking replaces what was staged, which is
  /// what "choose a different file" means with one slot.
  Future<void> _pickCommentFile() async {
    final picked = <PlatformFile>[];
    await _pickFiles(picked, allowMultiple: false);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _commentFiles
        ..clear()
        ..add(picked.first);
    });
  }

  Future<void> _pickFiles(
    List<PlatformFile> into, {
    bool allowMultiple = true,
  }) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Attach supporting documents',
        type: FileType.custom,
        allowedExtensions: AppConstants.documentExtensions,
        allowMultiple: allowMultiple,
        withData: true,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the file picker: $e');
      return;
    }
    if (!mounted || result == null) return;

    final tooBig =
        result.files
            .where((f) => f.size > AppConstants.maxDocumentBytes)
            .map((f) => f.name)
            .toList();

    setState(() {
      _error =
          tooBig.isEmpty
              ? null
              : '${tooBig.join(', ')} exceeds the 10 MB limit.';
      into.addAll(
        result!.files.where((f) => f.size <= AppConstants.maxDocumentBytes),
      );
    });
  }

  Future<void> _verifyRecord() async {
    if (_verifying) return;
    final now = DateTime.now();
    final comment = _verifyCommentCtrl.text.trim();

    final updated = _case.copyWith(
      // The one outcome this call has. The server sets it too — this is the
      // row on screen catching up, and what moves it out of the queue.
      status: CaseStatus.verified,
      activity: [
        ..._case.activity,
        CaseActivity(
          type: ActivityType.verified,
          actor: _displayName,
          at: now,
          comment: comment,
        ),
      ],
      lastActivity: ActivityEntry(type: ActivityType.verified, at: now),
      updatedNote: comment.isEmpty ? 'Record verified.' : comment,
      updatedBy: _displayName,
      updatedAt: now,
    );

    // Written to the server before the panel claims anything: a status that
    // only ever changed on screen would be gone on the next load, and the
    // reviewer would have no way to tell.
    //
    // Four fields, not the case: the record is the server's, and `clientId` is
    // all it needs to find the row. The comment rides along and lands on the
    // thread, so verifying and saying why stay one act.
    setState(() => _verifying = true);
    try {
      await widget.api.verifyCase(
        VerifyRequest(
          clientId: _case.clientId,
          userId: widget.userId,
          role: widget.role,
          comments: comment,
          // The button has one meaning. A note that decides nothing goes on
          // the Comments tab, which is the tab for it.
          isVerified: true,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _toast(e.message, success: false);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _toast('Could not verify the record: $e', success: false);
      return;
    }
    if (!mounted) return;

    setState(() => _verifying = false);
    _verifyCommentCtrl.clear();
    await _confirmed(
      'Record verified',
      '${_case.exceptionCode} is verified and has left your queue.',
    );
    if (!mounted) return;
    // Last, and the only thing that closes the drawer: the status moved, so
    // the dashboard drops the row from the queue and reads it again. After the
    // dialog, so the row does not vanish behind a message still being read.
    _apply(updated);
  }

  Future<void> _confirmReassignment() async {
    final cpu = _newCpu;
    final team = _newTeam;
    if (cpu == null || team == null) {
      _toast('Select both a CPU and a team.', success: false);
      return;
    }
    if (_reassigning) return;
    final now = DateTime.now();
    final comment = _reassignCommentCtrl.text.trim();
    final note = _reassignReason ?? 'Reassigned to $team.';

    // Written to the server before the panel claims anything: a routing that
    // only ever changed on screen would be gone on the next load, and the
    // record would still be sitting with whoever sent it.
    setState(() => _reassigning = true);
    final ReassignResponse response;
    try {
      response = await widget.api.reassignCase(
        ReassignRequest(
          clientId: _case.clientId,
          userId: widget.userId,
          role: widget.role,
          cpu: cpu,
          team: team,
          reason: _reassignReason ?? '',
          comments: comment,
          document: _attachment(_reassignFiles),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reassigning = false);
      _toast(e.message, success: false);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _reassigning = false);
      _toast('Could not reassign the record: $e', success: false);
      return;
    }
    if (!mounted) return;
    setState(() => _reassigning = false);

    await _confirmed('Reassigned', response.toastText);
    if (!mounted) return;

    _apply(
      _case.copyWith(
        cpu: cpu,
        team: team,
        // Back to square one for whoever picks it up, which is the same status
        // the server gives a case nobody has reviewed yet.
        status: CaseStatus.pendingWithCpu,
        activity: [
          ..._case.activity,
          CaseActivity(
            type: ActivityType.reassigned,
            actor: _displayName,
            at: now,
            comment: comment,
          ),
        ],
        lastActivity: ActivityEntry(type: ActivityType.reassigned, at: now),
        updatedNote: note,
        updatedBy: _displayName,
        updatedAt: now,
      ),
    );

    _reassignCommentCtrl.clear();
    setState(() {
      // The dropdowns follow the record, which has just moved.
      _readAssignment();
      _reassignReason = null;
      _reassignFiles.clear();
    });
  }

  /// Reads the thread for the record on screen.
  ///
  /// Failures are shown in place of the list rather than thrown: the rest of
  /// the panel still works, and the message carries a retry.
  Future<void> _loadComments() async {
    final request = GetCommentsRequest(
      clientId: _case.clientId,
      userId: widget.userId,
    );
    setState(() {
      _loadingComments = true;
      _commentsError = null;
    });

    try {
      final response = await widget.api.fetchComments(request);
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        // Newest first. The service answers oldest first — the order a thread
        // is written in — but a reader opening a record wants the last thing
        // said, not the first, and a long thread would bury it.
        _comments = [
          for (final comment in response.comments.reversed)
            comment.toCaseComment(),
        ];
        _loadingComments = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        _loadingComments = false;
        _commentsError = e.message;
      });
    } on Object catch (e) {
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        _loadingComments = false;
        _commentsError = 'Could not load the comments: $e';
      });
    }
  }

  /// Pulls the case's attachments in, the way [_loadComments] pulls the thread.
  ///
  /// The client id is checked again on the way back for the same reason: the
  /// drawer is reused across rows, and a slow read must not land its answer on
  /// whichever record is open by then.
  Future<void> _loadDocuments() async {
    final request = GetDocumentsRequest(
      clientId: _case.clientId,
      userId: widget.userId,
    );
    setState(() {
      _loadingDocuments = true;
      _documentsError = null;
    });

    try {
      final response = await widget.api.fetchDocuments(request);
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        _documents = [
          for (final document in response.documents) document.toCaseDocument(),
        ];
        _loadingDocuments = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        _loadingDocuments = false;
        _documentsError = e.message;
      });
    } on Object catch (e) {
      if (!mounted || request.clientId != _case.clientId) return;
      setState(() {
        _loadingDocuments = false;
        _documentsError = 'Could not load the documents: $e';
      });
    }
  }

  /// The staged file as something the request can carry, or null when the
  /// note goes up on its own.
  ///
  /// A picked file only has bytes when the picker was asked for them; one that
  /// arrived without is dropped rather than sent as an empty part, which the
  /// service would store as a document nobody can open.
  CommentAttachment? _attachment(List<PlatformFile> staged) {
    if (staged.isEmpty) return null;
    final bytes = staged.first.bytes;
    if (bytes == null) return null;
    return CommentAttachment(filename: staged.first.name, bytes: bytes);
  }

  /// Posts the comment, and whatever was attached to it.
  ///
  /// The text is required and the files are not, so a note can stand on its
  /// own — but a file cannot: there would be nothing saying what it shows.
  ///
  /// The note goes to the server first and the thread is read back after, so
  /// what the panel shows is what is stored — a comment that only ever landed
  /// on screen would be gone on the next open with nobody the wiser.
  Future<void> _postComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _posting) return;
    final now = DateTime.now();
    final staged = [..._commentFiles];

    // One write for the whole box. The note, the document and — for the CPU
    // side — what they decided all go up as the one act they were.
    // Null for anyone but the CPU side: the health check side leaves a note
    // here and signs off on its own tab.
    final decision = _isChecker ? _approval : null;
    final approving = decision == ApprovalStatus.approved;
    setState(() => _posting = true);
    try {
      await widget.api.verifyCase(
        VerifyRequest(
          clientId: _case.clientId,
          userId: widget.userId,
          role: widget.role,
          comments: text,
          // A note from the health check side is them not verifying — which
          // they could have. From anyone else it is not a decision at all.
          isVerified: _isMaker ? false : null,
          status: decision,
          supportDocument: _attachment(staged),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _toast(e.message, success: false);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _toast('Could not post the comment: $e', success: false);
      return;
    }
    if (!mounted) return;
    setState(() => _posting = false);

    // A decision is worth confirming; a note is its own confirmation, since
    // it appears in the thread a line below the box it was typed in.
    if (decision != null) {
      await _confirmed(
        approving ? 'Record approved' : 'Record rejected',
        approving
            ? '${_case.exceptionCode} has gone to the health check side.'
            : '${_case.exceptionCode} stays with you, and your note is on the '
                'record.',
      );
      if (!mounted) return;
    }

    _apply(
      _case.copyWith(
        activity: [
          ..._case.activity,
          CaseActivity(
            type: ActivityType.commentAdded,
            actor: _displayName,
            at: now,
            comment: text,
          ),
          // Only when something was actually attached, so a plain comment
          // still reads as one event in the timeline.
          if (staged.isNotEmpty)
            CaseActivity(
              type: ActivityType.documentUploaded,
              actor: _displayName,
              at: now,
            ),
        ],
        lastActivity: ActivityEntry(type: ActivityType.commentAdded, at: now),
        updatedNote: text,
        updatedBy: _displayName,
        updatedAt: now,
        // An approval hands the record to the health check side, so the row
        // leaves this reader's queue — the dashboard closes the drawer and
        // reads the grid again off this status move. A reject or a plain note
        // decides nothing and leaves both alone.
        status: approving ? CaseStatus.pendingWithHealthChecker : null,
      ),
    );
    _commentCtrl.clear();
    setState(() {
      _commentFiles.clear();
      _approval = null;
    });
    // Last, and not awaited by the caller: the note is already stored, so a
    // slow re-read holds up nothing the user is waiting on. The files are read
    // back with it when any went up, so the Documents tab shows what the server
    // stored rather than a local guess at it.
    await _loadComments();
    if (staged.isNotEmpty) await _loadDocuments();
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        if (_error != null) _errorBanner(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [for (final tab in widget.tabs) _bodyFor(tab)],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _case.exceptionCode,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                    StatusBadge(status: _case.status),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                iconSize: 22,
                color: AppColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _case.customerName,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
              children: [
                const TextSpan(text: 'Client ID: '),
                TextSpan(
                  text: _case.clientId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const TextSpan(text: '  ·  Account: '),
                TextSpan(
                  text: _case.accountNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primaryLight,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primaryLight,
            indicatorWeight: 2.5,
            dividerColor: AppColors.border,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              for (final tab in widget.tabs)
                Tab(text: '${tab.label}${_tabSuffix(tab)}'),
            ],
          ),
        ],
      ),
    );
  }

  /// The body behind [tab]. Keyed rather than positional, so the view and the
  /// bar cannot fall out of step when a role drops a tab from the middle.
  Widget _bodyFor(CaseDetailTab tab) => switch (tab) {
    CaseDetailTab.basicInfo => _basicInfoTab(),
    CaseDetailTab.verify => _verifyTab(),
    CaseDetailTab.reassign => _reassignTab(),
    CaseDetailTab.comments => _commentsTab(),
    CaseDetailTab.documents => _documentsTab(),
    CaseDetailTab.activity => _activityTab(),
  };

  String _tabSuffix(CaseDetailTab tab) => switch (tab) {
    CaseDetailTab.comments => ' (${_comments.length})',
    CaseDetailTab.documents => ' (${_documents.length})',
    _ => '',
  };

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.dangerBg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close_rounded),
            iconSize: 15,
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }

  // --- Tab: Basic info ----------------------------------------------------

  Widget _basicInfoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _sectionLabel('BASIC INFORMATION'),
        const SizedBox(height: 14),
        _fieldGrid([
          ('Client ID', _case.clientId),
          ('Customer Name', _case.customerName),
          ('Account No', _case.accountNo),
          ('Line No', _case.lineNo),
          ('Health Check Category', _case.healthCheckCategory),
          ('Sub Category', _case.subCategory),
          ('Support System', _case.supportSystem),
          ('Core System', _case.coreSystem),
          ('Exception Category', _case.exceptionCategory),
          ('Segment', _case.segment),
          ('Facility Sr No', _case.srNo),
          ('Maker', _case.maker),
          ('Checker', _case.checker),
          ('LSRM Date', _date(_case.lsrmDate)),
        ]),
        const SizedBox(height: 18),
        _field('Reason', _case.reason),
        const SizedBox(height: 24),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 24),
        _sectionLabel('ASSIGNMENT'),
        const SizedBox(height: 14),
        _fieldGrid([
          ('Current CPU', _case.cpu),
          ('Current Team', _case.team),
          ('Assigned By', _case.assignedBy),
          ('Assigned Date', _date(_case.assignedDate)),
          ('Status', _case.status.label),
          ('Priority', _case.priority),
        ]),
      ],
    );
  }

  Widget _fieldGrid(List<(String, String)> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns when there is room; one when the drawer is narrow.
        final twoUp = constraints.maxWidth >= 460;
        if (!twoUp) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in fields) ...[
                _field(f.$1, f.$2),
                const SizedBox(height: 18),
              ],
            ],
          );
        }
        const gap = 24.0;
        final columnWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (final f in fields)
              SizedBox(width: columnWidth, child: _field(f.$1, f.$2)),
          ],
        );
      },
    );
  }

  Widget _field(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value.trim().isEmpty ? '—' : value,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.35,
            color:
                value.trim().isEmpty
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.textSecondary,
    ),
  );

  // --- Tab: Verify --------------------------------------------------------

  Widget _verifyTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _banner(
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.success,
          background: AppColors.successBg,
          title: 'Verification Action',
          body:
              'Review the record details and confirm verification. This will '
              'update the status and create an audit entry.',
        ),
        const SizedBox(height: 22),
        // No status to pick: verifying has one outcome, and offering the
        // record's own queue as a choice was offering to verify it into where
        // it already was.
        _inputLabel('VERIFICATION COMMENT'),
        const SizedBox(height: 8),
        _multilineField(_verifyCommentCtrl, 'Add verification notes...'),
        const SizedBox(height: 24),
        _primaryButton(
          label: 'Verify Record',
          icon: Icons.check_circle_outline_rounded,
          color: AppColors.success,
          onTap: _verifyRecord,
        ),
      ],
    );
  }

  // --- Tab: Reassign ------------------------------------------------------

  Widget _reassignTab() {
    final ready = _newCpu != null && _newTeam != null && !_reassigning;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Assignment',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.primaryLight,
                  ),
                  children: [
                    const TextSpan(text: 'CPU: '),
                    TextSpan(
                      text: _case.cpu.isEmpty ? '—' : _case.cpu,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: '  ·  Team: '),
                    TextSpan(
                      text: _case.team.isEmpty ? '—' : _case.team,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _inputLabel('NEW CPU'),
        const SizedBox(height: 8),
        _dropdown<String>(
          value: _newCpu,
          hint: 'Select CPU...',
          options: MasterData.cpus,
          labelOf: (cpu) => cpu,
          onChanged: (v) => setState(() => _newCpu = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('NEW TEAM'),
        const SizedBox(height: 8),
        _dropdown<String>(
          value: _newTeam,
          hint: 'Select Team...',
          options: MasterData.teams,
          labelOf: (team) => team,
          onChanged: (v) => setState(() => _newTeam = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('REASON'),
        const SizedBox(height: 8),
        _dropdown<String>(
          value: _reassignReason,
          hint: 'Select reason...',
          options: MasterData.reassignReasons,
          labelOf: (reason) => reason,
          onChanged: (v) => setState(() => _reassignReason = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('COMMENT'),
        const SizedBox(height: 8),
        _multilineField(_reassignCommentCtrl, 'Add reassignment note...'),
        const SizedBox(height: 20),
        _inputLabel('UPLOAD DOCUMENT'),
        const SizedBox(height: 8),
        _dropZone(_reassignFiles, onTap: _pickReassignFile),
        const SizedBox(height: 24),
        _primaryButton(
          label: 'Confirm Reassignment',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.primaryLight,
          // Routing is the whole point of the action; without both fields
          // there is nothing to send.
          onTap: ready ? _confirmReassignment : null,
        ),
      ],
    );
  }

  // --- Tab: Comments ------------------------------------------------------

  Widget _commentsTab() {
    return Column(
      children: [
        Expanded(child: _commentsList()),
        const Divider(height: 1, color: AppColors.border),
        Container(
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The CPU side decides here rather than on a tab of its own: the
              // note and what it decided are one act, and this is where the
              // note is written.
              if (_isChecker) ...[
                _inputLabel('ACTION'),
                const SizedBox(height: 8),
                _dropdown<ApprovalStatus>(
                  value: _approval,
                  hint: 'Select an action',
                  options: ApprovalStatus.values,
                  labelOf: (v) => v.action,
                  onChanged: (v) => setState(() => _approval = v),
                ),
                const SizedBox(height: 14),
              ],
              _inputLabel('COMMENTS'),
              const SizedBox(height: 8),
              _multilineField(
                _commentCtrl,
                'Add a comment...',
                minLines: 2,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _inputLabel('SUPPORT DOCUMENTS'),
              const SizedBox(height: 8),
              _dropZone(_commentFiles, onTap: _pickCommentFile),
              const SizedBox(height: 12),
              // No attachment here: a comment is the log entry, and a file
              // belongs on the record itself — the Documents tab is where it
              // is uploaded and where a reader looks for it.
              Align(
                alignment: Alignment.centerRight,
                child: _primaryButton(
                  label: 'Post Comment',
                  icon: Icons.send_rounded,
                  color: AppColors.primaryLight,
                  expand: false,
                  onTap: _canPost ? _postComment : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The thread, or what is standing in for it: the spinner on the first read,
  /// the failure with a retry, or the empty state.
  Widget _commentsList() {
    if (_loadingComments && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _commentsError;
    if (error != null && _comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.danger),
              ),
            ),
            TextButton(
              onPressed: _loadingComments ? null : _loadComments,
              child: Text(_loadingComments ? 'Retrying…' : 'Retry'),
            ),
          ],
        ),
      );
    }

    if (_comments.isEmpty) return _emptyState('No comments yet.');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      itemCount: _comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (_, i) => _commentTile(_comments[i]),
    );
  }

  Widget _commentTile(CaseComment comment) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: comment.avatarColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            comment.initials,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.author,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // Only a reassignment carries one, and it is the first thing
                  // the CPU side wants when a record lands back with them.
                  if (comment.reason.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '· ${comment.reason}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _dateTime(comment.at),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  comment.text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Tab: Documents -----------------------------------------------------

  Widget _documentsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _inputLabel('SUPPORTING DOCUMENTS'),
        const SizedBox(height: 18),
        // No upload here: a document arrives with the comment that explains
        // it, so this tab lists what was attached rather than taking more.
        if (_loadingDocuments && _documents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_documentsError != null && _documents.isEmpty)
          _documentsErrorState(_documentsError!)
        else if (_documents.isEmpty)
          _emptyState('No documents yet. Attach one with a comment.')
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: AppColors.surfaceAlt,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: const [
                      Expanded(flex: 4, child: _DocHeader('DOCUMENT NAME')),
                      Expanded(flex: 3, child: _DocHeader('UPLOADED BY')),
                      Expanded(flex: 3, child: _DocHeader('UPLOAD DATE')),
                      Expanded(flex: 2, child: _DocHeader('VERSION')),
                      SizedBox(width: 36),
                    ],
                  ),
                ),
                for (var i = 0; i < _documents.length; i++) ...[
                  const Divider(height: 1, color: AppColors.border),
                  _documentRow(_documents[i], i),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// A read that failed, said in place of the list with a way to try again.
  Widget _documentsErrorState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: _loadingDocuments ? null : _loadDocuments,
            child: Text(_loadingDocuments ? 'Retrying…' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Widget _documentRow(CaseDocument doc, int index) {
    return Container(
      color: index.isOdd ? AppColors.surfaceAlt : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              doc.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              doc.uploadedBy,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _date(doc.uploadedAt),
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              doc.version,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: AppColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              onPressed: () => _toast('${doc.name} is not available offline'),
              tooltip: 'Download',
              icon: const Icon(Icons.file_download_outlined),
              iconSize: 18,
              color: AppColors.textMuted,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab: Activity ------------------------------------------------------

  Widget _activityTab() {
    if (_case.activity.isEmpty) return _emptyState('No activity recorded.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        _sectionLabel('AUDIT HISTORY'),
        const SizedBox(height: 18),
        for (var i = 0; i < _case.activity.length; i++)
          _activityTile(
            _case.activity[i],
            isLast: i == _case.activity.length - 1,
          ),
      ],
    );
  }

  Widget _activityTile(CaseActivity entry, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.4),
                ),
                child: Icon(
                  entry.type.icon,
                  size: entry.type == ActivityType.created ? 10 : 15,
                  color: entry.type.color,
                ),
              ),
              // Connector, omitted on the last entry so the line does not
              // dangle past the timeline.
              if (!isLast)
                Expanded(child: Container(width: 1.4, color: AppColors.border)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.type.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (entry.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '"${entry.comment}"',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${entry.actor} · ${_dateTime(entry.at, at: true)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Shared pieces ------------------------------------------------------

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color background,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.textSecondary,
    ),
  );

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<T> options,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return SearchableDropdown<T>(
      value: value,
      options: options,
      labelOf: labelOf,
      hint: hint,
      searchHint: 'Search…',
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      iconSize: 20,
      textStyle: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
      hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.textMuted),
      onChanged: onChanged,
    );
  }

  Widget _multilineField(
    TextEditingController controller,
    String hint, {
    int minLines = 3,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines + 3,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
      ),
    );
  }

  /// The dashed "Drop files or browse" target on its own, for the places that
  /// act on the picked files right away rather than staging them.
  Widget _dropTarget({required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: DottedBorderBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_file_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                children: [
                  TextSpan(text: 'Drop files or '),
                  TextSpan(
                    text: 'browse',
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The drop target and whatever is staged under it, each with a remove.
  ///
  /// [onTap] overrides how files are picked — the comment composer takes one
  /// file and replaces it, the reassign tab takes several.
  Widget _dropZone(List<PlatformFile> staged, {VoidCallback? onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropTarget(onTap: onTap ?? () => _pickFiles(staged)),
        for (final file in staged)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => staged.remove(file)),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 15,
                  color: AppColors.textMuted,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    bool expand = true,
  }) {
    final enabled = onTap != null;
    final button = Material(
      color: enabled ? color : AppColors.borderStrong,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _emptyState(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
      ),
    ),
  );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} '
        '${d.year}';
  }

  static String _dateTime(DateTime d, {bool at = false}) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final time =
        '${hour.toString().padLeft(2, '0')}:$minute '
        '${d.hour < 12 ? 'AM' : 'PM'}';
    return at ? '${_date(d)} at $time' : '${_date(d)} · $time';
  }
}

class _DocHeader extends StatelessWidget {
  final String text;
  const _DocHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.textSecondary,
    ),
  );
}

/// Dashed upload target. Flutter has no dashed border, so the dashes are
/// painted directly.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const DottedBorderBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Container(
        width: double.infinity,
        padding: padding,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.borderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3;

    const dash = 6.0;
    const gap = 5.0;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
