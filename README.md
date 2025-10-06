
# SymTerraRichTextController

A powerful rich text controller for Flutter, designed for advanced text editing scenarios such as mentions, hashtags, atomic tokens, and syntax highlighting. Perfect for chat, comments, and collaborative apps.

## Features

- **Pattern-based syntax highlighting**: Easily highlight mentions (`@user`), hashtags (`#topic`), URLs, and more using custom regex patterns.
- **Atomic tokens**: Typing or deleting inside a token (e.g., a mention) removes the whole token, ensuring clean editing.
- **ID-backed tokens**: Attach stable IDs to tokens for robust data binding (e.g., mentions with user IDs).
- **Token insertion**: Insert tokens at the caret or replace active handles (e.g., typing `@sa` and selecting `@sarah_cro`).
- **Delete callbacks**: Listen for token deletions with per-pattern or global callbacks.
- **Customizable styles**: Define how each pattern is rendered with `TextStyle`.

## Getting Started

Install using Flutter's package manager:

```sh
flutter pub add symterra_rich_text_controller
```

Or add it manually to your `pubspec.yaml`:

```yaml
dependencies:
    symterra_rich_text_controller: ^latest_version
```

If you are developing locally, use:

```yaml
dependencies:
    symterra_rich_text_controller:
        path: ../
```

## Usage

Define your patterns and create a controller:

```dart
final controller = SymTerraRichTextController(
	patterns: [
		PatternStyle(
			key: 'mention',
			pattern: RegExp(r'@[A-Za-z0-9_]+'),
			style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
			trigger: '@',
			onDeleted: (tok) {
				print('Mention deleted: \'${tok.text}\'');
			},
		),
		PatternStyle(
			key: 'hashtag',
			pattern: RegExp(r'#[A-Za-z0-9_]+'),
			style: TextStyle(color: Colors.green),
			trigger: '#',
		),
	],
	onAnyDeleted: (tok) {
		print('Token deleted: ${tok.text}');
	},
);

TextField(
	controller: controller,
	maxLines: null,
	decoration: InputDecoration(border: OutlineInputBorder()),
)
// Insert a mention token programmatically:
controller.insertToken(
	patternKey: 'mention',
	visibleText: '@sarah_cro',
	tokenId: 'user_42', // Reference your backend user ID
	label: 'Sarah Cro',
);

// Access ID-backed tokens:
final tokens = controller.idTokens;
```

### When to use `insertToken`

Use `insertToken` when you want to programmatically add a token to the text field, such as when a user selects an item from a dropdown or autocomplete list. This is especially useful for referencing backend entities (like users, projects, or tags) by their stable IDs, ensuring your UI and backend stay in sync. For example:

- **Mentions**: Insert a mention with a user ID so you can reference the correct user in your backend, even if their display name changes.
- **Tags/Projects**: Insert a hashtag or project reference with a unique ID for robust data binding.
- **Replacing handles**: Automatically replace partial handles (e.g., `@sa`) with a full token (`@sarah_cro`) when selected.


## Example Project

See the [`example/`](example/) folder for a complete Flutter app demonstrating mentions, hashtags, token insertion, and callbacks.

## API Overview

- `SymTerraRichTextController`: Main controller, extends `TextEditingController`.
- `PatternStyle`: Defines a pattern, its style, trigger, and delete callback.
- `DeletedToken`: Payload for deleted tokens.
- `insertToken(...)`: Insert a token at the caret or replace an active handle.
- `idTokens`: List of all ID-backed tokens in the text.

## Contributing & Issues

Feel free to open issues or pull requests! For questions, suggestions, or bug reports, please use the GitHub issue tracker.

---
Made with ❤️ by SymTerra.
