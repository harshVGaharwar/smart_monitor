import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../models/pending_case.dart';
import '../services/cases_file_parser.dart';
import '../services/file_download.dart';
import '../services/file_drop.dart';
import '../services/pending_case_export.dart';
import 'validation_results_table.dart';

/// Which of the three screens the upload flow is showing.
enum _Stage { idle, validating, results }

/// Bulk case upload: pick a spreadsheet, watch it validate against the master
/// data, then review every row before importing the clean ones.
class UploadCasesView extends StatefulWidget {
  const UploadCasesView({super.key});

  @override
  State<UploadCasesView> createState() => _UploadCasesViewState();
}

class _UploadCasesViewState extends State<UploadCasesView>
    with SingleTickerProviderStateMixin {
  // Legacy .xls is not a zip archive and cannot be read, so the picker does
  // not offer it; a file dropped in anyway gets the parser's "save it as
  // .xlsx" message rather than a silent failure.
  static const _allowedExtensions = ['xlsx', 'csv'];
  static const _droppableExtensions = ['xlsx', 'xls', 'csv'];
  static const _maxUploadBytes = 25 * 1024 * 1024; // 25 MB

  /// The columns checked against the master database. Everything else is
  /// imported as-is, so only these can put a row into the error state.
  static const _validatedFields = [
    'Health Check Category',
    'Exception Category',
    'CPU',
    'Actionable Team',
  ];

  /// Columns every row of the file must provide.
  static const _requiredColumns = [
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

  /// Shown in the results table when the file carries them, blank when it does
  /// not — a file without these still uploads.
  static const _additionalColumns = [
    'Segment',
    'Facility Sr. no',
    'LS SRM Date',
  ];

  /// Built eagerly in [initState], not lazily: a view disposed without ever
  /// reaching the validating stage would otherwise construct the controller
  /// from inside [dispose], and creating a Ticker needs a live element.
  late final AnimationController _progress;

  _Stage _stage = _Stage.idle;
  String? _error;

  /// Name of the file being validated or reported on.
  String _fileName = '';

  UploadOutcome? _outcome;

  /// Rows ticked in the report — any row, clean or flagged.
  Set<PendingCase> _selected = {};
  DateTime _validatedAt = DateTime.now();

  /// Locates the drop zone so a page-level drop can be tested against it.
  final _dropzoneKey = GlobalKey();
  late final FileDropSubscription _drop;
  bool _draggingOver = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _drop = listenForFileDrop(
      hitTest: _isOverDropzone,
      onHover: (hovering) {
        if (mounted) setState(() => _draggingOver = hovering);
      },
      onFile: (name, size, bytes) {
        if (mounted) _acceptDropped(name, size, bytes);
      },
    );
  }

  @override
  void dispose() {
    _drop.cancel();
    _progress.dispose();
    super.dispose();
  }

  /// Only the idle stage shows a drop zone, and only its painted bounds count
  /// as a target — a drop anywhere else falls through to the browser.
  bool _isOverDropzone(double x, double y) {
    if (_stage != _Stage.idle) return false;
    final box = _dropzoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(Offset(x, y));
  }

  // --- Picking and validating ---------------------------------------------

  Future<void> _chooseFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Select the cases file',
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        // Web has no file paths, so bytes are the only way to read a file.
        withData: true,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = 'Could not open the file picker: $e';
      });
      return;
    }
    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'Could not read ${file.name}.';
      });
      return;
    }
    await _accept(name: file.name, size: file.size, bytes: bytes);
  }

  /// A dropped file bypasses the picker's extension filter, so the type is
  /// checked here as well as the size.
  Future<void> _acceptDropped(String name, int size, Uint8List bytes) async {
    final ext = name.split('.').last.toLowerCase();
    if (!_droppableExtensions.contains(ext)) {
      setState(() {
        _stage = _Stage.idle;
        _error = '$name is not a spreadsheet — upload a .xlsx or .csv file.';
      });
      return;
    }
    await _accept(name: name, size: size, bytes: bytes);
  }

  /// Shared by the picker and the drop target: validate, then run the file
  /// through the validating stage.
  Future<void> _accept({
    required String name,
    required int size,
    required Uint8List bytes,
  }) async {
    if (size > _maxUploadBytes) {
      setState(() {
        _stage = _Stage.idle;
        _error = '$name is ${_fmtSize(size)} — the limit is 25 MB.';
      });
      return;
    }

    setState(() {
      _stage = _Stage.validating;
      _error = null;
      _fileName = name;
      _outcome = null;
      _selected = {};
    });

    _progress
      ..reset()
      ..forward();

    // Parsing is synchronous work on this isolate, so let the card paint one
    // frame before it starts or the animation never appears.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    UploadOutcome outcome;
    try {
      outcome = CasesFileParser.parse(fileName: name, bytes: bytes);
    } on CasesFileException catch (e) {
      _failValidation(e.message);
      return;
    } on Object catch (e) {
      _failValidation('Could not read $name: $e');
      return;
    }
    if (!mounted) return;

    // Hold on the card until the bar reaches 100%, so it never cuts away
    // mid-progress on a small file.
    if (_progress.isAnimating) {
      await _progress.forward().orCancel.catchError((_) {});
    }
    if (!mounted) return;

    setState(() {
      _stage = _Stage.results;
      _outcome = outcome;
      _validatedAt = DateTime.now();
    });
  }

  void _failValidation(String message) {
    if (!mounted) return;
    _progress.stop();
    setState(() {
      _stage = _Stage.idle;
      _error = message;
      _outcome = null;
    });
  }

  // --- Result actions -----------------------------------------------------

  void _reset() {
    _progress.stop();
    setState(() {
      _stage = _Stage.idle;
      _outcome = null;
      _error = null;
      _fileName = '';
      _selected = {};
    });
  }

  void _downloadErrors() {
    final outcome = _outcome;
    if (outcome == null) return;
    // The tick boxes drive removal too, so a selection can hold clean rows;
    // only the flagged ones belong in an error file. No flagged row ticked
    // means "all of them" — the common case is wanting the whole error set to
    // fix in Excel.
    final ticked = outcome.failed.where(_selected.contains).toList();
    final rows = ticked.isEmpty ? outcome.failed : ticked;
    if (rows.isEmpty) return;

    downloadBytes(
      bytes: PendingCaseExport.buildCsvBytes(rows),
      filename: PendingCaseExport.fileName(),
    );
    _snack('Downloaded ${rows.length} error row(s)', AppColors.primary);
  }

  /// Drops one row, from its own delete button. It leaves the report and is
  /// not part of what [_submit] uploads.
  ///
  /// Removal is immediate and the snackbar carries the undo, rather than a
  /// confirmation dialog in front of every row — clearing a dozen rows should
  /// not cost a dozen prompts.
  void _deleteRow(PendingCase row) {
    final outcome = _outcome;
    if (outcome == null) return;
    final index = outcome.removeRow(row);
    if (index < 0) return;

    setState(() => _selected = _selected.difference({row}));
    _snack(
      'Row ${row.id} removed',
      AppColors.primary,
      action: SnackBarAction(
        label: 'Undo',
        textColor: Colors.white,
        onPressed: () => setState(() => outcome.restore(index, row)),
      ),
    );
  }

  /// Uploads whatever survived the review: the rows still in the report that
  /// pass validation. Removed rows are already gone from [outcome], and rows
  /// still carrying errors are left behind.
  void _submit() {
    final outcome = _outcome;
    if (outcome == null) return;
    final valid = outcome.valid;
    if (valid.isEmpty) {
      _snack('No valid records to import.', AppColors.danger);
      return;
    }
    final skipped = outcome.failed.length;
    _snack(
      skipped == 0
          ? '${valid.length} case(s) imported'
          : '${valid.length} case(s) imported · $skipped left unresolved',
      AppColors.success,
    );
    _reset();
  }

  void _snack(String message, Color color, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      // One at a time: deleting several rows in a row would otherwise queue
      // the undos behind each other, each pointing at an older removal.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: Duration(seconds: action == null ? 2 : 5),
          content: Text(message),
          action: action,
        ),
      );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // --- Layout -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerBar(isMobile),
        Expanded(
          child: Padding(
            // The bar above is full-bleed, so the inset starts here.
            padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 18,
              14,
              isMobile ? 12 : 18,
              14,
            ),
            child: switch (_stage) {
              _Stage.idle => _idleBody(isMobile),
              _Stage.validating => Center(child: _validatingCard(isMobile)),
              _Stage.results => _resultsBody(),
            },
          ),
        ),
      ],
    );
  }

  /// Full-width white strip with a hairline divider, so the section reads as
  /// having its own top bar rather than a card floating on the canvas.
  Widget _headerBar(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        isMobile ? 14 : 18,
        isMobile ? 14 : 24,
        isMobile ? 14 : 18,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: _header(isMobile),
    );
  }

  String get _subtitle => switch (_stage) {
    _Stage.validating => 'Validating your file against master data…',
    _ =>
      'Import Health Check exception records from Excel and validate them '
          'before importing into the system.',
  };

  Widget _header(bool isMobile) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Upload Document',
              style: TextStyle(
                fontSize: isMobile ? 19 : 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
            if (_stage == _Stage.results && _fileName.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(child: _fileChip()),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          _subtitle,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    if (_stage != _Stage.results) return title;

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [title, _resultActions()],
    );
  }

  Widget _fileChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        _fileName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          fontFamily: 'monospace',
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _resultActions() {
    final outcome = _outcome;
    final hasErrors = outcome != null && outcome.failed.isNotEmpty;
    final canSubmit = outcome != null && outcome.valid.isNotEmpty;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _outlinedAction(label: 'Reset', onTap: _reset),
        _outlinedAction(
          label: 'Upload Again',
          icon: Icons.file_upload_outlined,
          onTap: _chooseFile,
        ),
        _outlinedAction(
          label: 'Download Error Data',
          icon: Icons.file_download_outlined,
          onTap: hasErrors ? _downloadErrors : null,
        ),
        _filledAction(
          label: 'Submit Data',
          icon: Icons.check_circle_outline_rounded,
          onTap: canSubmit ? _submit : null,
        ),
      ],
    );
  }

  // --- Idle ---------------------------------------------------------------

  Widget _idleBody(bool isMobile) {
    // The scroll view sizes to its child, so a bare Center would have no spare
    // height to work with and the card would sit at the top. Floor the child
    // at the viewport height instead: it centres while there is room, and
    // still scrolls once the expanded column list outgrows the screen.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    _errorBanner(),
                    const SizedBox(height: 14),
                  ],
                  _dropzone(isMobile),
                  const SizedBox(height: 16),
                  _validatedFieldsPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropzone(bool isMobile) {
    return Material(
      key: _dropzoneKey,
      color: _draggingOver ? AppColors.infoBg : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _chooseFile,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            // Firms up under a dragged file so the target is unmistakable.
            color: _draggingOver
                ? AppColors.primaryLight
                : AppColors.primaryLight.withValues(alpha: 0.6),
            radius: 14,
            width: _draggingOver ? 2.2 : 1.6,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: isMobile ? 36 : 54,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    size: 30,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Upload Health Check Excel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  // Wraps after "Health" as in the design rather than running
                  // the full width of the zone.
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    _draggingOver
                        ? 'Drop the file to start validating.'
                        : 'Drag & drop your Excel file or browse to upload '
                              'Health Check exception records for validation.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '.xlsx · .xls · .csv · Max 25 MB',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Validating ---------------------------------------------------------

  Widget _validatingCard(bool isMobile) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 22 : 34,
          vertical: 34,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppTheme.cardShadow,
        ),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final percent = (_progress.value * 100).round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: AppColors.infoBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: RotationTransition(
                      turns: _progress,
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 27,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Validating $_fileName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Checking Health Check Category, Exception Category, CPU '
                  'and Actionable Team against master records…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress.value,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.primaryLight,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$percent% complete',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Results ------------------------------------------------------------

  Widget _resultsBody() {
    final outcome = _outcome!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statsStrip(outcome),
        const SizedBox(height: 12),
        Expanded(
          child: ValidationResultsTable(
            key: ValueKey(outcome),
            rows: outcome.rows,
            onSelectionChanged: (s) => setState(() => _selected = s),
            // Correcting a cell changes the counts above, so rebuild them.
            onRowsChanged: () => setState(() {}),
            onDeleteRow: _deleteRow,
          ),
        ),
      ],
    );
  }

  Widget _statsStrip(UploadOutcome outcome) {
    final valid = outcome.uploaded;
    final errors = outcome.failed.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _stat(outcome.processed, 'Processed', AppColors.textPrimary),
          _dot(),
          _stat(valid, 'Included', AppColors.success),
          _dot(),
          _stat(errors, 'Validation Errors', AppColors.danger),
          _dot(),
          _stat(valid, 'Ready to Import', AppColors.info),
          // Only once something has been dropped, so the strip stays the same
          // as before on an untouched report.
          if (outcome.removed > 0) ...[
            _dot(),
            _stat(outcome.removed, 'Removed', AppColors.textMuted),
          ],
          _dot(),
          const Text(
            'Only valid records will be imported on submit',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.refresh_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                'Updated ${_relativeTime(_validatedAt)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(int value, String label, Color color) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => const Text(
    '·',
    style: TextStyle(fontSize: 15, color: AppColors.textMuted),
  );

  /// Coarse on purpose — it only needs to tell the user whether what they are
  /// looking at is stale.
  static String _relativeTime(DateTime when) {
    final seconds = DateTime.now().difference(when).inSeconds;
    if (seconds < 45) return 'just now';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    final hours = (minutes / 60).round();
    return '$hours hour${hours == 1 ? '' : 's'} ago';
  }

  // --- Shared pieces ------------------------------------------------------

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
        ],
      ),
    );
  }

  /// The three fields checked against master data, plus the full column
  /// contract folded away behind a disclosure so the resting screen stays as
  /// designed while the requirements are still one tap away.
  Widget _validatedFieldsPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VALIDATED FIELDS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final field in _validatedFields) _fieldPill(field)],
          ),
          const SizedBox(height: 16),
          const Text(
            'These fields are checked against the master database. All other '
            'columns are imported as-is from the Excel file.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          _columnsDisclosure(),
        ],
      ),
    );
  }

  Widget _fieldPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.warning,
        ),
      ),
    );
  }

  Widget _columnsDisclosure() {
    return Theme(
      // The default divider lines would cut the card in half; the panel is
      // part of the same block, not a separate section.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        visualDensity: VisualDensity.compact,
        iconColor: AppColors.primaryLight,
        collapsedIconColor: AppColors.textMuted,
        title: const Text(
          'View required columns',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLight,
          ),
        ),
        children: [
          const Text(
            'Columns required in the file for each case',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final col in _requiredColumns) _bullet(col),
          const SizedBox(height: 16),
          const Text(
            'Additional columns',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final col in _additionalColumns) _bullet(col),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 10),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outlinedAction({
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
  }) {
    final enabled = onTap != null;
    final fg = enabled ? AppColors.textPrimary : AppColors.textMuted;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filledAction({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.primaryLight : AppColors.borderStrong,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the dropzone's dashed outline. Flutter has no dashed `BorderSide`, so
/// the path is stroked in fixed-length segments by hand.
class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 7;
  static const double _gap = 5;

  final Color color;
  final double radius;
  final double width;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    this.width = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}
