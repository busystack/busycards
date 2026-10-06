import 'dart:async';
import 'dart:convert';

import 'package:busystack_contacts/google.dart';
import 'package:busystack_contacts/microsoft.dart';
import 'package:busystack_contacts/carddav.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:yaru/yaru.dart';
import 'package:uuid/uuid.dart';

import '../../application/cards_runtime.dart';
import '../../app/busycards_design.dart';
import '../../app/busycards_dialogs.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../platform/gtk_header_icon_service.dart';

class CardsSettingsScreen extends StatefulWidget {
  const CardsSettingsScreen({
    super.key,
    required this.runtime,
    required this.themeMode,
    required this.onTheme,
    required this.onBack,
  });
  final CardsRuntime runtime;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;
  final VoidCallback onBack;
  @override
  State<CardsSettingsScreen> createState() => _CardsSettingsScreenState();
}

class _CardsSettingsScreenState extends State<CardsSettingsScreen> {
  List<ContactAccount> _accounts = [];
  List<ContactSource> _sources = [];
  Map<String, (int, ContactSyncState?)> _sourceStates = {};
  int _generation = 0;
  StreamSubscription<void>? _changes;
  String _page = 'accounts';
  String? _error;
  final _working = <String>{};
  @override
  void initState() {
    super.initState();
    _changes = widget.runtime.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final result = await widget.runtime.store.read(
      (tx) => (
        tx.accounts(),
        tx.sources(),
        {
          for (final source in tx.sources())
            source.key: (
              tx.count(sourceKey: source.key),
              tx.syncState(source.key),
            ),
        },
      ),
    );
    if (mounted && generation == _generation)
      setState(() {
        _accounts = result.$1;
        _sources = result.$2;
        _sourceStates = result.$3;
      });
  }

