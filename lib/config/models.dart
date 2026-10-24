import 'dart:convert';
import 'dart:typed_data';

const configSchema = 1;
const maxConfigBytes = 16384;
const maxConfigurationBytes = 12288;
typedef Json = Map<String, dynamic>;
Never invalid(String message) => throw FormatException(message);
Json object(dynamic v, Set<String> keys) {
  if (v is! Map<String, dynamic> || v.keys.any((k) => !keys.contains(k))) {
    invalid('Invalid or unsupported fields.');
  }
  return v;
}

String ascii(dynamic v, int min, int max, {bool lines = false}) {
  if (v is! String ||
      v.length < min ||
      v.length > max ||
      v.codeUnits.any(
        (c) => (c < 32 || c > 126) && !(lines && [9, 10, 13].contains(c)),
      )) {
    invalid('Use $min–$max supported ASCII characters.');
  }
  return v;
}

int number(dynamic v, int min, int max) {
  if (v is! int || v < min || v > max) invalid('Enter an integer $min–$max.');
  return v;
}

bool boolean(dynamic v) {
  if (v is! bool) invalid('Expected an enabled/disabled value.');
  return v;
}

List<dynamic> array(dynamic v, int max) {
  if (v is! List || v.length > max) invalid('Maximum $max entries.');
  return v;
}

int address(dynamic value, {bool zero = false}) {
  if (value is! String || !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value)) {
    invalid('Enter a numeric IPv4 address.');
  }
  final p = value.split('.').map(int.parse).toList();
  if (p.any((n) => n > 255)) invalid('Invalid IPv4 address.');
  final n = p.fold(0, (a, b) => (a << 8) | b);
  if (!(zero && n == 0) && (p[0] == 0 || p[0] == 127 || p[0] >= 224)) {
    invalid('Use a unicast IPv4 address.');
  }
  return n;
}

class Destination {
  Destination(this.ip, this.port);
  final String ip;
  final int port;
  factory Destination.parse(dynamic value) {
    final j = object(value, {'ip', 'port'});
    address(j['ip']);
    return Destination(j['ip'], number(j['port'], 1, 65535));
  }
  Json toJson() => {'ip': ip, 'port': port};
}

List<Destination> destinations(dynamic v) =>
    array(v, 8).map(Destination.parse).toList();

class OscArgument {
  OscArgument(this.type, this.value);
  final String type;
  final Object value;
  factory OscArgument.parse(dynamic v) {
    final j = object(v, {'type', 'value'});
    final type = j['type'];
    final x = j['value'];
    switch (type) {
      case 'i':
        number(x, -2147483648, 2147483647);
      case 'f':
        if (x is! num || !x.isFinite || x.abs() > 3.4028234663852886e38) {
          invalid('Invalid float32.');
        }
      case 's':
        ascii(x, 0, 256, lines: true);
      default:
        invalid('Unsupported OSC argument.');
    }
    return OscArgument(
      type,
      type == 'f'
          ? Float32List.fromList([(x as num).toDouble()])[0]
          : x as Object,
    );
  }
  Json toJson() => {'type': type, 'value': value};
}

sealed class Trigger {
  Trigger(this.enabled);
  final bool enabled;
  String get protocol;
  Json toJson();
  Trigger withEnabled(bool enabled) {
    final j = toJson();
    j['enabled'] = enabled;
    return Trigger.parse(j);
  }

  factory Trigger.parse(dynamic v) {
    final j = object(v, {'enabled', 'protocol', 'osc', 'udp', 'midi'});
    boolean(j['enabled']);
    final protocol = j['protocol'];
    if (!['osc', 'udp', 'midi'].contains(protocol) ||
        j.keys.where((k) => ['osc', 'udp', 'midi'].contains(k)).length != 1 ||
        !j.containsKey(protocol)) {
      invalid('Select one typed protocol.');
    }
    return switch (protocol) {
      'osc' => OscTrigger.parse(j),
      'udp' => UdpTrigger.parse(j),
      _ => MidiTrigger.parse(j),
    };
  }
}

class OscTrigger extends Trigger {
  OscTrigger(super.enabled, this.address, this.args, this.destinations);
  final String address;
  final List<OscArgument> args;
  final List<Destination> destinations;
  @override
  String get protocol => 'osc';
  factory OscTrigger.parse(Json root) {
    final j = object(root['osc'], {'address', 'args', 'destinations'});
    final path = ascii(j['address'], 2, 128);
    if (!path.startsWith('/') || path.codeUnits.any((n) => n <= 32)) {
      invalid('OSC address must start with / and contain no whitespace.');
    }
    final args = array(j['args'], 8).map(OscArgument.parse).toList();
    int padded(int n) => (n + 3) & ~3;
    final length =
        padded(path.length + 1) +
        padded(args.length + 2) +
        args.fold<int>(
          0,
          (n, a) =>
              n + (a.type == 's' ? padded((a.value as String).length + 1) : 4),
        );
    if (length > 1024) invalid('OSC message exceeds 1024 bytes.');
    return OscTrigger(
      root['enabled'],
      path,
      args,
      configDestinations(j['destinations']),
    );
  }
  @override
  Json toJson() => {
    'enabled': enabled,
    'protocol': protocol,
    'osc': {
      'address': address,
      'args': args.map((a) => a.toJson()).toList(),
      'destinations': destinations.map((d) => d.toJson()).toList(),
    },
  };
}

