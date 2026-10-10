import 'dart:async';
import 'dart:convert';

import 'package:busystack_contacts/busystack_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yaru/yaru.dart';

import '../../application/cards_runtime.dart';
import '../../app/busycards_design.dart';
import '../../app/busycards_dialogs.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../platform/gtk_header_icon_service.dart';
import '../settings/settings_screen.dart';
import 'contact_editor.dart';

enum _Menu {
  settings,
  import,
  export,
  delete,
  selection,
  groups,
  pending,
  drafts,
  shortcuts,
}

class _Command extends Intent {
  const _Command(this.command);
  final _Menu command;
}

class _NewContact extends Intent {
  const _NewContact();
}

class _FindContact extends Intent {
  const _FindContact();
}

class ContactsWorkspace extends StatefulWidget {
  const ContactsWorkspace({
    super.key,
    required this.runtime,
    required this.themeMode,
    required this.onTheme,
  });
  final CardsRuntime runtime;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  @override
  State<ContactsWorkspace> createState() => _ContactsWorkspaceState();
}

class _ContactsWorkspaceState extends State<ContactsWorkspace> {
  final _query = TextEditingController();
  final _listScroll = ScrollController();
  double _rowExtent = 0;
  final _pages = <int, List<ContactProjection>>{};
  final _loadingPages = <int>{};
  final _selected = <ContactIdentity>{};
  StreamSubscription<void>? _changes;
  List<ContactAccount> _accounts = [];
  List<ContactSource> _sources = [];
  List<ContactMutation> _pending = [];
  List<ContactDraft> _drafts = [];
  ContactRecord? _detail;
  String? _sourceKey, _error;
  bool _sidebar = true,
      _settings = false,
      _selection = false,
      _loadingDetail = false;
  int _generation = 0,
      _detailGeneration = 0,
      _count = 0,
      _sidebarGeneration = 0,
      _focusRequest = 0,
      _keyboardIndex = -1;
  static const _pageSize = 100;
  final _fileOpen = const MethodChannel(
    'io.busystack.busycards/external_contact_open',
  );
  @override
  void initState() {
    super.initState();
    _changes = widget.runtime.changes.listen((_) => unawaited(_load()));
    _fileOpen.setMethodCallHandler((call) async {
      if (call.method == 'openItem' &&
          call.arguments is Map &&
          (call.arguments as Map)['kind'] == 'vcf') {
        final path = (call.arguments as Map)['value'];
        if (path is String && mounted) await _import(XFile(path));
      }
    });
    unawaited(_fileOpen.invokeMethod<void>('ready').catchError((Object _) {}));
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final snapshot = await widget.runtime.store.read(
        (tx) async => (
          await tx.accounts(),
          await tx.sources(),
          (await tx.mutations())
              .where((m) => m.state != ContactMutationState.confirmed)
              .toList(),
          await tx.drafts(),
        ),
      );
      if (!mounted || generation != _generation) return;
      if (_sourceKey != null && !snapshot.$2.any((s) => s.key == _sourceKey)) {
        _sourceKey = null;
        _detail = null;
        _selected.clear();
      }
      final data = await widget.runtime.store.read(
        (tx) async => (
          await tx.projections(
            sourceKey: _sourceKey,
            query: _query.text,
            limit: _pageSize,
          ),
          await tx.count(sourceKey: _sourceKey, query: _query.text),
        ),
      );
      if (!mounted || generation != _generation) return;
      if (_detail != null) {
        final refreshed = await widget.runtime.store.read<ContactRecord?>(
          (tx) async => tx.contact(_detail!.identity),
        );
        if (!mounted || generation != _generation) return;
        _detail = refreshed;
      }
      setState(() {
        _accounts = snapshot.$1;
        _sources = snapshot.$2;
        _pending = snapshot.$3;
        _drafts = snapshot.$4;
        _count = data.$2;
        _pages.clear();
        _pages[0] = data.$1;
        _loadingPages.clear();
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = CardsRuntime.safeError(error));
    }
  }

