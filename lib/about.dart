import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ble/controller.dart';
import 'brand.dart';
import 'third_party_licenses.dart';
import 'ui.dart';

abstract final class DeveloperProfiles {
  static final linkedIn = Uri.parse('https://www.linkedin.com/in/anoofc/');
  static final github = Uri.parse('https://github.com/anoofc');
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.controller});
  final CueLinkController controller;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    registerNativeLicenses();
    _packageInfo = PackageInfo.fromPlatform();
  }

  Future<void> _openProfile(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Platform errors and unavailable external apps share the same recovery.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open $uri. Please try again.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: cueAppBar(context, 'About'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: CueSpace.screen,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ControlColumn(
                children: [
                  const SizedBox(height: 12),
                  const Center(child: CueLinkLogo(height: 48)),
                  const SizedBox(height: 12),
                  Text(
                    'CueLink Config',
                    textAlign: TextAlign.center,
                    style: text.headlineLarge,
                  ),
                  Text(
                    'Configure. Connect. Control.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The companion app for configuring your CueLink controller’s buttons, OSC, UDP, USB MIDI, routing, and network settings.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: CueSpace.section),
                  Card(
                    child: Padding(
                      padding: CueSpace.card,
                      child: ControlColumn(
                        children: [
                          const _Detail(
                            label: 'Designed & developed by',
                            value: 'Anoof C.',
                          ),
                          FutureBuilder<PackageInfo>(
                            future: _packageInfo,
                            builder: (context, snapshot) {
                              final info = snapshot.data;
                              final version =
                                  info == null || info.version.isEmpty
                                  ? snapshot.connectionState ==
                                            ConnectionState.done
                                        ? 'Version unavailable'
                                        : 'Reading version…'
                                  : info.buildNumber.isEmpty
                                  ? info.version
                                  : '${info.version} (build ${info.buildNumber})';
                              return _Detail(
                                label: 'App version',
                                value: version,
                              );
                            },
                          ),
                          ListenableBuilder(
                            listenable: widget.controller,
                            builder: (context, _) {
                              final controller = widget.controller;
                              if (controller.session !=
                                  SessionState.connected) {
                                return const SizedBox.shrink();
                              }
                              final name = controller.selected?.name.trim();
                              final firmware = controller.information?.firmware
                                  .trim();
                              if ((name == null || name.isEmpty) &&
                                  (firmware == null || firmware.isEmpty)) {
                                return const SizedBox.shrink();
                              }
                              return _Detail(
                                label: 'Connected device',
                                value: [
                                  if (name != null && name.isNotEmpty) name,
                                  if (firmware != null && firmware.isNotEmpty)
                                    'Firmware $firmware',
                                ].join('\n'),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CueSpace.section),
                  Text(
                    'Technical Support & Feedback',
                    style: text.headlineSmall,
                  ),
                  const Text(
                    'For technical support, bug reports, or suggestions, please send me a message on LinkedIn.',
                  ),
                  FilledButton.icon(
                    onPressed: () => _openProfile(DeveloperProfiles.linkedIn),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text(
                      'Message on LinkedIn',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProfileLink(
                    label: 'LinkedIn',
                    icon: Icons.work_outline,
                    onPressed: () => _openProfile(DeveloperProfiles.linkedIn),
                  ),
                  _ProfileLink(
                    label: 'GitHub',
                    icon: Icons.code,
                    onPressed: () => _openProfile(DeveloperProfiles.github),
                  ),
                  const SizedBox(height: CueSpace.section),
                  const Divider(),
                  const Text(
                    'CueLink Config is a proprietary companion application for customers who purchase CueLink hardware.',
                    style: TextStyle(fontSize: 14),
                  ),
                  TextButton.icon(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'CueLink Config',
                    ),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text(
                      'Third-party Licenses',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Text(
                    '© 2026 Anoof C. All rights reserved.\nFor use with CueLink hardware.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value),
    ],
  );
}

class _ProfileLink extends StatelessWidget {
  const _ProfileLink({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    button: true,
    onTap: onPressed,
    label: '$label developer profile, opens externally',
    excludeSemantics: true,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