List<Destination> configDestinations(dynamic v) => destinations(v);

class UdpTrigger extends Trigger {
  UdpTrigger(
    super.enabled,
    this.format,
    this.payload,
    this.lineEnding,
    this.destinations,
  );
  final String format, payload, lineEnding;
  final List<Destination> destinations;
  @override
  String get protocol => 'udp';
  List<int> get bytes {
    if (format == 'hex') {
      return [
        for (int i = 0; i < payload.length; i += 2)
          int.parse(payload.substring(i, i + 2), radix: 16),
      ];
    }
    return [
      ...payload.codeUnits,
      if (lineEnding == 'crlf') 13,
      if (lineEnding != 'none') 10,
    ];
  }

  factory UdpTrigger.parse(Json root) {
    final j = object(root['udp'], {
      'format',
      'payload',
      'lineEnding',
      'destinations',
    });
    final payload = ascii(j['payload'], 0, 2048, lines: true),
        format = j['format'],
        ending = j['lineEnding'];
    if (format == 'hex') {
      if (ending != 'none' ||
          !RegExp(r'^(?:[0-9a-fA-F]{2})*$').hasMatch(payload)) {
        invalid('Hex requires complete byte pairs and no line ending.');
      }
    } else if (format != 'text' || !['none', 'lf', 'crlf'].contains(ending)) {
      invalid('Unsupported UDP representation/line ending.');
    }
    final t = UdpTrigger(
      root['enabled'],
      format,
      payload,
      ending,
      configDestinations(j['destinations']),
    );
    if (t.bytes.isEmpty || t.bytes.length > 1024) {
      invalid('UDP requires 1–1024 bytes.');
    }
    return t;
  }
  UdpTrigger representation(String next) {
    final data = bytes;
    final value = next == 'hex' ? hex(data) : asciiDecode(data);
    return UdpTrigger(enabled, next, value, 'none', destinations);
  }

  @override
  Json toJson() => {
    'enabled': enabled,
    'protocol': protocol,
    'udp': {
      'format': format,
      'payload': payload,
      'lineEnding': lineEnding,
      'destinations': destinations.map((d) => d.toJson()).toList(),
    },
  };
}

String hex(List<int> bytes) =>
    bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
String asciiDecode(List<int> bytes) {
  if (bytes.any((n) => (n < 32 || n > 126) && ![9, 10, 13].contains(n))) {
    invalid('These bytes cannot be represented as supported text; keep hex.');
  }
  return String.fromCharCodes(bytes);
}

class MidiTrigger extends Trigger {
  MidiTrigger(
    super.enabled,
    this.type,
    this.channel, {
    this.note = 60,
    this.velocity = 100,
    this.duration = 100,
    this.controller = 1,
    this.value = 127,
    this.program = 0,
  });
  final String type;
  final int channel, note, velocity, duration, controller, value, program;
  @override
  String get protocol => 'midi';
  factory MidiTrigger.parse(Json root) {
    final j = root['midi'];
    if (j is! Json) invalid('Missing MIDI settings.');
    final type = j['type'];
    final ch = number(j['channel'], 1, 16);
    switch (type) {
      case 'pulse':
        object(j, {'type', 'channel', 'note', 'velocity', 'duration'});
        return MidiTrigger(
          root['enabled'],
          type,
          ch,
          note: number(j['note'], 0, 127),
          velocity: number(j['velocity'], 1, 127),
          duration: number(j['duration'], 1, 60000),
        );
      case 'on':
      case 'off':
        object(j, {'type', 'channel', 'note', 'velocity'});
        return MidiTrigger(
          root['enabled'],
          type,
          ch,
          note: number(j['note'], 0, 127),
          velocity: number(j['velocity'], 0, 127),
        );
      case 'cc':
        object(j, {'type', 'channel', 'controller', 'value'});
        return MidiTrigger(
          root['enabled'],
          type,
          ch,
          controller: number(j['controller'], 0, 127),
          value: number(j['value'], 0, 127),
        );
      case 'program':
        object(j, {'type', 'channel', 'program'});
        return MidiTrigger(
          root['enabled'],
          type,
          ch,
          program: number(j['program'], 0, 127),
        );
      default:
        invalid('Unsupported MIDI message.');
    }
  }
  @override
  Json toJson() => {
    'enabled': enabled,
    'protocol': protocol,
    'midi': {
      'type': type,
      'channel': channel,
      if (type == 'program') 'program': program,
      if (type == 'cc') ...{'controller': controller, 'value': value},
      if (['pulse', 'on', 'off'].contains(type)) ...{
        'note': note,
        'velocity': velocity,
      },
      if (type == 'pulse') 'duration': duration,
    },
  };
}

