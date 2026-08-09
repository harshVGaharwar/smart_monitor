import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../data/mock_data.dart';
import '../models/case_item.dart';
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

/// Right-hand drawer showing one record across six tabs.
class CaseDetailPanel extends StatefulWidget {
  final CaseItem caseItem;
  final CaseDetailTab initialTab;
  final String currentUser;

  /// Fired with the edited record so the dashboard can refresh its row.
  final ValueChanged<CaseItem> onChanged;

  final VoidCallback onClose;

  /// Used to write a verified record back. Supplied by the dashboard, which
  /// already owns a client; tests pass a stand-in.
  final Api api;

  const CaseDetailPanel({
    super.key,
    required this.caseItem,
    required this.initialTab,
    required this.currentUser,
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

  late CaseStatus _verifyStatus;
  String? _newCpu;
  String? _newTeam;
  String? _reassignReason;

  /// Files staged on the Verify and Reassign tabs before submitting.
  final List<PlatformFile> _verifyFiles = [];

  /// True while the verify write is in flight, so the button cannot be hit
  /// twice and post the same case again.
  bool _verifying = false;
  final List<PlatformFile> _reassignFiles = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _case = widget.caseItem;
    _verifyStatus = _assignable(_case.status);
    _tabs = TabController(
      length: CaseDetailTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CaseDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The drawer is reused across rows; reset when a different record opens.
    if (oldWidget.caseItem.exceptionCode != widget.caseItem.exceptionCode) {
      _case = widget.caseItem;
      _verifyStatus = _assignable(_case.status);
      _verifyCommentCtrl.clear();
      _reassignCommentCtrl.clear();
      _commentCtrl.clear();
      _newCpu = null;
      _newTeam = null;
      _reassignReason = null;
      _verifyFiles.clear();
      _reassignFiles.clear();
      _error = null;
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _tabs.index = widget.initialTab.index;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _verifyCommentCtrl.dispose();
    _reassignCommentCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  String get _displayName {
    final u = widget.currentUser.isEmpty ? 'ninad.thakur' : widget.currentUser;
    return u
        .replaceAll('.', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// The status the Verify dropdown should start on.
  ///
  /// A record carrying a legacy status has nothing to select — the dropdown
  /// asserts on a value outside its options — so it falls back to the first
  /// one a reviewer can actually assign.
  static CaseStatus _assignable(CaseStatus status) =>
      CaseStatus.assignable.contains(status)
          ? status
          : CaseStatus.assignable.first;

  void _apply(CaseItem updated) {
    setState(() => _case = updated);
    widget.onChanged(updated);
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

  Future<void> _pickFiles(List<PlatformFile> into) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Attach supporting documents',
        type: FileType.custom,
        allowedExtensions: AppConstants.documentExtensions,
        allowMultiple: true,
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
    final documents = [
      ..._case.documents,
      for (final f in _verifyFiles)
        CaseDocument(
          name: f.name,
          uploadedBy: _displayName,
          uploadedAt: now,
          version: 'v${_case.documents.length + 1}.0',
        ),
    ];
    final comment = _verifyCommentCtrl.text.trim();

    final updated = _case.copyWith(
      status: _verifyStatus,
      documents: documents,
      comments:
          comment.isEmpty
              ? _case.comments
              : [
                CaseComment(author: _displayName, text: comment, at: now),
                ..._case.comments,
              ],
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
    setState(() => _verifying = true);
    try {
      await widget.api.updateCase(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _toast(e.message, success: false);
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _toast('Could not save the status: $e', success: false);
      return;
    }
    if (!mounted) return;

    setState(() {
      _verifying = false;
      _verifyFiles.clear();
    });
    _apply(updated);
    _verifyCommentCtrl.clear();
    _toast('${_case.exceptionCode} set to ${_verifyStatus.label}');
    // The record is done being reviewed, so the drawer gets out of the way and
    // hands the grid back. Last, after the row has already been updated: closing
    // drops the selection, and anything touching state past this point is gone.
    widget.onClose();
  }

  void _confirmReassignment() {
    if (_newCpu == null || _newTeam == null) {
      _toast('Select both a CPU and a team.', success: false);
      return;
    }
    final now = DateTime.now();
    final comment = _reassignCommentCtrl.text.trim();
    final note = _reassignReason ?? 'Reassigned to $_newTeam.';

    _apply(
      _case.copyWith(
        cpu: _newCpu,
        team: _newTeam,
        // Back to square one for whoever picks it up, which is the same status
        // the server gives a case nobody has reviewed yet.
        status: CaseStatus.pendingWithCpu,
        documents: [
          ..._case.documents,
          for (final f in _reassignFiles)
            CaseDocument(
              name: f.name,
              uploadedBy: _displayName,
              uploadedAt: now,
              version: 'v${_case.documents.length + 1}.0',
            ),
        ],
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
      _newCpu = null;
      _newTeam = null;
      _reassignReason = null;
      _reassignFiles.clear();
    });
    _toast('${_case.exceptionCode} reassigned');
  }

  void _postComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();

    _apply(
      _case.copyWith(
        comments: [
          ..._case.comments,
          CaseComment(author: _displayName, text: text, at: now),
        ],
        activity: [
          ..._case.activity,
          CaseActivity(
            type: ActivityType.commentAdded,
            actor: _displayName,
            at: now,
            comment: text,
          ),
        ],
        lastActivity: ActivityEntry(type: ActivityType.commentAdded, at: now),
        updatedNote: text,
        updatedBy: _displayName,
        updatedAt: now,
      ),
    );
    _commentCtrl.clear();
  }

  Future<void> _uploadDocument() async {
    final before = _case.documents.length;
    final staged = <PlatformFile>[];
    await _pickFiles(staged);
    if (!mounted || staged.isEmpty) return;

    final now = DateTime.now();
    _apply(
      _case.copyWith(
        documents: [
          ..._case.documents,
          for (var i = 0; i < staged.length; i++)
            CaseDocument(
              name: staged[i].name,
              uploadedBy: _displayName,
              uploadedAt: now,
              version: 'v${before + i + 1}.0',
            ),
        ],
        activity: [
          ..._case.activity,
          CaseActivity(
            type: ActivityType.documentUploaded,
            actor: _displayName,
            at: now,
          ),
        ],
        lastActivity: ActivityEntry(
          type: ActivityType.documentUploaded,
          at: now,
        ),
        updatedNote: 'Document uploaded for reference.',
        updatedBy: _displayName,
        updatedAt: now,
      ),
    );
    _toast('${staged.length} document(s) attached');
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
            children: [
              _basicInfoTab(),
              _verifyTab(),
              _reassignTab(),
              _commentsTab(),
              _documentsTab(),
              _activityTab(),
            ],
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
              for (final tab in CaseDetailTab.values)
                Tab(text: '${tab.label}${_tabSuffix(tab)}'),
            ],
          ),
        ],
      ),
    );
  }

  String _tabSuffix(CaseDetailTab tab) => switch (tab) {
    CaseDetailTab.comments => ' (${_case.comments.length})',
    CaseDetailTab.documents => ' (${_case.documents.length})',
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
        _inputLabel('CHANGE STATUS'),
        const SizedBox(height: 8),
        _dropdown<CaseStatus>(
          value: _verifyStatus,
          hint: 'Select status',
          // Only the two a reviewer can hand a case on to. The older statuses
          // still render on a record that carries one, but cannot be chosen.
          options: CaseStatus.assignable,
          labelOf: (s) => s.label,
          onChanged: (v) => setState(() => _verifyStatus = v ?? _verifyStatus),
        ),
        const SizedBox(height: 20),
        _inputLabel('VERIFICATION COMMENT'),
        const SizedBox(height: 8),
        _multilineField(_verifyCommentCtrl, 'Add verification notes...'),
        const SizedBox(height: 20),
        _inputLabel('SUPPORTING DOCUMENTS'),
        const SizedBox(height: 8),
        _dropZone(_verifyFiles),
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
    final ready = _newCpu != null && _newTeam != null;
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
          options: MockData.cpus,
          labelOf: (cpu) => cpu,
          onChanged: (v) => setState(() => _newCpu = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('NEW TEAM'),
        const SizedBox(height: 8),
        _dropdown<String>(
          value: _newTeam,
          hint: 'Select Team...',
          options: MockData.teams,
          labelOf: (team) => team,
          onChanged: (v) => setState(() => _newTeam = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('REASON'),
        const SizedBox(height: 8),
        _dropdown<String>(
          value: _reassignReason,
          hint: 'Select reason...',
          options: MockData.reassignReasons,
          labelOf: (reason) => reason,
          onChanged: (v) => setState(() => _reassignReason = v),
        ),
        const SizedBox(height: 20),
        _inputLabel('COMMENT'),
        const SizedBox(height: 8),
        _multilineField(_reassignCommentCtrl, 'Add reassignment note...'),
        const SizedBox(height: 20),
        _inputLabel('UPLOAD DOCUMENTS'),
        const SizedBox(height: 8),
        _dropZone(_reassignFiles),
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
        Expanded(
          child:
              _case.comments.isEmpty
                  ? _emptyState('No comments yet.')
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    itemCount: _case.comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 18),
                    itemBuilder: (_, i) => _commentTile(_case.comments[i]),
                  ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Container(
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _multilineField(
                _commentCtrl,
                'Add a comment...',
                minLines: 2,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _uploadDocument,
                    icon: const Icon(Icons.attach_file_rounded, size: 17),
                    label: const Text('Attach files'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _primaryButton(
                    label: 'Post Comment',
                    icon: Icons.send_rounded,
                    color: AppColors.primaryLight,
                    expand: false,
                    onTap:
                        _commentCtrl.text.trim().isEmpty ? null : _postComment,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
        Align(
          alignment: Alignment.centerRight,
          child: _primaryButton(
            label: 'Upload Document',
            icon: Icons.add_rounded,
            color: AppColors.primaryLight,
            expand: false,
            onTap: _uploadDocument,
          ),
        ),
        const SizedBox(height: 18),
        if (_case.documents.isEmpty)
          _emptyState('No documents attached.')
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
                for (var i = 0; i < _case.documents.length; i++) ...[
                  const Divider(height: 1, color: AppColors.border),
                  _documentRow(_case.documents[i], i),
                ],
              ],
            ),
          ),
      ],
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

  Widget _dropZone(List<PlatformFile> staged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _pickFiles(staged),
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
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
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
        ),
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
