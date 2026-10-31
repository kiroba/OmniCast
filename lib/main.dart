import 'package:flutter/material.dart';
import 'omnicast_classroom_mode_ui.dart';

// OmniCast entry point. 1:1 calls (flutter_webrtc + omni_signal_client.dart) are not wired yet;
// Classroom Mode is a UI preview from the NotebookLM design with no live video behind it.
void main() => runApp(const OmniCastApp());

class OmniCastApp extends StatelessWidget {
  const OmniCastApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OmniCast',
        theme: ThemeData.dark(useMaterial3: true),
        home: const OmniCastHome(),
      );
}

class OmniCastHome extends StatelessWidget {
  const OmniCastHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OmniCast')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.call),
              title: Text('1:1 calls'),
              subtitle: Text('Not wired yet'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school),
              title: const Text('Classroom Mode (preview)'),
              subtitle: const Text('UI preview only, no live video yet'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const OmniCastClassroomScreen(classRoomId: 'preview'))),
            ),
          ),
        ]),
      );
}