  Future<void> _run(String id, Future<void> Function() work) async {
    if (_working.contains(id)) return;
    setState(() {
      _working.add(id);
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    } finally {
      if (mounted) setState(() => _working.remove(id));
    }
  }

  void _connect(String type, [ContactAccount? reconnect]) => unawaited(
    showBusyCardsModalEditorDialog<void>(
      context,
      maxWidth: 600,
      builder: (_) => ConnectionDialog(
        runtime: widget.runtime,
        type: type,
        reconnect: reconnect,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LinuxPageFrame(
    sidebarAvailable: true,
    sidebarExpanded: MediaQuery.sizeOf(context).width >= 760,
    sidebarHeader: const BusyCardsLinuxBrandHeader(),
    sidebarBody: BusyCardsSidebarNavigation(
      children: [
        for (final page in ['accounts', 'appearance'])
          BusyCardsSidebarNavigationTile(
            selected: _page == page,
            leading: Icon(
              page == 'accounts' ? YaruIcons.user : YaruIcons.settings,
            ),
            title: Text(
              page == 'accounts' ? 'Accounts and sources' : 'Appearance',
            ),
            onTap: () => setState(() => _page = page),
          ),
      ],
    ),
    header: BusyCardsLinuxHeaderLayout(
      leading: BusyCardsLinuxHeaderIconButton(
        icon: BusyCardsLinuxHeaderIcon.back,
        tooltip: 'Back to contacts',
        onPressed: widget.onBack,
      ),
      title: const BusyCardsLinuxHeaderTitle('Settings'),
      trailing: BusyCardsLinuxHeaderMenuButton<String>(
        tooltip: 'Settings menu',
        icon: BusyCardsLinuxHeaderIcon.mainMenu,
        entries: const [
          BusyCardsMenuEntry(value: 'accounts', label: 'Accounts and sources'),
          BusyCardsMenuEntry(value: 'appearance', label: 'Appearance'),
          BusyCardsMenuEntry(
            value: 'registration',
            label: 'BusyCards registrations',
          ),
        ],
        onSelected: (value) {
          if (value == 'registration') {
            unawaited(
              showBusyCardsModalEditorDialog<void>(
                context,
                builder: (_) => RegistrationDialog(runtime: widget.runtime),
              ),
            );
          } else {
            setState(() => _page = value);
          }
        },
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(BusyCardsSpacing.lg),
      child: BusyCardsClamp(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              BusyCardsGroupedList(
                filled: true,
                children: [
                  BusyCardsActionRow(
                    title: 'Connection needs attention',
                    subtitle: _error,
                    leading: const Icon(Icons.error_outline),
                  ),
                ],
              ),
            if (_page == 'appearance')
              BusyCardsGroupedList(
                title: 'Appearance',
                filled: true,
                children: [
                  BusyCardsComboRow<ThemeMode>(
                    title: 'Theme',
                    leading: const Icon(YaruIcons.settings),
                    values: ThemeMode.values,
                    selected: widget.themeMode,
                    labelFor: (value) => switch (value) {
                      ThemeMode.system => 'Follow system',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    },
                    onSelected: widget.onTheme,
                  ),
                  const BusyCardsActionRow(
                    title: 'Fonts, scaling and motion',
                    subtitle: 'BusyCards follows the live GTK font, system text size, contrast and reduced-motion settings.',
                  ),
                ],
              )
            else ...[
              BusyCardsGroupedList(
                title: 'Connect a source',
                description: 'Connections and credentials belong to BusyCards.',
                filled: true,
                children: [
                  for (final item in [
                    ('google', 'Google'),
                    ('microsoft', 'Microsoft'),
                    ('carddav', 'CardDAV'),
                    ('nextcloud', 'Nextcloud'),
                  ])
                    BusyCardsActionRow(
                      title: 'Add ' + item.$2,
                      leading: const Icon(YaruIcons.plus),
                      onTap: () => _connect(item.$1),
                    ),
                  BusyCardsActionRow(
                    title: 'BusyCards registrations',
                    subtitle: 'Configure the app’s own Google Desktop and Microsoft public-client registrations.',
                    leading: const Icon(YaruIcons.settings),
                    onTap: () => unawaited(
                      showBusyCardsModalEditorDialog<void>(
                        context,
                        builder: (_) =>
                            RegistrationDialog(runtime: widget.runtime),
                      ),
                    ),
                  ),
                ],
              ),
              for (final account in _accounts)
                BusyCardsGroupedList(
                  title: account.displayName,
                  filled: true,
                  children: [
                    BusyCardsActionRow(
                      title: account.provider.name,
                      subtitle:
                          (account.enabled ? 'Connected' : 'Disabled') +
                          (account.errorCode == null
                              ? ''
                              : ' · ' + account.errorCode!),
                      leading: const Icon(YaruIcons.user),
                      trailing: _working.contains(account.id)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(),
                            )
                          : null,
                    ),
                    BusyCardsActionRow(
                      title: 'Permissions',
                      subtitle: account.grantedScopes.join(', '),
                    ),
                    BusyCardsSwitchRow(
                      title: 'Enable contacts',
                      value: account.enabled,
                      onChanged: (value) => unawaited(
                        _run(
                          account.id,
                          () => value
                              ? widget.runtime.enable(account.id)
                              : widget.runtime.disable(account.id),
                        ),
                      ),
                    ),
                    BusyCardsActionRow(
                      title: 'Reconnect',
                      enabled: !_working.contains(account.id),
                      onTap: () => _connect(account.provider.name, account),
                    ),
                    BusyCardsActionRow(
                      title: 'Synchronize now',
                      enabled:
                          account.enabled && !_working.contains(account.id),
                      onTap: () => unawaited(
                        _run(
                          account.id,
                          () => widget.runtime.synchronizeAccount(account.id),
                        ),
                      ),
                    ),
                    for (final source in _sources.where(
                      (s) => s.accountId == account.id,
                    ))
                      BusyCardsActionRow(
                        title: source.name,
                        subtitle:
                            source.kind.name +
                            ' · ' +
                            (source.capabilities.update && account.enabled
                                ? 'Editable'
                                : 'Read only') +
                            ' · ' +
                            (_sourceStates[source.key]?.$1 ?? 0).toString() +
                            ' cached contacts' +
                            (_sourceStates[source.key]?.$2?.scanId != null
                                ? ' · Scan in progress'
                                : '') +
                            (_sourceStates[source.key]?.$2?.lastSync == null
                                ? ' · Not yet synchronized'
                                : ' · Last sync ' +
                                      _sourceStates[source.key]!.$2!.lastSync!
                                          .toLocal()
                                          .toString()) +
                            (_sourceStates[source.key]?.$2?.errorCode == null
                                ? ''
                                : ' · ' +
                                      _sourceStates[source.key]!
                                          .$2!
                                          .errorCode!),
                      ),
                    BusyCardsActionRow(
                      title: account.provider == ContactProviderKind.google
                          ? 'Manage contact groups'
                          : account.provider == ContactProviderKind.microsoft
                          ? 'Manage contact folders'
                          : 'Manage address books',
                      enabled: account.enabled,
                      onTap: () => unawaited(
                        showBusyCardsModalEditorDialog<void>(
                          context,
                          builder: (_) => OrganizationDialog(
                            runtime: widget.runtime,
                            account: account,
                            sources: _sources
                                .where((s) => s.accountId == account.id)
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                    BusyCardsActionRow(
                      title: 'Remove connection',
                      destructive: true,
                      onTap: () => unawaited(
                        _run(account.id, () async {
                          if (await showBusyCardsConfirm(
                            context,
                            title: 'Remove ' + account.displayName + '?',
                            message: 'Remove this account’s cached contacts, drafts and BusyCards credentials from this device?',
                            confirmLabel: 'Remove',
                            destructive: true,
                          ))
                            await widget.runtime.remove(account.id);
                        }),
                      ),
                    ),
                  ],
                ),
              if (_accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(BusyCardsSpacing.lg),
                  child: Text(
                    'Add a source to browse contacts here. The ordinary contacts shell is available without an account.',
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    super.key,
    required this.runtime,
    required this.type,
    this.reconnect,
  });
  final CardsRuntime runtime;
  final String type;
  final ContactAccount? reconnect;
  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late final _label = TextEditingController(
    text: widget.reconnect?.displayName ?? widget.type,
  );
  final _server = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController();
  bool _readOnly = false, _working = false;
  String? _error;
  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => BusyCardsContactValueRow(
    label: label,
    entry: TextField(
      controller: controller,
      obscureText: secret,
      enabled: !_working,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Future<void> _connect() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (_label.text.trim().isEmpty)
        throw const ContactsException(
          ContactsFailure.validation,
          'connection-name-required',
        );
      switch (widget.type) {
        case 'google':
          await widget.runtime.connectGoogle(
            label: _label.text,
            readOnly: _readOnly,
            reconnect: widget.reconnect,
          );
        case 'microsoft':
          await widget.runtime.connectMicrosoft(
            label: _label.text,
            readOnly: _readOnly,
            reconnect: widget.reconnect,
          );
        case 'nextcloud':
          await widget.runtime.connectNextcloud(
            label: _label.text,
            server: Uri.parse(_server.text),
            readOnly: _readOnly,
            reconnect: widget.reconnect,
          );
        case 'carddav':
          await widget.runtime.connectCardDav(
            label: _label.text,
            server: Uri.parse(_server.text),
            username: _username.text,
            password: _password.text,
            readOnly: _readOnly,
            reconnect: widget.reconnect,
          );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => BusyCardsModalEditorScaffold(
    title: 'Connect ' + widget.type,
    cancelLabel: 'Cancel',
    saveLabel: _working ? 'Connecting…' : 'Connect',
    saving: _working,
    onSave: _working ? null : () => unawaited(_connect()),
    onCancel: () async {
      await widget.runtime.cancelAuthorization();
      if (context.mounted) Navigator.pop(context);
    },
    children: [
      BusyCardsGroupedList(
        filled: true,
        children: [
          field('Connection name', _label),
          if (widget.type == 'carddav' || widget.type == 'nextcloud')
            field('HTTPS server or DAV service URL', _server),
          if (widget.type == 'carddav') ...[
            field('DAV username', _username),
            field('App password', _password, secret: true),
          ],
          BusyCardsSwitchRow(
            title: 'Lookup only',
            subtitle:
                'Request read access. Reconnect explicitly to enable editing.',
            value: _readOnly,
            onChanged: (value) {
              if (!_working) setState(() => _readOnly = value);
            },
          ),
        ],
      ),
      if (widget.type == 'google' || widget.type == 'microsoft')
        const Padding(
          padding: EdgeInsets.all(BusyCardsSpacing.lg),
          child: Text(
            'BusyCards uses the system browser and its own registration. Additional permission requires a complete authorization request.',
          ),
        ),
      if (widget.type == 'nextcloud')
        const Padding(
          padding: EdgeInsets.all(BusyCardsSpacing.lg),
          child: Text(
            'Complete Nextcloud Login Flow v2 in your browser. BusyCards uses the returned login identity and discovers address books.',
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(BusyCardsSpacing.lg),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: BusyCardsSpacing.lg),
    ],
  );
  @override
  void dispose() {
    if (_working) unawaited(widget.runtime.cancelAuthorization());
    _label.dispose();
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }
}

class RegistrationDialog extends StatefulWidget {
  const RegistrationDialog({super.key, required this.runtime});
  final CardsRuntime runtime;
  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final _google = TextEditingController(),
      _secret = TextEditingController(),
      _microsoft = TextEditingController();
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await widget.runtime.registration();
    if (mounted)
      setState(() {
        _google.text = value.googleClientId;
        _secret.text = value.googleClientSecret;
        _microsoft.text = value.microsoftClientId;
      });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.runtime.saveRegistration(
        CardsRegistration(
          googleClientId: _google.text.trim(),
          googleClientSecret: _secret.text,
          microsoftClientId: _microsoft.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = CardsRuntime.safeError(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) => BusyCardsModalEditorScaffold(
    title: 'BusyCards registrations',
    cancelLabel: 'Cancel',
    saveLabel: 'Save',
    saving: _saving,
    onCancel: () => Navigator.pop(context),
    onSave: _saving ? null : () => unawaited(_save()),
    children: [
      const Padding(
        padding: EdgeInsets.all(BusyCardsSpacing.lg),
        child: Text(
          'Use registrations owned by BusyCards: a Google Desktop OAuth client and a Microsoft public client with delegated Contacts permissions.',
        ),
      ),
      BusyCardsGroupedList(
        title: 'Google Desktop',
        filled: true,
        children: [
          BusyCardsContactValueRow(
            label: 'Google client ID',
            entry: TextField(
              controller: _google,
              decoration: const InputDecoration(labelText: 'Google client ID'),
            ),
          ),
          BusyCardsContactValueRow(
            label: 'Desktop client secret',
            entry: TextField(
              controller: _secret,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Desktop client secret',
              ),
            ),
          ),
          BusyCardsActionRow(
            title: 'Import Desktop registration JSON',
            onTap: () async {
              final file = await openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(label: 'JSON', extensions: ['json']),
                ],
              );
              if (file == null) return;
              try {
                if (await file.length() > 65536) throw const FormatException();
                final installed = jsonDecode(
                  await file.readAsString(),
                )['installed'];
                if (installed is! Map ||
                    installed['client_id'] is! String ||
                    installed['client_secret'] is! String)
                  throw const FormatException();
                if (mounted)
                  setState(() {
                    _google.text = installed['client_id'] as String;
                    _secret.text = installed['client_secret'] as String;
                  });
              } catch (_) {
                if (mounted)
                  setState(
                    () => _error = 'A Google Desktop installed-client JSON file is required.',
                  );
              }
            },
          ),
        ],
      ),
      BusyCardsGroupedList(
        title: 'Microsoft public client',
        filled: true,
        children: [
          BusyCardsContactValueRow(
            label: 'Microsoft client ID',
            entry: TextField(
              controller: _microsoft,
              decoration: const InputDecoration(
                labelText: 'Microsoft client ID',
              ),
            ),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(BusyCardsSpacing.lg),
          child: Text(_error!),
        ),
      const SizedBox(height: BusyCardsSpacing.lg),
    ],
  );
  @override
  void dispose() {
    _google.dispose();
    _secret.dispose();
    _microsoft.dispose();
    super.dispose();
  }
}

class OrganizationDialog extends StatefulWidget {
  const OrganizationDialog({
    super.key,
    required this.runtime,
    required this.account,
    required this.sources,
    this.selected = const [],
  });
  final CardsRuntime runtime;
  final ContactAccount account;
  final List<ContactSource> sources;
  final List<ContactRecord> selected;
  @override
  State<OrganizationDialog> createState() => _OrganizationDialogState();
}

class _OrganizationDialogState extends State<OrganizationDialog> {
  List<ContactGroup> _groups = [];
  String? _error;
  bool _working = false;
  bool get _write =>
      widget.account.grantedScopes.contains(
        'https://www.googleapis.com/auth/contacts',
      ) ||
      widget.account.grantedScopes.any(
        (s) => s.toLowerCase() == 'contacts.readwrite',
      ) ||
      widget.account.grantedScopes.contains('dav:advertised-write');
  @override
  void initState() {
    super.initState();
    if (widget.account.provider == ContactProviderKind.google)
      unawaited(_loadGroups());
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await widget.runtime.googleGroups(widget.account.id);
      if (mounted) setState(() => _groups = groups);
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    }
  }

  Future<void> _action(ContactProviderAction action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await widget.runtime.directory.providerAction(
        widget.account.id,
        action,
      );
      if (result.state != ContactMutationState.confirmed)
        throw ContactsException(
          ContactsFailure.server,
          result.errorCode ?? 'action-needs-review',
        );
      if (widget.account.provider == ContactProviderKind.google)
        await _loadGroups();
      else {
        await widget.runtime.directory.discover(widget.account.id);
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = CardsRuntime.safeError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _name(String title, [String? current]) =>
      showBusyCardsTextPrompt(
        context,
        title: title,
        label: 'Name',
        actionLabel: 'Save',
        initialValue: current,
      );
  @override
  Widget build(BuildContext context) => BusyCardsModalEditorScaffold(
    title: widget.account.provider == ContactProviderKind.google
        ? 'Google contact groups'
        : widget.account.provider == ContactProviderKind.microsoft
        ? 'Microsoft contact folders'
        : 'CardDAV address books',
    cancelLabel: 'Close',
    saveLabel: 'Done',
    onCancel: () => Navigator.pop(context),
    onSave: () => Navigator.pop(context),
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(BusyCardsSpacing.lg),
          child: Text(_error!),
        ),
      if (_working) const LinearProgressIndicator(),
      if (widget.account.provider == ContactProviderKind.google) ...[
        BusyCardsGroupedList(
          filled: true,
          children: [
            BusyCardsActionRow(
              title: 'New user contact group',
              enabled: _write && !_working,
              onTap: () async {
                final name = await _name('New group');
                if (name != null)
                  await _action(
                    GoogleGroupAction(GoogleGroupOperation.create, name: name),
                  );
              },
            ),
            for (final group in _groups)
              Column(
                children: [
                  BusyCardsActionRow(
                    title: group.name ?? group.resourceName!,
                    subtitle: group.groupType,
                    onTap:
                        group.groupType == 'USER_CONTACT_GROUP' &&
                            _write &&
                            !_working
                        ? () async {
                            final name = await _name(
                              'Rename group',
                              group.name,
                            );
                            if (name != null)
                              await _action(
                                GoogleGroupAction(
                                  GoogleGroupOperation.rename,
                                  resourceName: group.resourceName,
                                  name: name,
                                  etag: group.etag,
                                ),
                              );
                          }
                        : null,
                  ),
                  if (widget.selected.isNotEmpty)
                    BusyCardsActionRow(
                      title: 'Add selected contacts',
                      enabled:
                          _write &&
                          !_working &&
                          (group.groupType == 'USER_CONTACT_GROUP' ||
                              const {
                                'contactGroups/myContacts',
                                'contactGroups/starred',
                              }.contains(group.resourceName)),
                      onTap: () => unawaited(
                        _action(
                          GoogleGroupAction(
                            GoogleGroupOperation.membership,
                            resourceName: group.resourceName,
                            add: widget.selected
                                .where(
                                  (r) =>
                                      r.identity.accountId == widget.account.id,
                                )
                                .map((r) => r.identity.remoteId)
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  if (widget.selected.isNotEmpty)
                    BusyCardsActionRow(
                      title: 'Remove selected contacts from group',
                      enabled: _write && !_working,
                      onTap: () => unawaited(
                        _action(
                          GoogleGroupAction(
                            GoogleGroupOperation.membership,
                            resourceName: group.resourceName,
                            remove: widget.selected
                                .where(
                                  (r) =>
                                      r.identity.accountId == widget.account.id,
                                )
                                .map((r) => r.identity.remoteId)
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  if (group.groupType == 'USER_CONTACT_GROUP')
                    BusyCardsActionRow(
                      title: 'Delete group',
                      destructive: true,
                      enabled: _write && !_working,
                      onTap: () async {
                        if (await showBusyCardsConfirm(
                          context,
                          title: 'Delete group?',
                          message: 'The group is removed. Its contacts stay in your account.',
                          confirmLabel: 'Delete group',
                          destructive: true,
                        ))
                          await _action(
                            GoogleGroupAction(
                              GoogleGroupOperation.delete,
                              resourceName: group.resourceName,
                            ),
                          );
                      },
                    ),
                ],
              ),
          ],
        ),
      ] else if (widget.account.provider == ContactProviderKind.microsoft)
        BusyCardsGroupedList(
          filled: true,
          children: [
            BusyCardsActionRow(
              title: 'New contact folder',
              enabled: _write && !_working,
              onTap: () async {
                final name = await _name('New contact folder');
                if (name != null)
                  await _action(
                    MicrosoftFolderAction(
                      MicrosoftFolderOperation.create,
                      name: name,
                    ),
                  );
              },
            ),
            for (final source in widget.sources)
              Column(
                children: [
                  BusyCardsActionRow(
                    title: source.name,
                    enabled: source.canRename && !_working,
                    onTap: () async {
                      final name = await _name(
                        'Rename contact folder',
                        source.name,
                      );
                      if (name != null)
                        await _action(
                          MicrosoftFolderAction(
                            MicrosoftFolderOperation.rename,
                            folderId: source.id,
                            name: name,
                          ),
                        );
                    },
                  ),
                  BusyCardsActionRow(
                    title: 'New child folder',
                    enabled: source.id != 'default' && _write && !_working,
                    onTap: () async {
                      final name = await _name('New child folder');
                      if (name != null)
                        await _action(
                          MicrosoftFolderAction(
                            MicrosoftFolderOperation.create,
                            parentId: source.id,
                            name: name,
                          ),
                        );
                    },
                  ),
                  BusyCardsActionRow(
                    title: 'Delete folder',
                    destructive: true,
                    enabled: source.canRemove && !_working,
                    onTap: () async {
                      if (await showBusyCardsConfirm(
                        context,
                        title: 'Delete folder?',
                        message: 'The provider will remove this folder and its contacts.',
                        confirmLabel: 'Delete folder',
                        destructive: true,
                      ))
                        await _action(
                          MicrosoftFolderAction(
                            MicrosoftFolderOperation.delete,
                            folderId: source.id,
                          ),
                        );
                    },
                  ),
                ],
              ),
          ],
        )
      else
        BusyCardsGroupedList(
          filled: true,
          children: [
            for (final home
                in widget.runtime
                        .cardDavProvider(widget.account.id)
                        ?.creatableHomes ??
                    <Uri>[])
              BusyCardsActionRow(
                title: 'New address book',
                subtitle: home.toString(),
                enabled: !_working,
                onTap: () async {
                  final name = await _name('New address book');
                  if (name != null)
                    await _action(
                      CardDavBookAction(
                        CardDavBookOperation.create,
                        uri: home.resolve(const Uuid().v7() + '/'),
                        name: name,
                      ),
                    );
                },
              ),
            for (final source in widget.sources)
              Column(
                children: [
                  BusyCardsActionRow(
                    title: source.name,
                    enabled: source.canRename && !_working,
                    onTap: () async {
                      final name = await _name(
                        'Rename address book',
                        source.name,
                      );
                      if (name != null)
                        await _action(
                          CardDavBookAction(
                            CardDavBookOperation.rename,
                            uri: Uri.parse(source.remotePath),
                            name: name,
                          ),
                        );
                    },
                  ),
                  BusyCardsActionRow(
                    title: 'Delete address book',
                    destructive: true,
                    enabled: source.canRemove && !_working,
                    onTap: () async {
                      if (await showBusyCardsConfirm(
                        context,
                        title: 'Delete address book?',
                        message: 'The server will remove this address book and its contacts.',
                        confirmLabel: 'Delete address book',
                        destructive: true,
                      ))
                        await _action(
                          CardDavBookAction(
                            CardDavBookOperation.delete,
                            uri: Uri.parse(source.remotePath),
                          ),
                        );
                    },
                  ),
                ],
              ),
            if ((widget.runtime
                        .cardDavProvider(widget.account.id)
                        ?.creatableHomes ??
                    [])
                .isEmpty)
              const BusyCardsActionRow(
                title:
                    'Creating address books is not advertised by this server.',
              ),
          ],
        ),
      const SizedBox(height: BusyCardsSpacing.lg),
    ],
  );
}
