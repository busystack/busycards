import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:busystack_contacts/busystack_contacts.dart';

import '../../application/cards_runtime.dart';
import '../../app/busycards_design.dart';
import '../../app/busycards_dialogs.dart';
import '../../app/busycards_window_close.dart';

class ContactEditor extends StatefulWidget {
  const ContactEditor({
    super.key,
    required this.runtime,
    required this.source,
    required this.draftId,
    this.base,
    this.restored,
  });
  final CardsRuntime runtime;
  final ContactSource source;
  final String draftId;
  final ContactRecord? base;
  final ContactPatch? restored;
  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  final _fields = <String, TextEditingController>{};
  final _emails = <Map<String, TextEditingController>>[],
      _phones = <Map<String, TextEditingController>>[],
      _urls = <Map<String, TextEditingController>>[],
      _addresses = <Map<String, TextEditingController>>[],
      _dates = <Map<String, TextEditingController>>[];
  final _nativeIds = <Map<String, TextEditingController>, String?>{};
  final _types = <Map<String, TextEditingController>, List<String>>{};
  Timer? _draftTimer;
  bool _saving = false;
  bool _completed = false;
  String? _error;
  late final ContactProjection _original;
  TextEditingController _field(String key, String value) {
    final controller = TextEditingController(text: value)
      ..addListener(_changed);
    _fields[key] = controller;
    return controller;
  }

  Map<String, TextEditingController> _row(
    Map<String, String> values, {
    String? nativeId,
    List<String> types = const [],
  }) {
    final row = {
      for (final e in values.entries)
        e.key: TextEditingController(text: e.value)..addListener(_changed),
    };
    _nativeIds[row] = nativeId;
    _types[row] = types;
    return row;
  }

  @override
  void initState() {
    super.initState();
    _original =
        widget.base?.projection ??
        ContactProjection(
          identity: ContactIdentity(
            accountId: widget.source.accountId,
            provider: widget.source.provider,
            sourceId: widget.source.id,
            remoteId: 'draft',
          ),
        );
    final patch = widget.restored;
    final name = patch?.name.changed == true
        ? patch!.name.value ?? const ContactName()
        : _original.name;
    for (final e in name.toJson().entries) {
      _field('name.' + e.key, e.value as String);
    }
    final org = patch?.organization.changed == true
        ? patch!.organization.value ?? const ContactOrganization()
        : _original.organization;
    for (final e in org.toJson().entries) {
      _field('org.' + e.key, e.value as String);
    }
    _field(
      'notes',
      patch?.notes.changed == true ? patch!.notes.value ?? '' : _original.notes,
    );
    _field(
      'labels',
      (patch?.labels.changed == true
              ? patch!.labels.value ?? []
              : _original.labels)
          .join('\n'),
    );
    void values(
      List<Map<String, TextEditingController>> rows,
      List<ContactValue> values,
    ) {
      for (final v in values) {
        rows.add(
          _row(
            {'value': v.value, 'label': v.label},
            nativeId: v.nativeId,
            types: v.types,
          ),
        );
      }
    }

    values(
      _emails,
      patch?.emails.changed == true
          ? patch!.emails.value ?? []
          : _original.emails,
    );
    values(
      _phones,
      patch?.phones.changed == true
          ? patch!.phones.value ?? []
          : _original.phones,
    );
    values(
      _urls,
      patch?.urls.changed == true ? patch!.urls.value ?? [] : _original.urls,
    );
    for (final address
        in patch?.addresses.changed == true
            ? patch!.addresses.value ?? []
            : _original.addresses) {
      _addresses.add(
        _row({
          for (final e in address.toJson().entries.where(
            (e) => e.key != 'nativeId',
          ))
            e.key: e.value as String,
        }, nativeId: address.nativeId),
      );
    }
    for (final date
        in patch?.dates.changed == true
            ? patch!.dates.value ?? []
            : _original.dates) {
      _dates.add(
        _row({
          'year': date.year?.toString() ?? '',
          'month': date.month.toString(),
          'day': date.day.toString(),
          'label': date.label,
        }, nativeId: date.nativeId),
      );
    }
  }

