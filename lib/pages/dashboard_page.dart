import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../data/master_data.dart';
import '../data/mock_data.dart';
import '../core/api_client.dart';
import '../models/case_item.dart';
import '../models/cases_response.dart';
import '../models/login_response.dart';
import '../models/smart_pointer_request.dart';
import '../models/user_rights.dart';
import '../services/case_api.dart';
import '../services/case_export.dart';
import '../services/file_download.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/case_detail_panel.dart';
import '../widgets/cases_table.dart';
import '../widgets/health_check_header.dart';
import '../widgets/mis_table.dart';
import '../widgets/upload_cases_view.dart';
import 'login_page.dart';

class DashboardPage extends StatefulWidget {
  /// The signed-in session: the token every request carries, and the user
  /// whose menu permissions decide which screens the rail offers.
  final LoginResponse session;

  /// Stand-in for the backend, supplied by tests. When null the page builds
  /// its own client and closes it on dispose.
  final Api? api;

  const DashboardPage({super.key, required this.session, this.api});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _navIndex = 0;

  /// The rail items this user may open. A subset of [kNavItems], so every
  /// index into it has to go through here rather than the catalogue.
  late final List<NavDestination> _navItems;

  /// What this user may do inside the screens their menu gives them.
  late final UserRights _rights;

  /// Whose queue this page reads. The rows the server answers with are already
  /// this user's — the page does not filter them again.
  late final SmartPointerRequest _request;

  /// The case-drawer tabs this user may open. Resolved once and handed to both
  /// the grid and the drawer, so the row actions and the tab bar agree.
  late final List<CaseDetailTab> _detailTabs;

  /// null = follow the breakpoint default; set once the user hits the toggle.
  bool? _sidebarExpanded;

  // Search is the only filtering the page owns; slicing by column is the
  // grid's own job, through the pickers under its headings.
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTime _lastUpdated = DateTime.now();

  /// The cases the grid shows, as `/get-smartpointer` returned them.
  List<CaseItem> _cases = const [];

  /// True while the fetch is in flight. Only blanks the grid on the first
  /// load — a refresh keeps the rows on screen so the page does not flash
  /// empty every time it reloads.
  bool _loading = true;
  bool _loaded = false;

  /// Why the last fetch failed, shown above the grid with a retry.
  String? _loadError;

  /// Why the master lists could not be read, or null when they were.
  ///
  /// Separate from [_loadError] because the two are different states: the
  /// queue can load perfectly while the reference lists do not, and that
  /// dashboard is usable — the rows are all there, it is the drawer's
  /// dropdowns and the upload screen's validation that are not. Blanking the
  /// grid over it would hide working data.
  String? _mastersError;

  /// Only set when the page built the client itself — an injected [Api]
  /// belongs to the caller and must not be closed here.
  ApiClient? _ownedClient;
  late final Api _api;

  /// Record shown in the end drawer, and which of its tabs is open.
  CaseItem? _selectedCase;
  CaseDetailTab _selectedTab = CaseDetailTab.basicInfo;

  @override
  void initState() {
    super.initState();
    _navItems = navItemsFor(widget.session.user.menuList);
    _rights = UserRights.forRole(widget.session.user.role);
    _request = SmartPointerRequest.forUser(widget.session.user);
    _detailTabs = tabsFor(_rights);
    final injected = widget.api;
    if (injected != null) {
      _api = injected;
    } else {
      // Only the client this page owns is given the token; an injected one
      // belongs to the caller, which has its own idea of who is signed in.
      _ownedClient = ApiClient()..setAuthToken(widget.session.token);
      _api = Api(_ownedClient!);
    }
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ownedClient?.close();
    super.dispose();
  }

