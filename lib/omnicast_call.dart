// OmniCast 1:1 calls: flutter_webrtc media + the signed signaling mailbox (omni_signal_client.dart).
//
// Signaling goes through this phone's node (Omni Node or a hub). Daemon v8.21.0+ forwards each signed
// message to its peers and pulls from them while we long-poll, so two phones on different nodes find
// each other through any node both can reach. Media is peer to peer (STUN), or through TURN when the
// node hands out TURN credentials.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'omni_signal_client.dart';

enum CallPhase { starting, ringing, connecting, connected, ended }

/// One call, either direction. Owns the peer connection, local media and renderers.
class CallSession extends ChangeNotifier {
  final OmniSignalClient client;
  final String peer; // their pubkey
  final String peerName;
  final String callId;
  final bool outgoing;
  final Stream<SignalMessage> incoming; // the app's broadcast stream
  final CalleeOfferTracker tracker;

  CallPhase phase = CallPhase.starting;
  String status = 'Starting...';
  bool micOn = true;
  bool camOn = true;
  final RTCVideoRenderer localView = RTCVideoRenderer();
  final RTCVideoRenderer remoteView = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  StreamSubscription<SignalMessage>? _sub;
  OfferResender? _resender;
  Timer? _connectTimer;

  CallSession({
    required this.client,
    required this.peer,
    required this.peerName,
    required this.callId,
    required this.outgoing,
    required this.incoming,
    required this.tracker,
  });

  void _set(CallPhase p, String s) {
    if (phase == CallPhase.ended) return;
    phase = p;
    status = s;
    notifyListeners();
  }

  Future<void> _setup() async {
    await localView.initialize();
    await remoteView.initialize();
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 24},
    });
    localView.srcObject = _local;
    SignalIceConfig ice;
    try {
      ice = await client.fetchIceConfiguration();
    } catch (_) {
      // Node unreachable: no third-party fallback. Direct (same Wi-Fi / IPv6) paths still work.
      ice = const SignalIceConfig(iceServers: [], iceTransportPolicy: 'all', turn: false);
    }
    final pc = await createPeerConnection(ice.rtcConfiguration);
    _pc = pc;
    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      client.sendIce(peer, callId, candidate: cand, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex);
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteView.srcObject = e.streams.first;
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _connectTimer?.cancel();
          _set(CallPhase.connected, 'Connected');
          _reportPath();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _end('Connection failed. Both networks may block direct calls; an Omni node with relaying on fixes that.',
              notify: true);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          if (phase == CallPhase.connected) _set(CallPhase.connecting, 'Reconnecting...');
          break;
        default:
          break;
      }
    };
    _sub = incoming.listen(_onSignal, onError: (_) {}, cancelOnError: false);
  }

  /// How the media flows, from the selected ICE candidate pair: shown in the status line so
  /// testers can tell direct, hole-punched and relayed calls apart.
  Future<void> _reportPath() async {
    try {
      final stats = await _pc?.getStats();
      if (stats == null) return;
      final byId = {for (final r in stats) r.id: r};
      String? pairId;
      for (final r in stats) {
        if (r.type == 'transport' && r.values['selectedCandidatePairId'] is String) {
          pairId = r.values['selectedCandidatePairId'] as String;
        }
      }
      pairId ??= stats
          .where((r) => r.type == 'candidate-pair' && r.values['state'] == 'succeeded' && r.values['nominated'] == true)
          .map((r) => r.id)
          .firstOrNull;
      final pair = pairId == null ? null : byId[pairId];
      final local = pair == null ? null : byId[pair.values['localCandidateId']];
      final remote = pair == null ? null : byId[pair.values['remoteCandidateId']];
      final lt = local?.values['candidateType'];
      final rt = remote?.values['candidateType'];
      String path;
      if (lt == 'relay' || rt == 'relay') {
        path = 'relayed through an Omni node';
      } else if (lt == 'srflx' || rt == 'srflx' || lt == 'prflx' || rt == 'prflx') {
        path = 'direct (through the router)';
      } else if (lt == 'host') {
        path = 'direct';
      } else {
        return;
      }
      if (phase == CallPhase.connected) _set(CallPhase.connected, 'Connected · $path');
    } catch (_) {
      // Stats are a nice-to-have; never end a call over them.
    }
  }

  void _onSignal(SignalMessage m) {
    if (m.from != peer || m.callId != callId) return;
    if (m.kind == SignalKind.ice) {
      final c = m.iceCandidate;
      if (c == null || c['candidate'] is! String) return;
      final cand = RTCIceCandidate(c['candidate'] as String, c['sdpMid'] as String?,
          c['sdpMLineIndex'] is int ? c['sdpMLineIndex'] as int : null);
      addRemoteIce(cand);
    } else if (m.kind == SignalKind.hangup) {
      _end(phase == CallPhase.ringing ? '$peerName didn\'t pick up' : '$peerName hung up', notify: false);
    } else if (m.kind == SignalKind.offer && !outgoing) {
      // The caller re-sent its offer: our answer was probably lost.
      if (tracker.onOffer(m) == OfferDisposition.duplicateAnswered) tracker.resendAnswer(client, m);
    }
  }

  void addRemoteIce(RTCIceCandidate c) {
    if (_remoteSet && _pc != null) {
      _pc!.addCandidate(c);
    } else {
      _pendingIce.add(c);
    }
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void _armConnectTimeout() {
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(seconds: 30), () {
      if (phase != CallPhase.connected) {
        _end('Couldn\'t connect the media. Both networks may block direct calls; an Omni node with relaying on fixes that.',
            notify: true);
      }
    });
  }

  /// Caller side: offer, re-sent until answered (45 s ring).
  Future<void> startOutgoing() async {
    try {
      await _setup();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
      await _pc!.setLocalDescription(offer);
      _set(CallPhase.ringing, 'Calling $peerName...');
      _resender = OfferResender(client);
      final answer = await _resender!.sendUntilAnswered(
          to: peer, callId: callId, sdp: offer.sdp ?? '', incoming: incoming);
      if (phase == CallPhase.ended) return;
      if (answer == null) {
        _end('No answer', notify: true);
        return;
      }
      _set(CallPhase.connecting, 'Connecting...');
      await _pc!.setRemoteDescription(RTCSessionDescription(answer.payload, 'answer'));
      await _flushIce();
      _armConnectTimeout();
    } catch (e) {
      _end('Call failed: $e', notify: true);
    }
  }

  /// Callee side, after the person tapped Answer. [earlyIce] arrived before they did.
  Future<void> answer(SignalMessage offer, List<RTCIceCandidate> earlyIce) async {
    try {
      _pendingIce.addAll(earlyIce);
      await _setup();
      _set(CallPhase.connecting, 'Connecting...');
      await _pc!.setRemoteDescription(RTCSessionDescription(offer.payload, 'offer'));
      await _flushIce();
      final ans = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(ans);
      final r = await tracker.answer(client, offer, ans.sdp ?? '');
      if (!r.ok) {
        _end('Couldn\'t send the answer (${r.error})', notify: true);
        return;
      }
      _armConnectTimeout();
    } catch (e) {
      _end('Call failed: $e', notify: true);
    }
  }

  void toggleMic() {
    micOn = !micOn;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    notifyListeners();
  }

  void toggleCam() {
    camOn = !camOn;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final v = _local?.getVideoTracks();
    if (v != null && v.isNotEmpty) await Helper.switchCamera(v.first);
  }

  /// The person tapped hang up.
  void hangUp() => _end('Call ended', notify: true);

  void _end(String why, {required bool notify}) {
    if (phase == CallPhase.ended) return;
    if (notify) client.hangup(peer, callId);
    tracker.end(peer, callId);
    _resender?.cancel();
    _connectTimer?.cancel();
    phase = CallPhase.ended;
    status = why;
    notifyListeners();
    _teardown();
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _local = null;
  }

  @override
  void dispose() {
    _end('Call ended', notify: phase != CallPhase.ended);
    localView.srcObject = null;
    remoteView.srcObject = null;
    localView.dispose();
    remoteView.dispose();
    super.dispose();
  }
}

