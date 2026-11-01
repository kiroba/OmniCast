import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import 'omni_signal_client.dart';
import 'omnicast_call.dart';
import 'omnicast_classroom_mode_ui.dart';
import 'omnicast_settings.dart';

// OmniCast: 1:1 video calls between Omni identities, signaled through Omni Node (daemon v8.21.0+
// relays signaling between nodes). Classroom Mode stays a UI preview with no live video.
// The app must be open to ring; there is no background call service yet.
void main() => runApp(const OmniCastApp());

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class OmniCastApp extends StatelessWidget {
  const OmniCastApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OmniCast',
        navigatorKey: navKey,
        theme: ThemeData.dark(useMaterial3: true),
        home: const OmniCastHome(),
      );
}

class OmniCastHome extends StatefulWidget {
  const OmniCastHome({super.key});
  @override
  State<OmniCastHome> createState() => _OmniCastHomeState();
}

class _OmniCastHomeState extends State<OmniCastHome> {
  StargateIdentity? _id;
  CastHub _hub = const CastHub();
  List<Contact> _contacts = [];
  OmniSignalClient? _client;
  Stream<SignalMessage>? _incoming; // broadcast
  StreamSubscription<SignalMessage>? _router;
  final CalleeOfferTracker _tracker = CalleeOfferTracker();
  CallSession? _active;
  String _link = 'Connecting...';
  bool _linkOk = false;
  // ICE that arrives before the person answers, per caller/call.
  final Map<String, List<RTCIceCandidate>> _earlyIce = {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final id = await StargateIdentity.load();
    final hub = await CastHub.load();
    final contacts = await Contacts.load();
    if (!mounted) return;
    setState(() {
      _id = id;
      _hub = hub;
      _contacts = contacts;
    });
    _connect();
  }

  Future<void> _connect() async {
    await _router?.cancel();
    await _client?.close();
    final id = _id;
    if (id == null) return;
    final c = OmniSignalClient(hub: _hub.signalHub, pubkeyHex: id.pubkeyHex, sign: id.signBytes);
    _client = c;
    _incoming = c.messages().asBroadcastStream();
    setState(() {
      _link = 'Connecting to ${_hub.label}...';
      _linkOk = false;
    });
    _router = _incoming!.listen((m) {
      if (!_linkOk && mounted) setState(() {
        _link = 'Ready for calls via ${_hub.label}';
        _linkOk = true;
      });
      _route(m);
    }, onError: (e) {
      if (!mounted) return;
      final code = e is SignalHubException ? e.statusCode : 0;
      setState(() {
        _linkOk = false;
        _link = code == 401 || code == 403
            ? 'Node refused the token. Open settings and paste it from Omni Node > Connect apps.'
            : code == 0
                ? 'Can\'t reach ${_hub.label}. Is Omni Node on?'
                : 'Node problem (HTTP $code). Retrying...';
      });
    }, cancelOnError: false);
    // A quick empty poll tells us the link works before anyone calls.
    try {
      await c.pollOnce();
      if (mounted) setState(() {
        _link = 'Ready for calls via ${_hub.label}';
        _linkOk = true;
      });
    } on SignalHubException catch (e) {
      if (mounted) setState(() {
        _linkOk = false;
        _link = e.statusCode == 401 || e.statusCode == 403
            ? 'Node refused the token. Open settings and paste it from Omni Node > Connect apps.'
            : e.statusCode == 0
                ? 'Can\'t reach ${_hub.label}. Is Omni Node on?'
                : 'Node problem (HTTP ${e.statusCode}).';
      });
    }
  }

  String _nameFor(String key) {
    for (final c in _contacts) {
      if (c.key == key) return c.name;
    }
    return 'Unknown ${key.substring(0, 4)}…${key.substring(60)}';
  }

  void _route(SignalMessage m) {
    final k = '${m.from}/${m.callId}';
    if (m.kind == SignalKind.ice && (_active == null || _active!.callId != m.callId)) {
      final c = m.iceCandidate;
      if (c != null && c['candidate'] is String) {
        (_earlyIce[k] ??= []).add(RTCIceCandidate(c['candidate'] as String, c['sdpMid'] as String?,
            c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : null));
      }
      return;
    }
    if (m.kind == SignalKind.hangup) {
      _earlyIce.remove(k);
      return; // an active session handles its own hangup
    }
    if (m.kind != SignalKind.offer) return;
    if (_active != null && _active!.phase != CallPhase.ended) {
      if (_active!.callId != m.callId) _client?.hangup(m.from, m.callId); // busy
      return;
    }
    if (_tracker.onOffer(m) != OfferDisposition.fresh) return;
    _showIncoming(m);
  }