  /// Pulls the stored cases in, and the master lists alongside them.
  ///
  /// Errors are shown rather than thrown: the rest of the page still works,
  /// and the banner carries the retry.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _mastersError = null;
    });

    // Both go out together rather than one after the other. Neither answer
    // depends on the other, and the grid and the dropdowns its drawer opens
    // are drawn in the same frame.
    final cases = _readCases();
    final masters = _readMasters();

    final (loaded, failure) = await cases;
    final mastersError = await masters;
    if (!mounted) return;

    setState(() {
      _loading = false;
      _mastersError = mastersError;
      if (failure != null) {
        _loadError = failure;
        return;
      }
      _cases = loaded!.cases;
      _loaded = true;
      _lastUpdated = DateTime.now();
    });
  }

  /// The queue, or why it could not be read.
  ///
  /// Catches rather than throws so the two reads can be started together
  /// without either one's failure escaping before the other is awaited.
  Future<(CasesResponse?, String?)> _readCases() async {
    try {
      return (await _api.fetchSmartPointer(_request), null);
    } on ApiException catch (e) {
      return (null, e.message);
    } on Object catch (e) {
      return (null, 'Could not load cases: $e');
    }
  }

  /// Fills [MasterData], and reports why it could not be filled.
  ///
  /// A success carrying nothing is reported as a failure: five empty lists
  /// leave every dropdown blank and flag every uploaded row, which is an
  /// outage whatever the envelope said about it.
  Future<String?> _readMasters() async {
    try {
      final response = await _api.fetchMasterData();
      MasterData.apply(response);
      return response.isEmpty
          ? 'Master data came back empty. CPU, team and category lists are '
              'unavailable.'
          : null;
    } on ApiException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Could not load master data: $e';
    }
  }

  /// The rows on screen, after this user's search.
  ///
  /// Search is the only filtering left here: which records are the user's was
  /// settled by the server, which answered `_request` with their queue and
  /// nothing else. The record total, the summary strip and the CSV all read
  /// this getter, so the three agree with each other and with the grid.
  List<CaseItem> get _visibleCases {
    return _cases.where((c) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final hay =
            '${c.exceptionCode} ${c.clientId} ${c.customerName} '
                    '${c.accountNo} ${c.lineNo} ${c.healthCheckCategory} '
                    '${c.subCategory} ${c.cpu} ${c.team} ${c.status.label}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  /// Summary buckets for the header strip, one per status.
  StatusCounts get _counts => StatusCounts.of(_visibleCases);

  void _refresh() => _load();

  void _exportExcel() {
    final rows = _visibleCases;
    if (rows.isEmpty) return;
    downloadBytes(
      bytes: CaseExport.buildCsvBytes(rows),
      filename: CaseExport.fileName(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        content: Text('Exported ${rows.length} record(s)'),
      ),
    );
  }

  /// The name shown in the rail's account block. The service sends a real
  /// name, so it is used as it arrived; only a response that carried none
  /// falls back to the sign-in username.
  String get _displayName {
    final name = widget.session.user.name.trim();
    return name.isEmpty ? 'Signed in' : name;
  }

  void _openCase(CaseItem c, CaseDetailTab tab) {
    setState(() {
      _selectedCase = c;
      // The drawer clamps too, but a tab this role dropped should not reach it.
      _selectedTab = _detailTabs.contains(tab) ? tab : CaseDetailTab.basicInfo;
    });
    // The end drawer only exists once a record is selected, and this setState
    // has not rebuilt yet. Calling openEndDrawer() now would silently do
    // nothing, so wait for the drawer to be in the tree first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  /// Panel edits are written back to the in-memory list so the row behind the
  /// drawer reflects them immediately.
  void _onCaseChanged(CaseItem updated) {
    final index = _cases.indexWhere(
      (c) => c.exceptionCode == updated.exceptionCode,
    );
    final moved = index >= 0 && _cases[index].status != updated.status;
    if (index >= 0) {
      // Copied rather than mutated in place: the fetched list is replaced
      // wholesale on the next load, and setState needs a new list to notice.
      _cases = [..._cases]..[index] = updated;
    }
    setState(() {
      _selectedCase = updated;
      _lastUpdated = DateTime.now();
    });

    // Verifying, approving or reassigning hands the record on, and whether it
    // is still this user's is the server's answer to give, not a guess to make
    // here — so the drawer closes and the queue is read again. An edit that
    // does not move the status — a comment, a document — leaves both alone.
    //
    // Nothing is said about it here: the panel has already confirmed the
    // action in a dialog the reader dismissed, and repeating it in a toast as
    // the row disappears would be telling them twice.
    if (moved) {
      Navigator.of(context).maybePop();
      _load();
    }
  }

  void _logout() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    // On tablets the rail auto-collapses to icons; the user can still expand it.
    final expanded = isMobile ? true : (_sidebarExpanded ?? context.isDesktop);

    final sidebar = AppSidebar(
      items: _navItems,
      selectedIndex: _navIndex,
      onSelect: (i) {
        setState(() => _navIndex = i);
        if (isMobile) Navigator.of(context).maybePop(); // close drawer
      },
      expanded: expanded,
      // Inside the mobile drawer the rail is always expanded, so the control
      // dismisses the drawer instead of collapsing to a rail nothing can see.
      onToggle: () {
        if (isMobile) {
          Navigator.of(context).maybePop();
        } else {
          setState(() => _sidebarExpanded = !expanded);
        }
      },
      displayName: _displayName,
      onLogout: _logout,
    );

    final selected = _selectedCase;

    return Scaffold(
      backgroundColor: AppColors.surface,
      key: _scaffoldKey,
      // Matches the expanded rail's own width, so the drawer neither clips the
      // labels nor leaves a dead strip beside them.
      drawer:
          isMobile
              ? Drawer(
                width: 244,
                backgroundColor: Colors.transparent,
                child: sidebar,
              )
              : null,
      // The record detail opens over the list rather than replacing it, so the
      // user keeps their place in the grid.
      endDrawer:
          selected == null
              ? null
              : Drawer(
                width: context.screenWidth < 700 ? context.screenWidth : 640,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(),
                child: SafeArea(
                  child: CaseDetailPanel(
                    key: ValueKey(selected.exceptionCode),
                    caseItem: selected,
                    initialTab: _selectedTab,
                    tabs: _detailTabs,
                    currentUser: widget.session.user.name,
                    userId: widget.session.user.employeeCode,
                    role: widget.session.user.role,
                    onChanged: _onCaseChanged,
                    onClose: () => Navigator.of(context).maybePop(),
                    api: _api,
                  ),
                ),
              ),
      onEndDrawerChanged: (open) {
        // Drop the selection when the drawer closes so a stale record is not
        // rebuilt behind the scrim on the next open.
        if (!open && mounted) setState(() => _selectedCase = null);
      },
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile) sidebar,
            Expanded(
              child: Column(
                children: [
                  // The rail carries its own controls, so there is no top bar
                  // on desktop. On mobile the rail is hidden in the drawer and
                  // this strip's button is the only way to reach it.
                  if (isMobile) _mobileMenuBar(),
                  // No shared padding here: a section that wants a full-bleed
                  // header bar has to reach the edges, so each one insets its
                  // own body instead.
                  Expanded(child: _sectionBody(isMobile)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile-only strip holding the drawer opener. Without it the rail — and
  /// therefore every other section — would be unreachable on a phone.
  Widget _mobileMenuBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded),
            iconSize: 22,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              _pageTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What this user's dashboard calls itself. The two sides work the same grid
  /// from opposite ends, and the heading is the only thing on screen that says
  /// which end the reader is at.
  String get _dashboardTitle =>
      AppRole.parse(widget.session.user.role).dashboardTitle;

  /// Page heading for the selected rail item — mostly the nav label, except
  /// where the screen has its own title. Dashboard takes the same heading the
  /// header shows, so the phone's title bar and the desktop heading agree.
  String get _pageTitle => switch (_navItems[_navIndex].label) {
    'MIS' => 'MIS Data',
    'Dashboard' => _dashboardTitle,
    final label => label,
  };

  /// Inset applied to sections that sit on the canvas. Upload Document is
  /// exempt: it paints its own header bar out to the edges.
  static const _sectionPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 10,
  );

  Widget _sectionBody(bool isMobile) => switch (_navItems[_navIndex].label) {
    'MIS' => Padding(
      padding: _sectionPadding,
      child: MisTable(reports: MockData.misReports),
    ),
    'Upload Document' => const UploadCasesView(),
    _ => Padding(padding: _sectionPadding, child: _dashboardBody(isMobile)),
  };

  Widget _dashboardBody(bool isMobile) {
    final rows = _visibleCases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header stays for everyone who reaches this screen — search,
        // refresh and export are how a reader works their own rows. Only the
        // status breakdown is a supervisor's read across the whole queue.
        HealthCheckHeader(
          title: _dashboardTitle,
          counts: _counts,
          recordCount: rows.length,
          searchController: _searchCtrl,
          onSearchChanged: (v) => setState(() => _search = v),
          lastUpdated: _lastUpdated,
          onRefresh: _refresh,
          onExport: _exportExcel,
          showSummary: _rights.canViewSummary,
        ),
        SizedBox(height: isMobile ? 12 : 16),
        if (_loadError != null) ...[
          _loadErrorBanner(_loadError!),
          SizedBox(height: isMobile ? 12 : 16),
        ],
        // Shown alongside the rows rather than instead of them: the queue
        // loading while its reference lists did not is a working dashboard
        // with unusable dropdowns, and the user should see both facts.
        if (_mastersError != null) ...[
          _mastersWarningBanner(_mastersError!),
          SizedBox(height: isMobile ? 12 : 16),
        ],
        // Table fills remaining height; its rows scroll internally while the
        // footer stays fixed. Column filters live in the table's own header.
        Expanded(
          // Only the very first load blanks the grid. A refresh keeps the rows
          // on screen, so the page does not flash empty on every reload.
          child:
              _loading && !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : CasesTable(
                    cases: rows,
                    onOpenCase: _openCase,
                    tabs: _detailTabs,
                    canTick: _rights.canTick,
                  ),
        ),
      ],
    );
  }

  /// The master lists failing. A warning rather than an error: nothing on
  /// screen is wrong, some of it is just missing.
  Widget _mastersWarningBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.warning),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _load,
            child: Text(_loading ? 'Retrying…' : 'Retry'),
          ),
        ],
      ),
    );
  }

  Widget _loadErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _load,
            child: Text(_loading ? 'Retrying…' : 'Retry'),
          ),
        ],
      ),
    );
  }
}
