import 'package:flutter_test/flutter_test.dart';
import 'package:symterra_rich_text_controller/symterra_rich_text_controller.dart';
import 'package:flutter/material.dart';

void main() {
  group('SymTerraRichTextController', () {
    final mentionPattern = PatternStyle(
      key: 'mention',
      pattern: RegExp(r'@[A-Za-z0-9_]+'),
      style: const TextStyle(color: Color(0xFF2196F3)),
      trigger: '@',
    );

    test('insertToken inserts at caret', () {
      final controller = SymTerraRichTextController(patterns: [mentionPattern]);
      controller.text = 'Hello ';
      controller.selection = const TextSelection.collapsed(offset: 6);
      controller.insertToken(patternKey: 'mention', visibleText: '@alice');
      expect(controller.text, 'Hello @alice');
      expect(controller.idTokens.length, 0);
    });

    test('insertToken replaces active handle', () {
      final controller = SymTerraRichTextController(patterns: [mentionPattern]);
      controller.text = 'Hello @al';
      controller.selection = const TextSelection.collapsed(offset: 9);
      controller.insertToken(patternKey: 'mention', visibleText: '@alice');
      expect(controller.text, 'Hello @alice');
    });

    test('insertToken with tokenId adds ID-backed token', () {
      final controller = SymTerraRichTextController(patterns: [mentionPattern]);
      controller.text = 'Hey ';
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.insertToken(patternKey: 'mention', visibleText: '@bob', tokenId: 'user_123');
      expect(controller.text, 'Hey @bob');
      expect(controller.idTokens.length, 1);
      expect(controller.idTokens.first.id, 'user_123');
    });

    test('atomic deletion removes whole token', () {
      final controller = SymTerraRichTextController(patterns: [mentionPattern]);
      controller.text = 'Hi @alice!';
      controller.selection = const TextSelection.collapsed(offset: 4); // Inside @alice
      final oldText = controller.text;
      // Simulate backspace inside token
      controller.value = TextEditingValue(text: 'Hi !', selection: const TextSelection.collapsed(offset: 4));
      expect(controller.text, 'Hi !');
      expect(controller.text.length, lessThan(oldText.length));
    });

    test('deletion outside token behaves normally', () {
      final controller = SymTerraRichTextController(patterns: [mentionPattern]);
      controller.text = 'Hello @alice!';
      controller.selection = const TextSelection.collapsed(offset: 5); // After 'Hello'
      controller.value = TextEditingValue(text: 'Hell @alice!', selection: const TextSelection.collapsed(offset: 4));
      expect(controller.text, 'Hell @alice!');
    });
  });
}