  Future<void> _showIncoming(SignalMessage offer) async {
    final name = _nameFor(offer.from);
    final k = '${offer.from}/${offer.callId}';
    var gone = false;
    late final StreamSubscription<SignalMessage> watch;
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    watch = _incoming!.listen((m) {
      if (m.from == offer.from && m.callId == offer.callId && m.kind == SignalKind.hangup && !gone) {
        gone = true;
        navKey.currentState?.maybePop(false);
      }
    }, onError: (_) {});
    final timeout = Timer(OmniCastTimeouts.ringTimeout, () {
      if (!gone) {
        gone = true;
        navKey.currentState?.maybePop(false);
      }
    });
    final accepted = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.videocam, size: 40),
        title: Text(name),
        content: const Text('Incoming video call'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Decline')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.call), label: const Text('Answer')),
        ],
      ),
    );
    timeout.cancel();
    await watch.cancel();
    if (accepted != true) {
      if (!gone) _client?.hangup(offer.from, offer.callId);
      _tracker.end(offer.from, offer.callId);
      _earlyIce.remove(k);
      return;
    }
    final s = CallSession(
      client: _client!,
      peer: offer.from,
      peerName: name,
      callId: offer.callId,
      outgoing: false,
      incoming: _incoming!,
      tracker: _tracker,
    );
    _active = s;
    unawaited(s.answer(offer, _earlyIce.remove(k) ?? []));
    await navKey.currentState?.push(MaterialPageRoute(builder: (_) => CallScreen(session: s)));
    _active = null;
  }

  Future<void> _call(Contact c) async {
    if (_client == null || _incoming == null) return;
    if (!_linkOk) {
      _toast(_link);
      return;
    }
    final s = CallSession(
      client: _client!,
      peer: c.key,
      peerName: c.name,
      callId: newCallId(),
      outgoing: true,
      incoming: _incoming!,
      tracker: _tracker,
    );
    _active = s;
    unawaited(s.startOutgoing());
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(session: s)));
    _active = null;
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ---------------------------------------------------------------- contacts / settings

  Future<void> _addContact() async {
    final name = TextEditingController();
    final key = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(
            controller: key,
            decoration: const InputDecoration(
                labelText: 'Their call ID', helperText: 'They copy it from the top of their OmniCast'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final k = Contact.normalizeKey(key.text);
    if (k == null) {
      _toast('That call ID doesn\'t look right (64 letters and numbers).');
      return;
    }
    if (k == _id?.pubkeyHex) {
      _toast('That\'s your own call ID.');
      return;
    }
    final list = [..._contacts.where((c) => c.key != k), Contact(name.text.trim().isEmpty ? 'Contact' : name.text.trim(), k)];
    await Contacts.save(list);
    setState(() => _contacts = list);
  }

  Future<void> _removeContact(Contact c) async {
    final list = _contacts.where((x) => x.key != c.key).toList();
    await Contacts.save(list);
    setState(() => _contacts = list);
  }

  Future<void> _settings() async {
    final host = TextEditingController(text: _hub.host);
    final token = TextEditingController(text: _hub.token);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Node settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: host,
            decoration: const InputDecoration(labelText: 'Address', helperText: '127.0.0.1 = Omni Node on this phone'),
          ),
          TextField(
            controller: token,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Token', helperText: 'Omni Node > Connect apps > Copy token'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.system_update),
              label: const Text('Check for updates'),
              onPressed: () {
                Navigator.pop(c, false);
                OmniOta.checkAndPrompt(context);
              },
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final next = CastHub(host: host.text.trim().isEmpty ? '127.0.0.1' : host.text.trim(), token: token.text.trim());
    await next.save();
    setState(() => _hub = next);
    _connect();
  }

  @override
  void dispose() {
    _router?.cancel();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniCast'),
        actions: [IconButton(icon: const Icon(Icons.settings), tooltip: 'Node settings', onPressed: _settings)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add),
        label: const Text('Add contact'),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.circle, size: 14, color: _linkOk ? Colors.greenAccent : Colors.orangeAccent),
            title: Text(_link),
            onTap: _linkOk ? null : _settings,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Your call ID'),
            subtitle: Text(id == null ? '...' : id.shortId),
            trailing: const Icon(Icons.copy),
            onTap: id == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: id.pubkeyHex));
                    _toast('Call ID copied. Send it to a friend so they can add you.');
                  },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('Contacts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Add a friend with their call ID. Keep OmniCast open to receive calls.',
                style: TextStyle(color: Colors.white60)),
          ),
        for (final c in _contacts)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(c.name),
              subtitle: Text(c.tag),
              trailing: IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.greenAccent), onPressed: () => _call(c)),
              onLongPress: () => _removeContact(c),
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.school),
            title: const Text('Classroom Mode (preview)'),
            subtitle: const Text('UI preview only, no live video yet'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OmniCastClassroomScreen(classRoomId: 'preview'))),
          ),
        ),
        const SizedBox(height: 80),
      ]),
    );
  }
}