/// Full-screen call: their video, mine in the corner, mic / camera / flip / hang up.
class CallScreen extends StatefulWidget {
  final CallSession session;
  const CallScreen({super.key, required this.session});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (s.phase == CallPhase.ended) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    s.dispose();
    super.dispose();
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: label,
            backgroundColor: color ?? Colors.white24,
            onPressed: onTap,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final connected = s.phase == CallPhase.connected;
    return PopScope(
      canPop: s.phase == CallPhase.ended,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: connected || s.remoteView.srcObject != null
                  ? RTCVideoView(s.remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircleAvatar(radius: 44, child: Icon(Icons.person, size: 48)),
                        const SizedBox(height: 16),
                        Text(s.peerName, style: const TextStyle(color: Colors.white, fontSize: 24)),
                      ]),
                    ),
            ),
            Positioned(
              top: 12,
              left: 16,
              right: 140,
              child: Text(s.status,
                  style: TextStyle(
                      color: s.phase == CallPhase.ended ? Colors.orangeAccent : Colors.white, fontSize: 16)),
            ),
            Positioned(
              top: 12,
              right: 12,
              width: 112,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white10,
                  child: s.camOn
                      ? RTCVideoView(s.localView,
                          mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      : const Center(child: Icon(Icons.videocam_off, color: Colors.white54)),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _btn(s.micOn ? Icons.mic : Icons.mic_off, s.micOn ? 'Mute' : 'Unmute', s.toggleMic),
                _btn(s.camOn ? Icons.videocam : Icons.videocam_off, s.camOn ? 'Camera off' : 'Camera on',
                    s.toggleCam),
                _btn(Icons.cameraswitch, 'Flip', s.flipCamera),
                _btn(Icons.call_end, 'Hang up', () {
                  if (s.phase == CallPhase.ended) {
                    Navigator.of(context).maybePop();
                  } else {
                    s.hangUp();
                  }
                }, color: Colors.redAccent),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