class ButtonConfig {
  ButtonConfig(this.label, this.enabled, this.slots);
  final String label;
  final bool enabled;
  final List<Trigger> slots;
  factory ButtonConfig.parse(dynamic v) {
    final j = object(v, {'label', 'enabled', 'slots'});
    return ButtonConfig(
      ascii(j['label'], 1, 12),
      boolean(j['enabled']),
      array(j['slots'], 4).map(Trigger.parse).toList(),
    );
  }
  Json toJson() => {
    'label': label,
    'enabled': enabled,
    'slots': slots.map((s) => s.toJson()).toList(),
  };
}

class Routing {
  Routing(this.master, this.destinations);
  final bool master;
  final List<Destination> destinations;
  factory Routing.parse(dynamic v) {
    final j = object(v, {'master', 'destinations'});
    return Routing(boolean(j['master']), configDestinations(j['destinations']));
  }
  Json toJson() => {
    'master': master,
    'destinations': destinations.map((d) => d.toJson()).toList(),
  };
}

class NetworkConfig {
  NetworkConfig(
    this.ssid,
    this.passwordConfigured,
    this.dhcp,
    this.ip,
    this.subnet,
    this.gateway,
    this.dns1,
    this.dns2,
  );
  final String ssid, ip, subnet, gateway, dns1, dns2;
  final bool passwordConfigured, dhcp;
  factory NetworkConfig.parse(dynamic v) {
    final j = object(v, {
      'ssid',
      'passwordConfigured',
      'dhcp',
      'ip',
      'subnet',
      'gateway',
      'dns1',
      'dns2',
    });
    final ssid = j['ssid'], dhcp = boolean(j['dhcp']);
    if (ssid is! String ||
        utf8.encode(ssid).length > 32 ||
        utf8.decode(utf8.encode(ssid)) != ssid ||
        ssid.runes.any((cp) => cp < 32 || (cp >= 127 && cp <= 159))) {
      invalid(
        'SSID requires up to 32 UTF-8 bytes, without control characters.',
      );
    }
    final ip = address(j['ip'], zero: true),
        gw = address(j['gateway'], zero: true);
    address(j['dns1'], zero: true);
    address(j['dns2'], zero: true);
    final maskText = j['subnet'];
    if (maskText is! String ||
        !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(maskText)) {
      invalid('Invalid subnet.');
    }
    final parts = maskText.split('.').map(int.parse);
    if (parts.any((n) => n > 255)) invalid('Invalid subnet.');
    final mask = parts.fold(0, (a, b) => (a << 8) | b),
        host = (~mask) & 0xffffffff;
    if (!dhcp &&
        (ip == 0 ||
            mask == 0 ||
            host < 3 ||
            (host & (host + 1)) != 0 ||
            (ip & host) == 0 ||
            (ip & host) == host ||
            gw == 0 ||
            gw == ip ||
            (gw & mask) != (ip & mask) ||
            (gw & host) == 0 ||
            (gw & host) == host)) {
      invalid('Invalid static subnet/IP/gateway.');
    }
    return NetworkConfig(
      ssid,
      boolean(j['passwordConfigured']),
      dhcp,
      j['ip'],
      maskText,
      j['gateway'],
      j['dns1'],
      j['dns2'],
    );
  }
  Json toJson() => {
    'ssid': ssid,
    'passwordConfigured': passwordConfigured,
    'dhcp': dhcp,
    'ip': ip,
    'subnet': subnet,
    'gateway': gateway,
    'dns1': dns1,
    'dns2': dns2,
  };
}

class Configuration {
  Configuration(this.revision, this.buttons, this.routing, this.network);
  final int revision;
  final List<ButtonConfig> buttons;
  final Routing routing;
  final NetworkConfig network;
  factory Configuration.parse(dynamic value) {
    final j = object(value, {
      'schema',
      'revision',
      'buttons',
      'routing',
      'network',
    });
    if (j['schema'] is! int || j['schema'] != 1) {
      invalid('Unsupported configuration schema.');
    }
    final bs = array(j['buttons'], 4);
    if (bs.length != 4) invalid('Exactly four buttons required.');
    if (utf8.encode(jsonEncode(j)).length > maxConfigurationBytes) {
      invalid('Configuration exceeds 12288 bytes.');
    }
    return Configuration(
      number(j['revision'], 0, 0xffffffff),
      bs.map(ButtonConfig.parse).toList(),
      Routing.parse(j['routing']),
      NetworkConfig.parse(j['network']),
    );
  }
  Json toJson() => {
    'schema': 1,
    'revision': revision,
    'buttons': buttons.map((b) => b.toJson()).toList(),
    'routing': routing.toJson(),
    'network': network.toJson(),
  };
}
