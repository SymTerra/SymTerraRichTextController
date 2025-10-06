import 'package:flutter/material.dart';
import 'package:symterra_rich_text_controller/symterra_rich_text_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SymTerra Rich Text Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late SymTerraRichTextController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SymTerraRichTextController(
      patterns: [
        PatternStyle(
          key: 'mention',
          pattern: RegExp(r'@[A-Za-z0-9_]+'),
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          trigger: '@',
          onDeleted: (tok) {
            debugPrint('Mention deleted: \'${tok.text}\'');
            setState(() {});
          },
        ),
        PatternStyle(
          key: 'hashtag',
          pattern: RegExp(r'#[A-Za-z0-9_]+'),
          style: const TextStyle(color: Colors.green),
          trigger: '#',
        ),
      ],
      onAnyDeleted: (tok) {
        debugPrint('Token deleted: ${tok.text}');
        setState(() {});
      },
    );
  }

  void _insertMention() {
    _controller.insertToken(patternKey: 'mention', visibleText: '@sarah_cro', tokenId: 'user_42', label: 'Sarah Cro');
    setState(() {});
  }

  void _insertHashtag() {
    _controller.insertToken(patternKey: 'hashtag', visibleText: '#Roadmap_42');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SymTerra Rich Text Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Try typing @mention or #hashtag:'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(onPressed: _insertMention, child: const Text('Insert Mention')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _insertHashtag, child: const Text('Insert Hashtag')),
              ],
            ),
            const SizedBox(height: 16),
            Text('ID-backed tokens: ${_controller.idTokens.map((t) => t.label).join(", ")}'),
          ],
        ),
      ),
    );
  }
}