  ContactProjection? _at(int index) {
    final page = index ~/ _pageSize, slot = index % _pageSize;
    final records = _pages[page];
    if (records == null) {
      if (_loadingPages.add(page)) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_loadPage(page, _generation)),
        );
      }
      return null;
    }
    return slot < records.length ? records[slot] : null;
  }

  Future<void> _loadPage(int page, int generation) async {
    try {
      final records = await widget.runtime.directory.browse(
        _query.text,
        sourceKey: _sourceKey,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_pages.length >= 10) _pages.remove(_pages.keys.first);
        _pages[page] = records;
        _loadingPages.remove(page);
      });
      if (_keyboardIndex >= page * _pageSize &&
          _keyboardIndex < page * _pageSize + records.length) {
        unawaited(_open(records[_keyboardIndex % _pageSize]));
      }
    } catch (_) {
      _loadingPages.remove(page);
    }
  }

  void _search(String value) {
    // The BusyMax-derived header already owns the search debounce.
    unawaited(_load());
  }

  void _source(String? key) {
    setState(() {
      _sourceKey = key;
      _selected.clear();
      _detail = null;
      _keyboardIndex = -1;
      ++_detailGeneration;
    });
    unawaited(_load());
  }

  Future<void> _open(ContactProjection contact) async {
    final generation = ++_detailGeneration;
    setState(() => _loadingDetail = true);
    try {
      final record = await widget.runtime.store.read<ContactRecord?>(
        (tx) async => tx.contact(contact.identity),
      );
      if (mounted && generation == _detailGeneration)
        setState(() {
          _detail = record;
          _loadingDetail = false;
        });
    } catch (error) {
      if (mounted && generation == _detailGeneration)
        setState(() {
          _loadingDetail = false;
          _error = CardsRuntime.safeError(error);
        });
    }
  }

  ContactSource? _sourceFor(ContactIdentity identity) {
    final source = _sources
        .where(
          (s) =>
              s.accountId == identity.accountId &&
              s.provider == identity.provider &&
              s.id == identity.sourceId,
        )
        .firstOrNull;
    if (source == null ||
        _accounts.any(
          (account) => account.id == identity.accountId && account.enabled,
        ))
      return source;
    return ContactSource.fromJson({
      ...source.toJson(),
      'capabilities': {
        ...source.capabilities.toJson(),
        'create': false,
        'update': false,
        'delete': false,
        'photoWrite': false,
      },
    });
  }

  Future<ContactSource?> _destination() async {
    final writable = _sources
        .where(
          (s) =>
              s.capabilities.create &&
              _accounts.any((a) => a.id == s.accountId && a.enabled),
        )
        .toList();
    if (writable.isEmpty) {
      setState(() {
        _settings = true;
        _error = 'Connect an editable source in Settings.';
      });
      return null;
    }
    return showBusyCardsModalDialog<ContactSource>(
      context,
      builder: (context) => BusyCardsDialogShell(
        title: 'Choose a destination',
        children: [
          BusyCardsGroupedList(
            filled: true,
            children: [
              for (final source in writable)
                BusyCardsActionRow(
                  title: source.name,
                  subtitle:
                      _accounts
                          .firstWhere((a) => a.id == source.accountId)
                          .displayName +
                      ' · ' +
                      source.kind.name,
                  onTap: () => Navigator.pop(context, source),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit({ContactRecord? record, ContactDraft? draft}) async {
    final source = record == null
        ? draft == null
              ? await _destination()
              : _sources.where((s) => s.key == draft.sourceKey).firstOrNull
        : _sourceFor(record.identity);
    if (source == null || !mounted) return;
    if (record != null && !source.capabilities.update) return;
    final result = await showBusyCardsModalEditorDialog<ContactMutation>(
      context,
      builder: (_) => ContactEditor(
        runtime: widget.runtime,
        source: source,
        base: record,
        draftId: draft?.id ?? const Uuid().v7(),
        restored: draft?.patch,
      ),
    );
    if (result != null &&
        mounted &&
        result.state != ContactMutationState.confirmed) {
      setState(
        () => _error =
            result.errorCode ??
            'Saved change needs attention in Pending changes.',
      );
      await _pendingDialog();
    }
  }

  Future<List<ContactRecord>> _chosen() async {
    final identities = _selected.isNotEmpty
        ? _selected.toList()
        : _detail == null
        ? <ContactIdentity>[]
        : [_detail!.identity];
    return widget.runtime.store.read((tx) async {
      final records = <ContactRecord>[];
      for (final identity in identities) {
        final record = await tx.contact(identity);
        if (record != null) records.add(record);
      }
      return records;
    });
  }

  Future<void> _delete() async {
    final records = await _chosen();
    if (records.isEmpty || !mounted) return;
    if (!await showBusyCardsConfirm(
      context,
      title: 'Delete contacts?',
      message:
          'Delete ' +
          records.length.toString() +
          ' selected contacts from their remote sources?',
      confirmLabel: 'Delete',
      destructive: true,
    ))
      return;
    final results = await widget.runtime.deleteMany(records);
    if (mounted) {
      _selected.clear();
      await _results('Delete results', results);
    }
  }

  Future<void> _results(String title, List<CardsItemResult> results) =>
      showBusyCardsModalDialog<void>(
        context,
        builder: (_) => BusyCardsDialogShell(
          title: title,
          children: [
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, index) {
                  final result = results[index];
                  return BusyCardsActionRow(
                    title: result.label,
                    subtitle: result.succeeded
                        ? 'Confirmed'
                        : result.error ??
                              result.mutation?.errorCode ??
                              result.mutation?.state.name ??
                              'Needs review',
                  );
                },
              ),
            ),
          ],
        ),
      );
  Future<void> _import([XFile? supplied]) async {
    try {
      final file =
          supplied ??
          await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'vCard',
                extensions: ['vcf', 'vcard'],
                mimeTypes: ['text/vcard'],
              ),
            ],
          );
      if (file == null || !mounted) return;
      if (await file.length() > 32 * 1024 * 1024)
        throw const ContactsException(
          ContactsFailure.validation,
          'import-file-limit',
        );
      final source = await _destination();
      if (source == null || !mounted) return;
      final items = await widget.runtime.previewImport(
        await file.readAsBytes(),
      );
      final cards = items
          .map((i) => i.card)
          .whereType<VCardDocument>()
          .toList();
      if (!mounted) return;
      final warnings = cards
          .expand((card) => importConversionWarnings(card, source))
          .toSet()
          .toList();
      final allow = await showBusyCardsModalDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (_) => BusyCardsDialogShell(
          title: 'Import preview',
          children: [
            BusyCardsActionRow(
              title: cards.length.toString() + ' contacts',
              subtitle: 'Destination: ' + source.name,
            ),
            SizedBox(
              height: 300,
              child: ListView(
                children: [
                  for (final item in items)
                    BusyCardsActionRow(
                      title: item.card == null
                          ? 'Item ' + (item.index + 1).toString()
                          : item.card!.text('FN') ?? 'Unnamed',
                      subtitle: item.error ?? 'Ready',
                    ),
                  for (final warning in warnings)
                    BusyCardsActionRow(
                      title: 'Conversion needs review',
                      subtitle: warning,
                    ),
                ],
              ),
            ),
          ],
          actions: [
            BusyCardsPushButton.standard(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            BusyCardsPushButton.suggested(
              onPressed: cards.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(
                warnings.isEmpty ? 'Import' : 'Import with listed losses',
              ),
            ),
          ],
        ),
      );
      if (allow == true && mounted)
        await _results(
          'Import results',
          await widget.runtime.importCards(
            cards,
            source,
            allowLoss: warnings.isNotEmpty,
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    }
  }

  Future<void> _export() async {
    try {
      final records = await _chosen();
      if (records.isEmpty || !mounted) return;
      if (records.length > 1 &&
          !await showBusyCardsConfirm(
            context,
            title: 'Export selected contacts?',
            message:
                'Export ' +
                records.length.toString() +
                ' selected contacts to a vCard file?',
            confirmLabel: 'Export',
          ))
        return;
      final destination = await getSaveLocation(
        suggestedName: 'contacts.vcf',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'vCard', extensions: ['vcf']),
        ],
      );
      if (destination == null) return;
      final bytes = await widget.runtime.exportCards(records);
      await XFile.fromData(
        bytes,
        mimeType: 'text/vcard',
        name: 'contacts.vcf',
      ).saveTo(destination.path);
      if (mounted)
        await showBusyCardsModalDialog<void>(
          context,
          builder: (_) => BusyCardsDialogShell(
            title: 'Export completed',
            children: [
              BusyCardsActionRow(
                title: records.length.toString() + ' contacts exported',
                subtitle: records.every((r) => r is CardDavContactRecord)
                    ? 'Complete original vCards were retained.'
                    : 'vCard projection export includes supported common fields. Provider-only data stays in the encrypted source records.',
              ),
            ],
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    }
  }

  Future<void> _pendingDialog() => showBusyCardsModalEditorDialog<void>(
    context,
    builder: (_) => PendingChangesDialog(runtime: widget.runtime),
  );
  Future<void> _draftDialog() async {
    final draft = await showBusyCardsModalDialog<ContactDraft>(
      context,
      builder: (_) => BusyCardsDialogShell(
        title: 'Saved drafts',
        children: [
          SizedBox(
            height: 320,
            child: ListView(
              children: [
                for (final draft in _drafts)
                  BusyCardsActionRow(
                    title: draft.patch.name.value?.display ?? 'Contact draft',
                    subtitle: _sources
                        .where((s) => s.key == draft.sourceKey)
                        .firstOrNull
                        ?.name,
                    onTap: () => Navigator.pop(context, draft),
                  ),
                if (_drafts.isEmpty)
                  const BusyCardsActionRow(title: 'No saved drafts'),
              ],
            ),
          ),
        ],
      ),
    );
    if (draft != null && mounted) {
      final record = draft.identity == null
          ? null
          : await widget.runtime.store.read<ContactRecord?>(
              (tx) async => tx.contact(draft.identity!),
            );
      if (draft.identity != null && record == null) {
        setState(
          () => _error = 'Draft source contact was removed. Export or discard this draft in Pending changes.',
        );
        return;
      }
      await _edit(record: record, draft: draft);
    }
  }

  Future<void> _groups() async {
    final records = await _chosen();
    final accountId =
        records.firstOrNull?.identity.accountId ??
        _sources.where((s) => s.key == _sourceKey).firstOrNull?.accountId;
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null || !mounted) {
      setState(() => _settings = true);
      return;
    }
    await showBusyCardsModalEditorDialog<void>(
      context,
      builder: (_) => OrganizationDialog(
        runtime: widget.runtime,
        account: account,
        sources: _sources.where((s) => s.accountId == account.id).toList(),
        selected: records,
      ),
    );
  }

  void _menu(_Menu command) {
    switch (command) {
      case _Menu.settings:
        setState(() => _settings = true);
      case _Menu.selection:
        setState(() {
          _selection = !_selection;
          if (!_selection) _selected.clear();
        });
      case _Menu.import:
        unawaited(_import());
      case _Menu.export:
        unawaited(_export());
      case _Menu.delete:
        unawaited(_delete());
      case _Menu.pending:
        unawaited(_pendingDialog());
      case _Menu.drafts:
        unawaited(_draftDialog());
      case _Menu.groups:
        unawaited(_groups());
      case _Menu.shortcuts:
        unawaited(
          showBusyCardsModalDialog<void>(
            context,
            builder: (_) => const BusyCardsDialogShell(
              title: 'Keyboard shortcuts',
              children: [
                BusyCardsActionRow(title: 'Ctrl+N · New contact'),
                BusyCardsActionRow(title: 'Ctrl+F · Search'),
                BusyCardsActionRow(title: 'Ctrl+I · Import vCards'),
                BusyCardsActionRow(title: 'Ctrl+E · Export selected'),
                BusyCardsActionRow(title: 'Ctrl+, · Settings'),
                BusyCardsActionRow(
                  title: 'Arrow keys · Navigate the focused list',
                ),
                BusyCardsActionRow(title: 'Space · Select a focused contact'),
                BusyCardsActionRow(title: 'Escape · Leave selection'),
              ],
            ),
          ),
        );
    }
  }

  List<BusyCardsMenuEntry<_Menu>> get _entries => [
    const BusyCardsMenuEntry(
      value: _Menu.settings,
      label: 'Settings',
      shortcut: 'Ctrl+,',
    ),
    const BusyCardsMenuEntry(
      value: _Menu.import,
      label: 'Import vCards…',
      shortcut: 'Ctrl+I',
    ),
    BusyCardsMenuEntry(
      value: _Menu.export,
      label: 'Export selected…',
      enabled: _selected.isNotEmpty || _detail != null,
      shortcut: 'Ctrl+E',
    ),
    BusyCardsMenuEntry(
      value: _Menu.selection,
      label: 'Select contacts',
      selected: _selection,
      role: BusyCardsMenuEntryRole.toggle,
    ),
    BusyCardsMenuEntry(
      value: _Menu.delete,
      label: 'Delete selected…',
      enabled: _selected.isNotEmpty || _detail != null,
      destructive: true,
    ),
    const BusyCardsMenuEntry(value: _Menu.groups, label: 'Organize contacts…'),
    BusyCardsMenuEntry(
      value: _Menu.pending,
      label: 'Pending changes (' + _pending.length.toString() + ')',
    ),
    BusyCardsMenuEntry(
      value: _Menu.drafts,
      label: 'Saved drafts (' + _drafts.length.toString() + ')',
    ),
    const BusyCardsMenuEntry(
      value: _Menu.shortcuts,
      label: 'Keyboard shortcuts',
    ),
  ];
  @override
  Widget build(BuildContext context) {
    if (_settings)
      return CardsSettingsScreen(
        runtime: widget.runtime,
        themeMode: widget.themeMode,
        onTheme: widget.onTheme,
        onBack: () => setState(() => _settings = false),
      );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _NewContact(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindContact(),
        SingleActivator(LogicalKeyboardKey.keyI, control: true): _Command(
          _Menu.import,
        ),
        SingleActivator(LogicalKeyboardKey.keyE, control: true): _Command(
          _Menu.export,
        ),
        SingleActivator(LogicalKeyboardKey.comma, control: true): _Command(
          _Menu.settings,
        ),
      },
      child: Actions(
        actions: {
          _NewContact: CallbackAction<_NewContact>(
            onInvoke: (_) {
              unawaited(_edit());
              return null;
            },
          ),
          _FindContact: CallbackAction<_FindContact>(
            onInvoke: (_) {
              setState(() => _focusRequest++);
              return null;
            },
          ),
          _Command: CallbackAction<_Command>(
            onInvoke: (intent) {
              _menu(intent.command);
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth >= 700;
            return LinuxPageFrame(
              sidebarAvailable: available,
              sidebarExpanded: _sidebar,
              sidebarTransitionGeneration: _sidebarGeneration,
              sidebarHeader: const BusyCardsLinuxBrandHeader(),
              sidebarBody: BusyCardsSidebarNavigation(
                children: [
                  BusyCardsSidebarNavigationTile(
                    selected: _sourceKey == null,
                    leading: const Icon(YaruIcons.user),
                    title: const Text('All contacts'),
                    onTap: () => _source(null),
                  ),
                  for (final account in _accounts) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Text(
                        account.displayName,
                        style: busyCardsSectionHeaderStyle(context),
                      ),
                    ),
                    for (final source in _sources.where(
                      (s) => s.accountId == account.id,
                    ))
                      BusyCardsSidebarNavigationTile(
                        selected: _sourceKey == source.key,
                        leading: Icon(
                          source.capabilities.update
                              ? YaruIcons.user
                              : Icons.lock_outline,
                        ),
                        title: Text(
                          source.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _source(source.key),
                      ),
                  ],
                  BusyCardsSidebarNavigationTile(
                    selected: false,
                    leading: const Icon(YaruIcons.settings),
                    title: const Text('Settings'),
                    onTap: () => setState(() => _settings = true),
                  ),
                ],
              ),
              header: BusyCardsLinuxHeaderLayout(
                leading: BusyCardsLinuxHeaderControlGroup(
                  children: [
                    if (available)
                      BusyCardsLinuxHeaderIconButton(
                        icon: BusyCardsLinuxHeaderIcon.sidebar,
                        tooltip: 'Toggle source sidebar',
                        selected: _sidebar,
                        onPressed: () => setState(() {
                          _sidebar = !_sidebar;
                          _sidebarGeneration++;
                        }),
                      ),
                    BusyCardsLinuxHeaderIconButton(
                      icon: BusyCardsLinuxHeaderIcon.create,
                      tooltip: 'New contact',
                      onPressed:
                          _sources.any(
                            (s) =>
                                s.capabilities.create &&
                                _accounts.any(
                                  (a) => a.id == s.accountId && a.enabled,
                                ),
                          )
                          ? () => unawaited(_edit())
                          : null,
                    ),
                  ],
                ),
                title: BusyCardsLinuxHeaderSearchField(
                  controller: _query,
                  focusRequest: _focusRequest,
                  semanticLabel: 'Search cached contacts',
                  onChanged: _search,
                  autofocus: false,
                  onClear: () {
                    _query.clear();
                    unawaited(_load());
                  },
                ),
                trailing: BusyCardsLinuxHeaderControlGroup(
                  children: [
                    BusyCardsLinuxHeaderIconButton(
                      icon: BusyCardsLinuxHeaderIcon.refresh,
                      tooltip: 'Synchronize contacts',
                      onPressed: () =>
                          unawaited(widget.runtime.synchronizeAll()),
                    ),
                    BusyCardsLinuxHeaderMenuButton<_Menu>(
                      tooltip: 'Main menu',
                      icon: BusyCardsLinuxHeaderIcon.mainMenu,
                      entries: _entries,
                      onSelected: _menu,
                    ),
                  ],
                ),
              ),
              body: Column(
                children: [
                  if (_error != null)
                    BusyCardsActionRow(
                      title: 'Action needs attention',
                      subtitle: _error,
                      leading: const Icon(Icons.error_outline),
                      trailing: IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => setState(() => _error = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  if (_pending.isNotEmpty)
                    BusyCardsActionRow(
                      title: _pending.length.toString() + ' pending changes',
                      subtitle:
                          'Review failures, uncertain writes and conflicts',
                      onTap: () => unawaited(_pendingDialog()),
                    ),
                  if (_selection)
                    BusyCardsActionRow(
                      title: _selected.length.toString() + ' selected',
                      trailing: Wrap(
                        children: [
                          TextButton(
                            onPressed: _selected.isEmpty
                                ? null
                                : () => unawaited(_export()),
                            child: const Text('Export'),
                          ),
                          TextButton(
                            onPressed: _selected.isEmpty
                                ? null
                                : () => unawaited(_delete()),
                            child: const Text('Delete'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _selection = false;
                              _selected.clear();
                            }),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _accounts.isEmpty
                        ? BusyCardsEmptyState(
                            icon: YaruIcons.user,
                            title: 'Your contacts, together',
                            message: 'Connect Google, Microsoft, CardDAV or Nextcloud in Settings. Your synchronized directory is available offline.',
                            actions: [
                              BusyCardsPushButton.suggested(
                                onPressed: () =>
                                    setState(() => _settings = true),
                                child: const Text('Add a source'),
                              ),
                            ],
                          )
                        : _count == 0
                        ? BusyCardsEmptyState(
                            icon: YaruIcons.user,
                            title: _query.text.isEmpty
                                ? 'No contacts in this source'
                                : 'No matching contacts',
                            message: 'Search uses the cached directory. Sync or connect a source in Settings.',
                            actions: [
                              BusyCardsPushButton.standard(
                                onPressed: () =>
                                    setState(() => _settings = true),
                                child: const Text('Settings'),
                              ),
                            ],
                          )
                        : LayoutBuilder(
                            builder: (context, size) {
                              final wide = size.maxWidth >= 760;
                              final list = _list();
                              final details = _loadingDetail
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _detail == null
                                  ? const BusyCardsEmptyState(
                                      icon: YaruIcons.user,
                                      title: 'Select a contact',
                                    )
                                  : ContactDetails(
                                      key: ValueKey(
                                        _detail!.identity.key +
                                            _detail!.revision,
                                      ),
                                      runtime: widget.runtime,
                                      record: _detail!,
                                      source: _sourceFor(_detail!.identity),
                                      onEdit: () =>
                                          unawaited(_edit(record: _detail)),
                                      onDelete: () => unawaited(_delete()),
                                      onBack: () =>
                                          setState(() => _detail = null),
                                    );
                              return wide
                                  ? Row(
                                      children: [
                                        SizedBox(width: 320, child: list),
                                        VerticalDivider(
                                          width: 1,
                                          color: Theme.of(context).dividerColor,
                                        ),
                                        Expanded(child: details),
                                      ],
                                    )
                                  : _detail == null && !_loadingDetail
                                  ? list
                                  : details;
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _count.toString() + ' contacts · cached search',
                          ),
                        ),
                        if (_accounts.any((a) => a.errorCode != null))
                          const Text('Some sources need attention in Settings'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _list() => Focus(
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.escape && _selection) {
        setState(() {
          _selection = false;
          _selected.clear();
        });
        return KeyEventResult.handled;
      }
      if (_count > 0 &&
          (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp)) {
        _keyboardIndex =
            (_keyboardIndex +
                    (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1))
                .clamp(0, _count - 1);
        if (_listScroll.hasClients && _rowExtent > 0) {
          final target = (_keyboardIndex * _rowExtent).clamp(
            0.0,
            _listScroll.position.maxScrollExtent,
          );
          _listScroll.jumpTo(target);
        }
        final record = _at(_keyboardIndex);
        if (record != null) unawaited(_open(record));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Scrollbar(
      controller: _listScroll,
      child: ListView.builder(
        controller: _listScroll,
        prototypeItem: _MeasuredContactRow(
          onExtent: (extent) => _rowExtent = extent,
          child: BusyCardsActionRow(
            titleWidget: _ContactListText(' '),
            subtitleWidget: _ContactListText(' '),
            title: ' ',
            leading: _selection
                ? Checkbox(value: false, onChanged: (_) {})
                : const Icon(YaruIcons.user),
          ),
        ),
        key: ValueKey(_sourceKey ?? 'all'),
        itemCount: _count,
        itemBuilder: (context, index) {
          final projection = _at(index);
          if (projection == null)
            return const SizedBox(
              height: 60,
              child: Center(child: Text('Loading cached contacts…')),
            );
          final selected = _selected.contains(projection.identity);
          return BusyCardsActionRow(
            title: projection.displayName,
            titleWidget: _ContactListText(
              projection.displayName.isEmpty
                  ? 'Unnamed contact'
                  : projection.displayName,
            ),
            subtitleWidget: _ContactListText(
              projection.emails.firstOrNull?.value ??
                  (projection.organization.name.isEmpty
                      ? ' '
                      : projection.organization.name),
            ),
            leading: _selection
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => _toggle(projection.identity),
                  )
                : const Icon(YaruIcons.user),
            hoverColor: _detail?.identity == projection.identity || selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
                : null,
            onTap: () {
              if (_selection)
                _toggle(projection.identity);
              else
                unawaited(_open(projection));
            },
          );
        },
      ),
    ),
  );
  void _toggle(ContactIdentity id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });
  @override
  void dispose() {
    _query.dispose();
    _listScroll.dispose();
    unawaited(_changes?.cancel());
    _fileOpen.setMethodCallHandler(null);
    super.dispose();
  }
}

// The virtual list's prototype and visible rows must use the same line
// metrics. Fallback glyph fonts can otherwise exceed the blank prototype by
// a pixel, even when the GTK font and text scale are unchanged.
class _ContactListText extends StatelessWidget {
  const _ContactListText(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    strutStyle: StrutStyle.fromTextStyle(
      DefaultTextStyle.of(context).style,
      forceStrutHeight: true,
    ),
  );
}

class ContactDetails extends StatefulWidget {
  const ContactDetails({
    super.key,
    required this.runtime,
    required this.record,
    required this.source,
    required this.onEdit,
    required this.onDelete,
    required this.onBack,
  });
  final CardsRuntime runtime;
  final ContactRecord record;
  final ContactSource? source;
  final VoidCallback onEdit, onDelete, onBack;
  @override
  State<ContactDetails> createState() => _ContactDetailsState();
}

class _ContactDetailsState extends State<ContactDetails> {
  int _photoGeneration = 0;
  Uint8List? _photo;
  String? _photoError;
  @override
  void initState() {
    super.initState();
    unawaited(_loadPhoto());
  }

  @override
  void didUpdateWidget(covariant ContactDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.record.revision != oldWidget.record.revision)
      unawaited(_loadPhoto());
  }

  Future<void> _loadPhoto() async {
    final generation = ++_photoGeneration;
    setState(() {
      _photo = null;
      _photoError = null;
    });
    if (widget.record.projection.photo == null &&
        widget.record is! MicrosoftContactRecord)
      return;
    try {
      final bytes = await widget.runtime.directory.loadPhoto(widget.record);
      if (mounted && generation == _photoGeneration)
        setState(() => _photo = bytes);
    } catch (_) {
      if (mounted && generation == _photoGeneration)
        setState(
          () => _photoError = 'Photo unavailable. Contact data remains cached.',
        );
    }
  }

  Future<void> _photoChange({bool remove = false}) async {
    try {
      Uint8List? bytes;
      var type = 'image/jpeg';
      if (!remove) {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Contact photo',
              extensions: ['jpg', 'jpeg', 'png'],
            ),
          ],
        );
        if (file == null) return;
        if (await file.length() > 2 * 1024 * 1024)
          throw const ContactsException(
            ContactsFailure.validation,
            'photo-limit',
          );
        bytes = await file.readAsBytes();
        type = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
      }
      final result = await widget.runtime.directory.setPhoto(
        widget.record,
        bytes,
        type,
      );
      if (mounted && result.state == ContactMutationState.confirmed)
        setState(() {
          _photo = bytes;
          _photoError = null;
        });
      if (mounted && result.state != ContactMutationState.confirmed)
        setState(
          () => _photoError =
              result.errorCode ?? 'Review photo change in Pending changes',
        );
    } catch (error) {
      if (mounted) setState(() => _photoError = CardsRuntime.safeError(error));
    }
  }

  Future<void> _uri(Uri uri) async {
    if (!const {'mailto', 'tel', 'https', 'http'}.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _preservedValue(String name) {
    final record = widget.record;
    final value = switch (record) {
      GoogleContactRecord() => jsonEncode(record.nativeDocument[name]),
      MicrosoftContactRecord() => jsonEncode(record.contact.document[name]),
      CardDavContactRecord() =>
        record.vcard.values(name).map((property) => property.line()).join('\n'),
    };
    return value.length > 4096
        ? value.substring(0, 4096) + '\nFull value is retained in the source; use export to inspect it.'
        : value;
  }

  Widget _value(String title, String value, {Uri? uri}) => BusyCardsActionRow(
    title: title,
    subtitle: value,
    onTap: uri == null ? null : () => unawaited(_uri(uri)),
    trailing: IconButton(
      tooltip: 'Copy ' + title,
      icon: const Icon(Icons.copy, size: 16),
      onPressed: () => Clipboard.setData(ClipboardData(text: value)),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = widget.record.projection;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BusyCardsSpacing.lg),
      child: BusyCardsClamp(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to list',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: SelectableText(
                    p.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                BusyCardsPushButton.standard(
                  onPressed: widget.source?.capabilities.update == true
                      ? widget.onEdit
                      : null,
                  child: const Text('Edit'),
                ),
                IconButton(
                  tooltip: 'Delete contact',
                  onPressed: widget.source?.capabilities.delete == true
                      ? widget.onDelete
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Text(
              (widget.source?.name ?? 'Disconnected source') +
                  ' · ' +
                  widget.record.identity.provider.name,
            ),
            if (p.readOnlyFields.isNotEmpty)
              Text(
                'Provider-owned fields are read only: ' +
                    p.readOnlyFields.map((field) => field.name).join(', '),
              ),
            if (_photo != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(
                  _photo!,
                  height: 128,
                  cacheWidth: 256,
                  errorBuilder: (_, _, _) =>
                      const Text('Photo data could not be displayed'),
                ),
              ),
            if (_photoError != null) Text(_photoError!),
            if (widget.source?.capabilities.photoWrite == true)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => unawaited(_photoChange()),
                    child: const Text('Change photo'),
                  ),
                  if (widget.record.identity.provider !=
                      ContactProviderKind.microsoft)
                    TextButton(
                      onPressed: () => unawaited(_photoChange(remove: true)),
                      child: const Text('Remove photo'),
                    ),
                ],
              ),
            BusyCardsGroupedList(
              title: 'Contact details',
              filled: true,
              children: [
                for (final email in p.emails)
                  _value(
                    email.label.isEmpty ? 'Email' : email.label,
                    email.value,
                    uri: Uri(scheme: 'mailto', path: email.value),
                  ),
                for (final phone in p.phones)
                  _value(
                    phone.label.isEmpty ? 'Phone' : phone.label,
                    phone.value,
                    uri: Uri(scheme: 'tel', path: phone.value),
                  ),
                if (p.organization.name.isNotEmpty)
                  _value('Organization', p.organization.name),
                if (p.organization.title.isNotEmpty)
                  _value('Job title', p.organization.title),
                if (p.organization.department.isNotEmpty)
                  _value('Department', p.organization.department),
                for (final address in p.addresses)
                  _value(
                    address.label.isEmpty ? 'Address' : address.label,
                    [
                      address.poBox,
                      address.extended,
                      address.street,
                      address.city,
                      address.region,
                      address.postcode,
                      address.country,
                    ].where((v) => v.isNotEmpty).join(', '),
                  ),
                for (final date in p.dates)
                  _value(
                    date.label,
                    [
                      if (date.year != null) date.year.toString(),
                      date.month.toString().padLeft(2, '0'),
                      date.day.toString().padLeft(2, '0'),
                    ].join('-'),
                  ),
                for (final url in p.urls)
                  _value(
                    url.label.isEmpty ? 'URL' : url.label,
                    url.value,
                    uri: Uri.tryParse(url.value),
                  ),
                if (p.labels.isNotEmpty)
                  _value(
                    widget.record.identity.provider ==
                            ContactProviderKind.microsoft
                        ? 'Categories'
                        : 'Labels',
                    p.labels.join(', '),
                  ),
              ],
            ),
            if (p.notes.isNotEmpty)
              BusyCardsGroupedList(
                title: 'Notes',
                filled: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(BusyCardsSpacing.lg),
                    child: SelectableText(p.notes),
                  ),
                ],
              ),
            if (p.preservedPropertyNames.isNotEmpty)
              BusyCardsGroupedList(
                title: 'Additional source data',
                description: 'These source properties are retained. This editor does not replace them.',
                filled: true,
                children: [
                  for (final name in p.preservedPropertyNames)
                    BusyCardsActionRow(
                      title: name,
                      subtitleWidget: SelectableText(_preservedValue(name)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class PendingChangesDialog extends StatefulWidget {
  const PendingChangesDialog({super.key, required this.runtime});
  final CardsRuntime runtime;
  @override
  State<PendingChangesDialog> createState() => _PendingChangesDialogState();
}

class _PendingChangesDialogState extends State<PendingChangesDialog> {
  List<ContactMutation> _pending = [];
  List<ContactDraft> _drafts = [];
  StreamSubscription<void>? _changes;
  String? _error;
  @override
  void initState() {
    super.initState();
    _changes = widget.runtime.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final data = await widget.runtime.store.read(
      (tx) async => (
        (await tx.mutations())
            .where((m) => m.state != ContactMutationState.confirmed)
            .toList(),
        await tx.drafts(),
      ),
    );
    if (mounted)
      setState(() {
        _pending = data.$1;
        _drafts = data.$2;
      });
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    }
  }

  Future<void> _review(
    ContactMutation mutation,
  ) => showBusyCardsModalDialog<void>(
    context,
    builder: (_) => BusyCardsDialogShell(
      title: 'Resolve contact conflict',
      children: [
        BusyCardsActionRow(
          title: 'Base',
          subtitleWidget: SelectableText(_summary(mutation.base?.projection)),
        ),
        BusyCardsActionRow(
          title: 'Your selected changes',
          subtitleWidget: SelectableText(
            mutation.patch == null
                ? mutation.kind.name
                : const JsonEncoder.withIndent('  ').convert({
                    for (final field in mutation.patch!.changedFields)
                      field.name: mutation.patch!.toJson()[field.name],
                  }),
          ),
        ),
        BusyCardsActionRow(
          title: 'Remote',
          subtitleWidget: SelectableText(_summary(mutation.remote?.projection)),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Applying your edit replaces only its selected fields on the reviewed remote record.',
          ),
        ),
      ],
      actions: [
        BusyCardsPushButton.standard(
          onPressed:
              mutation.remote == null && mutation.errorCode != 'remote-deleted'
              ? null
              : () async {
                  await widget.runtime.directory.resolveConflict(
                    mutation.id,
                    applyLocalFields: false,
                  );
                  if (mounted) Navigator.pop(context);
                },
          child: const Text('Keep remote'),
        ),
        BusyCardsPushButton.suggested(
          onPressed: mutation.remote == null
              ? null
              : () async {
                  await widget.runtime.directory.resolveConflict(
                    mutation.id,
                    applyLocalFields: true,
                  );
                  if (mounted) Navigator.pop(context);
                },
          child: const Text('Apply selected changes'),
        ),
      ],
    ),
  );
  String _summary(ContactProjection? p) => p == null
      ? 'Resource unavailable'
      : [
          p.displayName,
          ...p.emails.map((e) => e.value),
          ...p.phones.map((e) => e.value),
          p.organization.name,
          p.notes,
        ].where((v) => v.isNotEmpty).join('\n');
  Future<void> _matchCreate(ContactMutation mutation) async {
    var query = '';
    await showBusyCardsModalDialog<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => BusyCardsDialogShell(
          title: 'Match an existing remote contact',
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Synchronize this account first if its new contact is not cached. Select the contact you recognize as the uncertain create. BusyCards verifies that it still exists; it will not create another copy.',
              ),
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search this source',
              ),
              onChanged: (value) => setLocalState(() => query = value),
            ),
            SizedBox(
              height: 320,
              child: FutureBuilder<List<ContactRecord>>(
                future: widget.runtime.directory.search(
                  query,
                  sourceKey: mutation.sourceKey,
                ),
                builder: (context, snapshot) => ListView(
                  children: [
                    for (final record in snapshot.data ?? <ContactRecord>[])
                      BusyCardsActionRow(
                        title: record.projection.displayName,
                        subtitle: record.projection.emails.firstOrNull?.value,
                        onTap: () => unawaited(
                          _run(() async {
                            if (!await showBusyCardsConfirm(
                              context,
                              title: 'Confirm this match?',
                              message: 'Resolve the uncertain create as this existing contact?',
                              confirmLabel: 'Confirm match',
                            ))
                              return;
                            await widget.runtime.directory.acceptUnknownCreate(
                              mutation.id,
                              record,
                            );
                            if (context.mounted) Navigator.pop(context);
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BusyCardsModalEditorScaffold(
    title: 'Pending changes',
    cancelLabel: 'Close',
    saveLabel: 'Done',
    onCancel: () => Navigator.pop(context),
    onSave: () => Navigator.pop(context),
    children: [
      if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      for (final mutation in _pending)
        BusyCardsGroupedList(
          title:
              mutation.base?.projection.displayName ??
              mutation.patch?.name.value?.display ??
              mutation.kind.name,
          filled: true,
          children: [
            BusyCardsActionRow(
              title: mutation.state.name,
              subtitle: mutation.errorCode,
            ),
            if (mutation.state == ContactMutationState.failed ||
                mutation.state == ContactMutationState.queued)
              BusyCardsActionRow(
                title: 'Retry confirmed failure',
                onTap: () => unawaited(
                  _run(() async {
                    await widget.runtime.directory.retry(mutation.id);
                  }),
                ),
              ),
            if (mutation.state == ContactMutationState.unknown)
              BusyCardsActionRow(
                title: 'Reconcile with provider',
                subtitle:
                    'An uncertain create is never sent again automatically.',
                onTap: () => unawaited(
                  _run(() async {
                    await widget.runtime.directory.reconcile(mutation.id);
                  }),
                ),
              ),
            if (mutation.state == ContactMutationState.unknown &&
                mutation.kind == ContactMutationKind.create)
              BusyCardsActionRow(
                title: 'Match an existing contact',
                onTap: () => unawaited(_matchCreate(mutation)),
              ),
            if (mutation.state == ContactMutationState.conflict)
              BusyCardsActionRow(
                title: 'Review base, local and remote',
                onTap: () => unawaited(_review(mutation)),
              ),
            if (mutation.state != ContactMutationState.executing)
              BusyCardsActionRow(
                title: 'Discard pending change',
                destructive: true,
                subtitle: 'Discarding local recovery information does not undo a possible remote write.',
                onTap: () => unawaited(
                  _run(() async {
                    if (await showBusyCardsConfirm(
                      context,
                      title: 'Discard pending change?',
                      message: 'This keeps the remote contact as it is. An uncertain write may already exist on the server.',
                      confirmLabel: 'Discard',
                      destructive: true,
                    ))
                      await widget.runtime.directory.discardFailedChange(
                        mutation.id,
                      );
                  }),
                ),
              ),
          ],
        ),
      for (final draft in _drafts)
        BusyCardsGroupedList(
          title: 'Saved draft',
          filled: true,
          children: [
            BusyCardsActionRow(
              title: draft.patch.name.value?.display ?? 'Contact draft',
            ),
            BusyCardsActionRow(
              title: 'Discard draft',
              destructive: true,
              onTap: () => unawaited(
                _run(() => widget.runtime.directory.deleteDraft(draft.id)),
              ),
            ),
          ],
        ),
      if (_pending.isEmpty && _drafts.isEmpty)
        const BusyCardsEmptyState(
          icon: Icons.check_circle_outline,
          title: 'All changes are confirmed',
        ),
      const SizedBox(height: BusyCardsSpacing.lg),
    ],
  );
  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }
}

// The prototype owns its measurement key. Replacing a source/list must not
// reparent a GlobalKey out of Flutter's special prototype sliver slot.
class _MeasuredContactRow extends StatefulWidget {
  const _MeasuredContactRow({required this.child, required this.onExtent});
  final Widget child;
  final ValueChanged<double> onExtent;
  @override
  State<_MeasuredContactRow> createState() => _MeasuredContactRowState();
}

class _MeasuredContactRowState extends State<_MeasuredContactRow> {
  final _measure = GlobalKey();
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _measure.currentContext?.size?.height;
      if (height != null && height > 0) widget.onExtent(height);
    });
    return SizedBox(key: _measure, child: widget.child);
  }
}