  String _text(String key) => _fields[key]!.text;
  void _changed() {
    if (!mounted || _saving) return;
    setState(() {
      _error = null;
    });
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistDraft()),
    );
  }

  Future<void> _persistDraft() async {
    try {
      await widget.runtime.directory.saveDraft(
        ContactDraft(
          id: widget.draftId,
          sourceKey: widget.source.key,
          identity: widget.base?.identity,
          patch: _patch(),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Complete invalid dates to save the draft.');
    }
  }

  ContactPatch _patch() {
    FieldEdit<T> change<T>(T value, T old, Object? Function(T) encode) {
      if (jsonEncode(encode(value)) == jsonEncode(encode(old)))
        return const FieldEdit.unchanged();
      if (value is String && value.isEmpty || value is List && value.isEmpty)
        return const FieldEdit.clear();
      return FieldEdit.set(value);
    }

    List<ContactValue> values(List<Map<String, TextEditingController>> rows) =>
        rows
            .map(
              (row) => ContactValue(
                row['value']!.text,
                label: row['label']!.text,
                nativeId: _nativeIds[row],
                types: _types[row] ?? [],
              ),
            )
            .toList();
    final name = ContactName(
      display: _text('name.display'),
      given: _text('name.given'),
      middle: _text('name.middle'),
      family: _text('name.family'),
      prefix: _text('name.prefix'),
      suffix: _text('name.suffix'),
    );
    final org = ContactOrganization(
      name: _text('org.name'),
      title: _text('org.title'),
      department: _text('org.department'),
    );
    final addresses = _addresses
        .map(
          (r) => ContactAddress.fromJson({
            for (final e in r.entries) e.key: e.value.text,
            'nativeId': _nativeIds[r],
          }),
        )
        .toList();
    final dates = _dates
        .map(
          (r) => ContactDate(
            month: int.tryParse(r['month']!.text) ?? 0,
            day: int.tryParse(r['day']!.text) ?? 0,
            year: r['year']!.text.isEmpty
                ? null
                : int.tryParse(r['year']!.text) ?? 0,
            label: r['label']!.text,
            nativeId: _nativeIds[r],
          ),
        )
        .toList();
    final fields = widget.source.capabilities.fields.difference(
      _original.readOnlyFields,
    );
    return ContactPatch(
      name: fields.contains(ContactField.name)
          ? change(name, _original.name, (v) => v.toJson())
          : const FieldEdit.unchanged(),
      organization: fields.contains(ContactField.organization)
          ? change(org, _original.organization, (v) => v.toJson())
          : const FieldEdit.unchanged(),
      emails: fields.contains(ContactField.emails)
          ? change(
              values(_emails),
              _original.emails,
              (v) => v.map((e) => e.toJson()).toList(),
            )
          : const FieldEdit.unchanged(),
      phones: fields.contains(ContactField.phones)
          ? change(
              values(_phones),
              _original.phones,
              (v) => v.map((e) => e.toJson()).toList(),
            )
          : const FieldEdit.unchanged(),
      urls: fields.contains(ContactField.urls)
          ? change(
              values(_urls),
              _original.urls,
              (v) => v.map((e) => e.toJson()).toList(),
            )
          : const FieldEdit.unchanged(),
      addresses: fields.contains(ContactField.addresses)
          ? change(
              addresses,
              _original.addresses,
              (v) => v.map((e) => e.toJson()).toList(),
            )
          : const FieldEdit.unchanged(),
      dates: fields.contains(ContactField.dates)
          ? change(
              dates,
              _original.dates,
              (v) => v.map((e) => e.toJson()).toList(),
            )
          : const FieldEdit.unchanged(),
      notes: fields.contains(ContactField.notes)
          ? change(_text('notes'), _original.notes, (v) => v)
          : const FieldEdit.unchanged(),
      labels: fields.contains(ContactField.labels)
          ? change(
              _text('labels').split('\n').where((v) => v.isNotEmpty).toList(),
              _original.labels,
              (v) => v,
            )
          : const FieldEdit.unchanged(),
    );
  }

  bool get _dirty {
    try {
      return _patch().changedFields.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _canClose() async {
    if (_saving) return false;
    if (!_dirty) return true;
    await _persistDraft();
    if (!mounted) return false;
    return showBusyCardsConfirm(
      context,
      title: 'Keep this draft?',
      message: 'Your edits are saved as a draft. Close this editor and restore them later?',
      confirmLabel: 'Keep draft and close',
    );
  }

  Future<void> _cancel() async {
    if (await _canClose() && mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    ContactPatch patch;
    try {
      patch = _patch();
      widget.source.capabilities.validate(patch);
      if (patch.changedFields.isEmpty) {
        Navigator.pop(context);
        return;
      }
    } catch (error) {
      setState(
        () => _error = error is FormatException
            ? 'Enter valid month, day and optional year.'
            : CardsRuntime.safeError(error),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    _draftTimer?.cancel();
    try {
      await widget.runtime.directory.saveDraft(
        ContactDraft(
          id: widget.draftId,
          sourceKey: widget.source.key,
          identity: widget.base?.identity,
          patch: patch,
        ),
      );
      final mutation = widget.base == null
          ? await widget.runtime.directory.create(widget.source.key, patch)
          : await widget.runtime.directory.update(widget.base!, patch);
      // The durable journal owns recovery after dispatch, including uncertainty.
      await widget.runtime.directory.deleteDraft(widget.draftId);
      if (mounted) {
        setState(() {
          _saving = false;
          _completed = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, mutation);
        });
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = CardsRuntime.safeError(error);
        });
    }
  }

  Widget _entry(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    int lines = 1,
  }) => BusyCardsContactValueRow(
    label: label,
    enabled: enabled && !_saving,
    entry: TextField(
      controller: controller,
      enabled: enabled && !_saving,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget _group(String title, List<Widget> rows) =>
      BusyCardsGroupedList(title: title, filled: true, children: rows);
  Widget _values(
    String title,
    List<Map<String, TextEditingController>> rows,
    ContactField field,
  ) {
    return _group(title, [
      for (final row in rows)
        Column(
          children: [
            _entry(
              title == 'Email addresses'
                  ? 'Email'
                  : title == 'Phone numbers'
                  ? 'Phone'
                  : 'URL',
              row['value']!,
            ),
            Row(
              children: [
                Expanded(child: _entry('Label', row['label']!)),
                IconButton(
                  tooltip: 'Remove ' + title.toLowerCase(),
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() => rows.remove(row));
                          _changed();
                        },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ],
        ),
      BusyCardsActionRow(
        title: 'Add ' + title.toLowerCase(),
        leading: const Icon(Icons.add),
        enabled:
            !_saving &&
            rows.length < (widget.source.capabilities.limits[field] ?? 100),
        onTap: () {
          setState(
            () => rows.add(
              _row({
                'value': '',
                'label': widget.source.provider == ContactProviderKind.microsoft
                    ? 'work'
                    : '',
              }),
            ),
          );
          _changed();
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.source.capabilities.fields;
    return BusyCardsWindowCloseGuard(
      onCloseRequested: _canClose,
      child: PopScope(
        canPop: _completed || !_dirty && !_saving,
        onPopInvokedWithResult: (popped, result) {
          if (!popped) unawaited(_cancel());
        },
        child: BusyCardsModalEditorScaffold(
          title: widget.base == null ? 'New contact' : 'Edit contact',
          cancelLabel: 'Close',
          saveLabel: 'Save',
          onCancel: () => unawaited(_cancel()),
          onSave: _saving ? null : () => unawaited(_save()),
          saving: _saving,
          children: [
            Padding(
              padding: const EdgeInsets.all(BusyCardsSpacing.md),
              child: Text('Destination: ' + widget.source.name),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(BusyCardsSpacing.md),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (fields.contains(ContactField.name))
              _group('Name', [
                _entry('Display name', _fields['name.display']!),
                _entry('Given name', _fields['name.given']!),
                _entry('Middle name', _fields['name.middle']!),
                _entry('Family name', _fields['name.family']!),
                _entry('Prefix', _fields['name.prefix']!),
                _entry('Suffix', _fields['name.suffix']!),
              ]),
            if (fields.contains(ContactField.emails))
              _values('Email addresses', _emails, ContactField.emails),
            if (fields.contains(ContactField.phones))
              _values('Phone numbers', _phones, ContactField.phones),
            if (fields.contains(ContactField.organization))
              _group('Organization', [
                _entry('Organization', _fields['org.name']!),
                _entry('Job title', _fields['org.title']!),
                _entry('Department', _fields['org.department']!),
              ]),
            if (fields.contains(ContactField.addresses))
              _group('Postal addresses', [
                for (final row in _addresses)
                  Column(
                    children: [
                      for (final e in row.entries)
                        _entry(
                          e.key,
                          e.value,
                          enabled:
                              widget.source.provider !=
                                  ContactProviderKind.microsoft ||
                              !const {'extended', 'poBox'}.contains(e.key),
                        ),
                      BusyCardsActionRow(
                        title: 'Remove address',
                        onTap: () {
                          setState(() => _addresses.remove(row));
                          _changed();
                        },
                      ),
                    ],
                  ),
                BusyCardsActionRow(
                  title: 'Add address',
                  leading: const Icon(Icons.add),
                  onTap: () {
                    setState(
                      () => _addresses.add(
                        _row({
                          'street': '',
                          'extended': '',
                          'poBox': '',
                          'city': '',
                          'region': '',
                          'postcode': '',
                          'country': '',
                          'label':
                              widget.source.provider ==
                                  ContactProviderKind.microsoft
                              ? 'home'
                              : '',
                        }),
                      ),
                    );
                    _changed();
                  },
                ),
              ]),
            if (fields.contains(ContactField.dates))
              _group('Dates', [
                for (final row in _dates)
                  Column(
                    children: [
                      for (final e in row.entries) _entry(e.key, e.value),
                      BusyCardsActionRow(
                        title: 'Remove date',
                        onTap: () {
                          setState(() => _dates.remove(row));
                          _changed();
                        },
                      ),
                    ],
                  ),
                BusyCardsActionRow(
                  title: 'Add date',
                  leading: const Icon(Icons.add),
                  enabled:
                      _dates.length <
                      (widget.source.capabilities.limits[ContactField.dates] ??
                          100),
                  onTap: () {
                    setState(
                      () => _dates.add(
                        _row({
                          'year': '',
                          'month': '1',
                          'day': '1',
                          'label': 'birthday',
                        }),
                      ),
                    );
                    _changed();
                  },
                ),
              ]),
            if (fields.contains(ContactField.urls))
              _values('URLs', _urls, ContactField.urls),
            if (fields.contains(ContactField.notes))
              _group('Notes', [_entry('Notes', _fields['notes']!, lines: 5)]),
            if (fields.contains(ContactField.labels))
              _group(
                widget.source.provider == ContactProviderKind.microsoft
                    ? 'Categories'
                    : 'Labels',
                [_entry('One label per line', _fields['labels']!, lines: 3)],
              ),
            if (_original.preservedPropertyNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(BusyCardsSpacing.lg),
                child: Text(
                  'Additional source data is preserved: ' +
                      _original.preservedPropertyNames.join(', '),
                ),
              ),
            const SizedBox(height: BusyCardsSpacing.lg),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    for (final controller in {
      ..._fields.values,
      ..._emails.expand((r) => r.values),
      ..._phones.expand((r) => r.values),
      ..._urls.expand((r) => r.values),
      ..._addresses.expand((r) => r.values),
      ..._dates.expand((r) => r.values),
    }) {
      controller.dispose();
    }
    super.dispose();
  }
}
