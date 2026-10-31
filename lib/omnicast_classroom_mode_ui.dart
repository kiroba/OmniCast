// omnicast_classroom_mode_ui.dart
// OmniCast - Educator Classroom Mode UI (Flutter / Dart)
// Serverless P2P Classroom Session with Stage Controls, Raise Hand Queue, and Local Signaling

import 'dart:convert';
import 'package:flutter/material.dart';

class OmniCastClassroomScreen extends StatefulWidget {
  final String classRoomId;
  final String userRole; // 'educator' or 'student'

  const OmniCastClassroomScreen({
    super.key,
    required this.classRoomId,
    this.userRole = 'student',
  });

  @override
  State<OmniCastClassroomScreen> createState() => _OmniCastClassroomScreenState();
}

class _OmniCastClassroomScreenState extends State<OmniCastClassroomScreen> {
  bool _isMicMuted = false;
  bool _isVideoOff = false;
  bool _isHandRaised = false;
  bool _isScreenSharing = false;

  final List<Map<String, String>> _raisedHands = [
    {'student_id': '0x8a12...3f4e', 'name': 'Alex M.', 'time': '10:14 AM'},
    {'student_id': '0x3c99...8b01', 'name': 'Jordan K.', 'time': '10:15 AM'},
  ];

  final List<Map<String, dynamic>> _classroomChat = [
    {
      'author': 'Prof. Keith',
      'role': 'Educator',
      'message': 'Welcome to P2P Systems 101. Today we cover Negentropy set reconciliation.',
      'timestamp': '10:00 AM'
    },
    {
      'author': 'Alex M.',
      'role': 'Student',
      'message': 'Is the range fingerprint computed per timestamp bucket?',
      'timestamp': '10:12 AM'
    },
  ];

  final TextEditingController _chatController = TextEditingController();

  void _toggleRaiseHand() {
    setState(() {
      _isHandRaised = !_isHandRaised;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isHandRaised ? 'Hand raised for Educator' : 'Hand lowered'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;
    setState(() {
      _classroomChat.add({
        'author': widget.userRole == 'educator' ? 'Prof. Keith' : 'Student (You)',
        'role': widget.userRole == 'educator' ? 'Educator' : 'Student',
        'message': _chatController.text.trim(),
        'timestamp': 'Just now',
      });
      _chatController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OmniCast Classroom: ${widget.classRoomId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 12, color: Colors.tealAccent),
                const SizedBox(width: 4),
                Text(
                  'Role: ${widget.userRole.toUpperCase()} | P2P TURN Sync Active',
                  style: const TextStyle(fontSize: 11, color: Colors.tealAccent),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: Colors.white70),
            onPressed: () => _showParticipantsModal(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Main Stage View (Educator Stream / Screen Share)
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.3), width: 1),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isScreenSharing ? Icons.screen_share : Icons.cast_for_education,
                            size: 64,
                            color: Colors.tealAccent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isScreenSharing
                                ? 'Educator Screen Stream (WebRTC 1080p)'
                                : 'Stage Video Stream (Prof. Keith)',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'P2P Loopback IPC :5000 | E2E Ed25519 Verified',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Live Indicator Badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent, width: 0.8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.circle, size: 8, color: Colors.redAccent),
                            SizedBox(width: 6),
                            Text('LIVE CLASSROOM', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Educator Moderation Bar or Student Question Status Bar
            if (widget.userRole == 'educator') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pan_tool, size: 18, color: Colors.amberAccent),
                        const SizedBox(width: 8),
                        Text(
                          '${_raisedHands.length} Student(s) Raising Hand',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => _showRaisedHandsModal(context),
                      child: const Text('View Queue', style: TextStyle(color: Colors.tealAccent)),
                    ),
                  ],
                ),
              ),
            ],

            // Classroom P2P Chat Stream
            Expanded(
              flex: 4,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Classroom Chat & Q&A Stream',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const Divider(color: Colors.white10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _classroomChat.length,
                        itemBuilder: (context, index) {
                          final item = _classroomChat[index];
                          final isEdu = item['role'] == 'Educator';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: isEdu ? Colors.teal : Colors.indigo,
                                  child: Text(
                                    item['author']![0],
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            item['author']!,
                                            style: TextStyle(
                                              color: isEdu ? Colors.tealAccent : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (isEdu) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.verified_user, size: 12, color: Colors.tealAccent),
                                          ],
                                          const SizedBox(width: 6),
                                          Text(
                                            item['timestamp']!,
                                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['message']!,
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // Chat Input Box
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Ask a question or comment...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.tealAccent),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Classroom Control Deck
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF1E293B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(_isMicMuted ? Icons.mic_off : Icons.mic, color: _isMicMuted ? Colors.redAccent : Colors.white),
                    onPressed: () => setState(() => _isMicMuted = !_isMicMuted),
                  ),
                  IconButton(
                    icon: Icon(_isVideoOff ? Icons.videocam_off : Icons.videocam, color: _isVideoOff ? Colors.redAccent : Colors.white),
                    onPressed: () => setState(() => _isVideoOff = !_isVideoOff),
                  ),
                  if (widget.userRole == 'student')
                    ElevatedButton.icon(
                      onPressed: _toggleRaiseHand,
                      icon: Icon(Icons.pan_tool, color: _isHandRaised ? Colors.black : Colors.amberAccent, size: 18),
                      label: Text(_isHandRaised ? 'Hand Raised' : 'Raise Hand'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isHandRaised ? Colors.amberAccent : const Color(0xFF0F172A),
                        foregroundColor: _isHandRaised ? Colors.black : Colors.white,
                      ),
                    ),
                  if (widget.userRole == 'educator') ...[
                    IconButton(
                      icon: Icon(_isScreenSharing ? Icons.stop_screen_share : Icons.screen_share, color: Colors.tealAccent),
                      onPressed: () => setState(() => _isScreenSharing = !_isScreenSharing),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.redAccent),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showParticipantsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Connected Classroom Nodes (3)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.school, color: Colors.tealAccent),
              title: Text('Prof. Keith (Educator Host)', style: TextStyle(color: Colors.white)),
              subtitle: Text('Direct Hub Node :5000', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
            ListTile(
              leading: Icon(Icons.person, color: Colors.indigoAccent),
              title: Text('Alex M. (Student)', style: TextStyle(color: Colors.white)),
              subtitle: Text('Tailscale Mesh Peer', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
            ListTile(
              leading: Icon(Icons.person, color: Colors.indigoAccent),
              title: Text('Jordan K. (Student)', style: TextStyle(color: Colors.white)),
              subtitle: Text('Local LAN Peer', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRaisedHandsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Raised Hand Queue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ..._raisedHands.map((student) => ListTile(
                  leading: const Icon(Icons.pan_tool, color: Colors.amberAccent),
                  title: Text(student['name']!, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('Raised at ${student['time']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Unmuted ${student['name']} for microphone stage access')),
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                    child: const Text('Grant Mic'),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
