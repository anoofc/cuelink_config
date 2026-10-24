import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ble/controller.dart';
import 'client.dart';
import 'models.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key, required this.controller});
  final CueLinkController controller;
  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  late final ConfigClient client;
  bool connected = true;
  @override
  void initState() {
    super.initState();
    client = ConfigClient(
      widget.controller.configWire!,
      widget.controller.selected!.id,
    );
    widget.controller.addListener(linkChanged);
  }

  void linkChanged() {
    final next =
        widget.controller.session == SessionState.connected &&
        widget.controller.selected?.id == client.id;
    if (connected && !next) client.disconnected();
    connected = next;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(linkChanged);
    client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: client,
    builder: (context, _) {
      final config = client.configuration;
      return Scaffold(
        appBar: AppBar(title: const Text('Controller settings')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Press B3 on the controller’s App connection page to authorize this session. Enter the OLED passkey only in the iOS pairing dialog.',
              ),
              const SizedBox(height: 16),
              Text(
                connected ? client.state : 'Disconnected / outcome unknown. Reconnect from the overview, then load settings.',
              ),
              if (client.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                TextButton(
                  onPressed: () => unawaited(client.cancel()),
                  child: const Text('Cancel transfer'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: !connected || client.busy
                    ? null
                    : () => unawaited(client.load()),
                child: const Text('Load / query device'),
              ),
              if (config != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Buttons',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                for (var b = 0; b < 4; ++b)
                  Card(
                    child: ListTile(
                      isThreeLine: true,
                      title: Text('B${b + 1} · ${config.buttons[b].label}'),
                      subtitle: Text(
                        '${config.buttons[b].enabled ? 'Enabled' : 'Disabled'} · ${config.buttons[b].slots.length} triggers\n${config.buttons[b].slots.map((s) => '${s.enabled ? '' : 'Off: '}${s.protocol.toUpperCase()}').join(' · ')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: !connected || client.busy || client.uncertain
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ButtonEditor(client: client, index: b),
                              ),
                            ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: !connected || client.busy || client.uncertain
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => RoutingEditor(client: client),
                          ),
                        ),
                  child: const Text('Routing'),
                ),
                OutlinedButton(
                  onPressed: !connected || client.busy || client.uncertain
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => NetworkEditor(
                              client: client,
                              controller: widget.controller,
                            ),
                          ),
                        ),
                  child: const Text('Network'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<bool> discardDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('No changes will be sent to the controller.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ) ??
    false;

class DraftPage extends StatefulWidget {
  const DraftPage({
    super.key,
    required this.title,
    required this.dirty,
    required this.child,
  });
  final String title;
  final bool dirty;
  final Widget child;
  @override
  State<DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<DraftPage> {
  bool leave = false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.dirty || leave,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (await discardDialog(context) && context.mounted) {
        setState(() => leave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget field(
  String label,
  TextEditingController c,
  VoidCallback changed, {
  bool numeric = false,
  int? maxLines = 1,
  int? maxLength,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: TextField(
    controller: c,
    onChanged: (_) => changed(),
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    maxLines: maxLines,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);
Widget failure(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(error, style: const TextStyle(color: Colors.orangeAccent)),
      );
String errorMessage(Object error) => error is FormatException
    ? error.message
    : 'Check the highlighted settings.';

class DestinationDraft {
  DestinationDraft([Destination? d])
    : ip = TextEditingController(text: d?.ip ?? ''),
      port = TextEditingController(text: '${d?.port ?? 7000}');
  final TextEditingController ip, port;
  Destination value() =>
      Destination.parse({'ip': ip.text, 'port': int.tryParse(port.text)});
  void dispose() {
    ip.dispose();
    port.dispose();
  }
}

class DestinationFields extends StatelessWidget {
  const DestinationFields({
    super.key,
    required this.values,
    required this.changed,
  });
  final List<DestinationDraft> values;
  final VoidCallback changed;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      const Text('Destinations · up to 8'),
      for (var i = 0; i < values.length; ++i)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('Destination ${i + 1}'),
                field('IPv4', values[i].ip, changed),
                field('Port', values[i].port, changed, numeric: true),
                TextButton(
                  onPressed: () {
                    values.removeAt(i).dispose();
                    changed();
                  },
                  child: const Text('Remove destination'),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton(
        onPressed: values.length >= 8
            ? null
            : () {
                values.add(DestinationDraft());
                changed();
              },
        child: const Text('Add destination'),
      ),
      if (values.isEmpty)
        const Text(
          'No destination: network triggers cannot submit until configured.',
        ),
    ],
  );
}

class ButtonEditor extends StatefulWidget {
  const ButtonEditor({super.key, required this.client, required this.index});
  final ConfigClient client;
  final int index;
  @override
  State<ButtonEditor> createState() => _ButtonEditorState();
}

class _ButtonEditorState extends State<ButtonEditor> {
  late TextEditingController label;
  late bool enabled;
  late List<Trigger> slots;
  late int revision;
  bool dirty = false;
  String? error;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    final c = widget.client.configuration!;
    final b = c.buttons[widget.index];
    label = TextEditingController(text: b.label);
    enabled = b.enabled;
    slots = [...b.slots];
    revision = c.revision;
    dirty = false;
  }

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  void changed() => setState(() => dirty = true);
  Future<void> edit([int? index]) async {
    final t = await Navigator.push<Trigger>(
      context,
      MaterialPageRoute(
        builder: (_) => TriggerEditor(
          initial: index == null ? null : slots[index],
          routing: widget.client.configuration!.routing,
        ),
      ),
    );
    if (t != null && mounted) {
      setState(() {
        if (index == null) {
          slots.add(t);
        } else {
          slots[index] = t;
        }
        dirty = true;
      });
    }
  }

  Future<void> save() async {
    try {
      final b = ButtonConfig.parse({
        'label': label.text,
        'enabled': enabled,
        'slots': slots.map((s) => s.toJson()).toList(),
      });
      setState(() => error = null);
      if (await widget.client.save(
            'button',
            b.toJson(),
            button: widget.index,
            revision: revision,
          ) &&
          mounted) {
        setState(() {
          dirty = false;
          revision = widget.client.configuration!.revision;
        });
      }
    } catch (e) {
      setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => DraftPage(
    title: 'B${widget.index + 1} · Edit button',
    dirty: dirty,
    child: AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) => IgnorePointer(
        ignoring: widget.client.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dirty ? 'Unsaved changes' : 'Device settings'),
            field(
              'Label · 1–12 printable ASCII characters',
              label,
              changed,
              maxLength: 12,
            ),
            const Text(
              'OLED indicators use the first 3 characters and a dot when the label exceeds 4 characters.',
            ),
            SwitchListTile(
              title: const Text('Button enabled'),
              value: enabled,
              onChanged: (v) {
                enabled = v;
                changed();
              },
            ),
            for (var i = 0; i < slots.length; ++i)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Slot ${i + 1} · ${slots[i].protocol.toUpperCase()}',
                      ),
                      SwitchListTile(
                        title: const Text('Slot enabled'),
                        value: slots[i].enabled,
                        onChanged: (v) {
                          slots[i] = slots[i].withEnabled(v);
                          changed();
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => edit(i),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: i == 0
                                ? null
                                : () {
                                    final t = slots.removeAt(i);
                                    slots.insert(i - 1, t);
                                    changed();
                                  },
                            child: const Text('Move up'),
                          ),
                          TextButton(
                            onPressed: i == slots.length - 1
                                ? null
                                : () {
                                    final t = slots.removeAt(i);
                                    slots.insert(i + 1, t);
                                    changed();
                                  },
                            child: const Text('Move down'),
                          ),
                          TextButton(
                            onPressed: () {
                              slots.removeAt(i);
                              changed();
                            },
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton(
              onPressed: slots.length >= 4 ? null : () => edit(),
              child: const Text('Add trigger'),
            ),
            failure(error),
            Text(widget.client.state),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: !dirty || widget.client.busy || widget.client.uncertain
                  ? null
                  : save,
              child: const Text('Save button'),
            ),
            TextButton(
              onPressed: () async {
                if (!dirty || await discardDialog(context)) {
                  if (mounted) {
                    setState(() {
                      label.dispose();
                      reset();
                      error = null;
                    });
                  }
                }
              },
              child: const Text('Discard / reload device values'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ArgumentDraft {
  ArgumentDraft([OscArgument? a])
    : type = a?.type ?? 'i',
      value = TextEditingController(text: '${a?.value ?? 1}');
  String type;
  final TextEditingController value;
  OscArgument result() => OscArgument.parse({
    'type': type,
    'value': type == 'i'
        ? int.tryParse(value.text)
        : type == 'f'
        ? double.tryParse(value.text)
        : value.text,
  });
}

class TriggerEditor extends StatefulWidget {
  const TriggerEditor({super.key, this.initial, required this.routing});
  final Trigger? initial;
  final Routing routing;
  @override
  State<TriggerEditor> createState() => _TriggerEditorState();
}

class _TriggerEditorState extends State<TriggerEditor> {
  String protocol = 'osc', format = 'text', ending = 'none', type = 'pulse';
  bool enabled = true, dirty = false;
  String? error;
  final path = TextEditingController(text: '/cue'),
      payload = TextEditingController(),
      channel = TextEditingController(text: '1'),
      note = TextEditingController(text: '60'),
      velocity = TextEditingController(text: '100'),
      duration = TextEditingController(text: '100'),
      controller = TextEditingController(text: '1'),
      value = TextEditingController(text: '127'),
      program = TextEditingController(text: '0');
  final List<ArgumentDraft> args = [];
  final List<DestinationDraft> dest = [];
  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t == null) return;
    protocol = t.protocol;
    enabled = t.enabled;
    if (t is OscTrigger) {
      path.text = t.address;
      args.addAll(t.args.map(ArgumentDraft.new));
      dest.addAll(t.destinations.map(DestinationDraft.new));
    }
    if (t is UdpTrigger) {
      format = t.format;
      payload.text = t.payload;
      ending = t.lineEnding;
      dest.addAll(t.destinations.map(DestinationDraft.new));
    }
    if (t is MidiTrigger) {
      type = t.type;
      channel.text = '${t.channel}';
      note.text = '${t.note}';
      velocity.text = '${t.velocity}';
      duration.text = '${t.duration}';
      controller.text = '${t.controller}';
      value.text = '${t.value}';
      program.text = '${t.program}';
    }
  }

  @override
  void dispose() {
    for (final c in [
      path,
      payload,
      channel,
      note,
      velocity,
      duration,
      controller,
      value,
      program,
    ]) {
      c.dispose();
    }
    for (final a in args) {
      a.value.dispose();
    }
    for (final d in dest) {
      d.dispose();
    }
    super.dispose();
  }

  void changed() => setState(() => dirty = true);
  Trigger buildTrigger() => Trigger.parse({
    'enabled': enabled,
    'protocol': protocol,
    if (protocol == 'osc')
      'osc': {
        'address': path.text,
        'args': args.map((a) => a.result().toJson()).toList(),
        'destinations': dest.map((d) => d.value().toJson()).toList(),
      },
    if (protocol == 'udp')
      'udp': {
        'format': format,
        'payload': payload.text,
        'lineEnding': ending,
        'destinations': dest.map((d) => d.value().toJson()).toList(),
      },
    if (protocol == 'midi')
      'midi': {
        'type': type,
        'channel': int.tryParse(channel.text),
        if (['pulse', 'on', 'off'].contains(type)) ...{
          'note': int.tryParse(note.text),
          'velocity': int.tryParse(velocity.text),
        },
        if (type == 'pulse') 'duration': int.tryParse(duration.text),
        if (type == 'cc') ...{
          'controller': int.tryParse(controller.text),
          'value': int.tryParse(value.text),
        },
        if (type == 'program') 'program': int.tryParse(program.text),
      },
  });
  void representation(String next) {
    try {
      final current = UdpTrigger(
        enabled,
        format,
        payload.text,
        ending,
        const [],
      );
      final converted = current.representation(next);
      payload.text = converted.payload;
      format = converted.format;
      ending = 'none';
      error = null;
      changed();
    } catch (e) {
      setState(() => error = errorMessage(e));
    }
  }

  String preview() {
    try {
      if (protocol == 'udp') {
        final t = UdpTrigger(enabled, format, payload.text, ending, const []);
        return '${t.bytes.length} bytes · ${hex(t.bytes)}';
      }
      if (protocol == 'osc') {
        return '${path.text} ${args.map((a) => '${a.type}:${a.value.text}').join(' ')}';
      }
      return 'USB MIDI · $type · channel ${channel.text}';
    } catch (_) {
      return 'Complete valid fields to preview bytes.';
    }
  }

  @override
  Widget build(BuildContext context) => DraftPage(
    title: 'Trigger settings',
    dirty: dirty,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: protocol,
          decoration: const InputDecoration(labelText: 'Protocol'),
          items: [
            for (final p in ['osc', 'udp', 'midi'])
              DropdownMenuItem(
                value: p,
                child: Text(p == 'midi' ? 'USB MIDI' : p.toUpperCase()),
              ),
          ],
          onChanged: (v) {
            protocol = v!;
            changed();
          },
        ),
        SwitchListTile(
          title: const Text('Enabled'),
          value: enabled,
          onChanged: (v) {
            enabled = v;
            changed();
          },
        ),
        if (protocol == 'osc') ...[
          field('OSC address', path, changed),
          const Text('Typed arguments · up to 8'),
          for (var i = 0; i < args.length; ++i)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: args[i].type,
                      items: [
                        for (final t in ['i', 'f', 's'])
                          DropdownMenuItem(
                            value: t,
                            child: Text(
                              {'i': 'int32', 'f': 'float32', 's': 'string'}[t]!,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        args[i].type = v!;
                        changed();
                      },
                    ),
                    field('Argument ${i + 1}', args[i].value, changed),
                    TextButton(
                      onPressed: () {
                        args.removeAt(i).value.dispose();
                        changed();
                      },
                      child: const Text('Remove argument'),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton(
            onPressed: args.length >= 8
                ? null
                : () {
                    args.add(ArgumentDraft());
                    changed();
                  },
            child: const Text('Add argument'),
          ),
        ],
        if (protocol == 'udp') ...[
          DropdownButtonFormField<String>(
            key: ValueKey(format),
            initialValue: format,
            decoration: const InputDecoration(labelText: 'Representation'),
            items: const [
              DropdownMenuItem(
                value: 'text',
                child: Text('Text · supported ASCII'),
              ),
              DropdownMenuItem(value: 'hex', child: Text('Hexadecimal bytes')),
            ],
            onChanged: (v) => representation(v!),
          ),
          field(
            format == 'hex' ? 'Hex byte pairs' : 'Text payload',
            payload,
            changed,
            maxLines: 4,
          ),
          if (format == 'text')
            DropdownButtonFormField<String>(
              key: ValueKey('ending$ending'),
              initialValue: ending,
              decoration: const InputDecoration(
                labelText: 'Append line ending',
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'lf', child: Text('LF')),
                DropdownMenuItem(value: 'crlf', child: Text('CRLF')),
              ],
              onChanged: (v) {
                ending = v!;
                changed();
              },
            ),
        ],
        if (protocol == 'midi') ...[
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'MIDI message'),
            items: [
              for (final p in ['pulse', 'on', 'off', 'cc', 'program'])
                DropdownMenuItem(
                  value: p,
                  child: Text(
                    {
                      'pulse': 'Note pulse',
                      'on': 'Note On',
                      'off': 'Note Off',
                      'cc': 'Control Change',
                      'program': 'Program Change',
                    }[p]!,
                  ),
                ),
            ],
            onChanged: (v) {
              type = v!;
              changed();
            },
          ),
          field('Channel · 1–16', channel, changed, numeric: true),
          if (['pulse', 'on', 'off'].contains(type)) ...[
            field('Note · 0–127', note, changed, numeric: true),
            field(
              'Velocity · ${type == 'pulse' ? '1' : '0'}–127',
              velocity,
              changed,
              numeric: true,
            ),
          ],
          if (type == 'pulse')
            field('Duration · 1–60000 ms', duration, changed, numeric: true),
          if (type == 'cc') ...[
            field('Controller · 0–127', controller, changed, numeric: true),
            field('Value · 0–127', value, changed, numeric: true),
          ],
          if (type == 'program')
            field(
              'Program · 0–127 (zero-based)',
              program,
              changed,
              numeric: true,
            ),
          const Text('USB MIDI ignores network/master routing.'),
        ] else ...[
          Text(
            widget.routing.master
                ? 'Effective routing: master list (${widget.routing.destinations.map((d) => '${d.ip}:${d.port}').join(', ')}). Individual destinations below are retained.'
                : 'Effective routing: individual destinations below.',
          ),
          DestinationFields(values: dest, changed: changed),
        ],
        const SizedBox(height: 16),
        SelectableText(preview()),
        failure(error),
        FilledButton(
          onPressed: () {
            try {
              final t = buildTrigger();
              dirty = false;
              Navigator.pop(context, t);
            } catch (e) {
              setState(() => error = errorMessage(e));
            }
          },
          child: const Text('Use trigger in draft'),
        ),
        TextButton(
          onPressed: () async {
            if (!dirty || await discardDialog(context)) {
              if (context.mounted) {
                setState(() => dirty = false);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) Navigator.pop(context);
                });
              }
            }
          },
          child: const Text('Discard trigger changes'),
        ),
      ],
    ),
  );
}

class RoutingEditor extends StatefulWidget {
  const RoutingEditor({super.key, required this.client});
  final ConfigClient client;
  @override
  State<RoutingEditor> createState() => _RoutingEditorState();
}

class _RoutingEditorState extends State<RoutingEditor> {
  late bool master;
  late int revision;
  bool dirty = false;
  String? error;
  final List<DestinationDraft> dest = [];
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    final c = widget.client.configuration!;
    master = c.routing.master;
    revision = c.revision;
    dest.addAll(c.routing.destinations.map(DestinationDraft.new));
    dirty = false;
  }

  void changed() => setState(() => dirty = true);
  @override
  void dispose() {
    for (final d in dest) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraftPage(
    title: 'Routing',
    dirty: dirty,
    child: AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) => IgnorePointer(
        ignoring: widget.client.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: const Text('Master network destinations'),
              value: master,
              onChanged: (v) {
                master = v;
                changed();
              },
            ),
            const Text(
              'ON replaces effective routing for every OSC/UDP slot. Individual lists stay intact. USB MIDI is unaffected.',
            ),
            DestinationFields(values: dest, changed: changed),
            failure(error),
            Text(widget.client.state),
            FilledButton(
              onPressed: !dirty || widget.client.busy || widget.client.uncertain
                  ? null
                  : () async {
                      try {
                        final r = Routing(
                          master,
                          dest.map((d) => d.value()).toList(),
                        );
                        if (await widget.client.save(
                              'routing',
                              r.toJson(),
                              revision: revision,
                            ) &&
                            mounted) {
                          setState(() {
                            dirty = false;
                            revision = widget.client.configuration!.revision;
                          });
                        }
                      } catch (e) {
                        setState(() => error = errorMessage(e));
                      }
                    },
              child: const Text('Save routing'),
            ),
            TextButton(
              onPressed: () async {
                if (!dirty || await discardDialog(context)) {
                  if (mounted) {
                    setState(() {
                      for (final d in dest) {
                        d.dispose();
                      }
                      dest.clear();
                      reset();
                    });
                  }
                }
              },
              child: const Text('Discard / reload device values'),
            ),
          ],
        ),
      ),
    ),
  );
}

class NetworkEditor extends StatefulWidget {
  const NetworkEditor({
    super.key,
    required this.client,
    required this.controller,
  });
  final ConfigClient client;
  final CueLinkController controller;
  @override
  State<NetworkEditor> createState() => _NetworkEditorState();
}

class _NetworkEditorState extends State<NetworkEditor> {
  final ssid = TextEditingController(), password = TextEditingController();
  final fields = <String, TextEditingController>{
    for (final k in ['ip', 'subnet', 'gateway', 'dns1', 'dns2'])
      k: TextEditingController(),
  };
  bool dhcp = true, reveal = false, dirty = false;
  String mode = 'keep';
  String? error;
  late int revision;
  List<Json> networks = [];
  @override
  void initState() {
    super.initState();
    reset();
    widget.controller.addListener(linkChanged);
  }

  void reset() {
    final c = widget.client.configuration!;
    final n = c.network;
    ssid.text = n.ssid;
    dhcp = n.dhcp;
    revision = c.revision;
    for (final k in fields.keys) {
      fields[k]!.text = n.toJson()[k];
    }
    password.clear();
    mode = 'keep';
    dirty = false;
  }

  void linkChanged() {
    if (widget.controller.session != SessionState.connected) {
      password.clear();
      mode = 'keep';
      reveal = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(linkChanged);
    ssid.dispose();
    password.clear();
    password.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() => setState(() => dirty = true);
  Future<void> apply() async {
    try {
      final n = NetworkConfig.parse({
        'ssid': ssid.text,
        'passwordConfigured':
            widget.client.configuration!.network.passwordConfigured,
        'dhcp': dhcp,
        for (final k in fields.keys) k: fields[k]!.text,
      });
      if (n.ssid.isEmpty) invalid('Enter an SSID.');
      if (mode == 'replace' &&
          (utf8.encode(password.text).length < 8 ||
              utf8.encode(password.text).length > 63 ||
              password.text.contains('\u0000'))) {
        invalid('Password must contain 8–63 UTF-8 bytes, without NUL.');
      }
      final credential = <String, dynamic>{
        'mode': mode,
        if (mode == 'replace') 'value': password.text,
      };
      final saved = await widget.client.save(
        'network',
        n.toJson(),
        credential: credential,
        revision: revision,
      );
      credential.clear();
      password.clear();
      if (mounted) {
        setState(() {
          mode = 'keep';
          reveal = false;
          if (saved) {
            dirty = false;
            revision = widget.client.configuration!.revision;
          }
        });
      }
    } catch (e) {
      setState(() => error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => DraftPage(
    title: 'Network',
    dirty: dirty,
    child: AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) => IgnorePointer(
        ignoring: widget.client.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.controller.fresh ? 'Current Wi-Fi' : 'Last Wi-Fi (stale)'}: ${widget.controller.status?.wifi.label ?? 'Unavailable'} · ${widget.controller.status?.ipv4 ?? 'No current IP'}',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: widget.client.busy || widget.client.uncertain
                  ? null
                  : () async {
                      final result = await widget.client.scan();
                      if (result != null && mounted) {
                        setState(() => networks = result);
                      }
                    },
              child: const Text('Scan Wi-Fi using controller'),
            ),
            for (final n in networks)
              ListTile(
                title: Text(n['ssid'] == '' ? 'Hidden network' : n['ssid']),
                subtitle: Text(
                  '${n['rssi']} dBm · ${n['open'] == true ? 'Open' : 'Secured'}',
                ),
                onTap: () {
                  ssid.text = n['ssid'];
                  changed();
                },
              ),
            field(
              'SSID · manual / hidden network',
              ssid,
              changed,
              maxLength: 32,
            ),
            Text(
              'Stored password: ${widget.client.configuration!.network.passwordConfigured ? 'Configured' : 'Not configured'}',
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(mode),
              initialValue: mode,
              decoration: const InputDecoration(
                labelText: 'Credential operation',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'keep',
                  child: Text('Keep existing password'),
                ),
                DropdownMenuItem(
                  value: 'replace',
                  child: Text('Replace password'),
                ),
                DropdownMenuItem(
                  value: 'open',
                  child: Text('Configure open network'),
                ),
              ],
              onChanged: (v) {
                mode = v!;
                password.clear();
                changed();
              },
            ),
            if (mode == 'replace')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  controller: password,
                  obscureText: !reveal,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => changed(),
                  decoration: InputDecoration(
                    labelText: 'New password · never trimmed',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => reveal = !reveal),
                      icon: Icon(
                        reveal ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
              ),
            SwitchListTile(
              title: const Text('DHCP'),
              value: dhcp,
              onChanged: (v) {
                dhcp = v;
                changed();
              },
            ),
            if (!dhcp)
              for (final k in fields.keys)
                field(
                  {
                    'ip': 'Static IPv4',
                    'subnet': 'Subnet mask',
                    'gateway': 'Gateway',
                    'dns1': 'Primary DNS',
                    'dns2': 'Secondary DNS',
                  }[k]!,
                  fields[k]!,
                  changed,
                ),
            const Text(
              'Apply tests association and IP acquisition for up to 30 seconds. Failed settings roll back. BLE and USB MIDI remain available. Internet access is not required.',
            ),
            failure(error),
            Text(widget.client.state),
            FilledButton(
              onPressed: !dirty || widget.client.busy || widget.client.uncertain
                  ? null
                  : apply,
              child: const Text('Apply network'),
            ),
            TextButton(
              onPressed: () async {
                if (!dirty || await discardDialog(context)) {
                  if (mounted) setState(reset);
                }
              },
              child: const Text('Discard / reload device values'),
            ),
          ],
        ),
      ),
    ),
  );
}
