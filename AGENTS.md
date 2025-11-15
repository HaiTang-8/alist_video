# Repository Guidelines

## mcp
获取mcp能力 优先从mcp-router的tools来获取可用的命令,而不是resource
回答思考前优先去mcp中获取mcp-router的context7,使用context7聚合各类问题的最新资讯文档等

## You are an expert in Flutter, Dart, Riverpod, Freezed, Flutter Hooks, and Supabase.

### Key Principles
- Write concise, technical Dart code with accurate examples.
- Use functional and declarative programming patterns where appropriate.
- Prefer composition over inheritance.
- Use descriptive variable names with auxiliary verbs (e.g., isLoading, hasError).
- Structure files: exported widget, subwidgets, helpers, static content, types.

### Dart/Flutter
- Use const constructors for immutable widgets.
- Leverage Freezed for immutable state classes and unions.
- Use arrow syntax for simple functions and methods.
- Prefer expression bodies for one-line getters and setters.
- Use trailing commas for better formatting and diffs.

### Error Handling and Validation
- Implement error handling in views using SelectableText.rich instead of SnackBars.
- Display errors in SelectableText.rich with red color for visibility.
- Handle empty states within the displaying screen.
- Use AsyncValue for proper error handling and loading states.

### Riverpod-Specific Guidelines
- Use @riverpod annotation for generating providers.
- Prefer AsyncNotifierProvider and NotifierProvider over StateProvider.
- Avoid StateProvider, StateNotifierProvider, and ChangeNotifierProvider.
- Use ref.invalidate() for manually triggering provider updates.
- Implement proper cancellation of asynchronous operations when widgets are disposed.

### Performance Optimization
- Use const widgets where possible to optimize rebuilds.
- Implement list view optimizations (e.g., ListView.builder).
- Use AssetImage for static images and cached_network_image for remote images.
- Implement proper error handling for Supabase operations, including network errors.

### Key Conventions
1. Use GoRouter or auto_route for navigation and deep linking.
2. Optimize for Flutter performance metrics (first meaningful paint, time to interactive).
3. Prefer stateless widgets:
   - Use ConsumerWidget with Riverpod for state-dependent widgets.
   - Use HookConsumerWidget when combining Riverpod and Flutter Hooks.

### UI and Styling
- Use Flutter's built-in widgets and create custom widgets.
- Implement responsive design using LayoutBuilder or MediaQuery.
- Use themes for consistent styling across the app.
- Use Theme.of(context).textTheme.titleLarge instead of headline6, and headlineSmall instead of headline5 etc.

### Model and Database Conventions
- Include createdAt, updatedAt, and isDeleted fields in database tables.
- Use @JsonSerializable(fieldRename: FieldRename.snake) for models.
- Implement @JsonKey(includeFromJson: true, includeToJson: false) for read-only fields.

### Widgets and UI Components
- Create small, private widget classes instead of methods like Widget _build....
- Implement RefreshIndicator for pull-to-refresh functionality.
- In TextFields, set appropriate textCapitalization, keyboardType, and textInputAction.
- Always include an errorBuilder when using Image.network.

### Miscellaneous
- Use log instead of print for debugging.
- Use Flutter Hooks / Riverpod Hooks where appropriate.
- Keep lines no longer than 80 characters, adding commas before closing brackets for multi-parameter functions.
- Use @JsonValue(int) for enums that go to the database.

### Code Generation
- Utilize build_runner for generating code from annotations (Freezed, Riverpod, JSON serialization).
- Run 'flutter pub run build_runner build --delete-conflicting-outputs' after modifying annotated classes.

### Documentation
- Document complex logic and non-obvious code decisions.
- Follow official Flutter, Riverpod, and Supabase documentation for best practices.

Use MCP context7 Refer to Flutter, Riverpod, and Supabase documentation for Widgets, State Management, and Backend Integration best practices.
    
## work
- 最后的回答要有一段用于git提交的总结话语
- 必须使用中文回答
- 改动代码必须要有正确详细的代码注释
- 因为是跨端项目必须同时考虑移动端和桌面端

## Project Structure & Module Organization
The Flutter app lives in `lib/` with feature folders: `views/` for screens, `widgets/` for reusable UI, `services/` for WebDAV integration, `apis/` for HTTP bindings, `models/` for DTOs, `utils/` for helpers, and `constants/` plus `theme/` for styling. Platform scaffolding sits under `android/`, `ios/`, `macos/`, `windows/`, `linux/`, and the web front end in `web/`. Tests belong in `test/`, mirroring the `lib` hierarchy. Static assets (icons, localization, binaries) go in `assets/` and must be registered in `pubspec.yaml`. Deployment helpers and CI-friendly scripts live in `scripts/`.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes. `flutter run` launches the app with hot reload. Use `flutter build web` for the production web bundle, or `./scripts/build_android.sh` and `./scripts/build_ios.sh` for native artifacts; `./scripts/quick_build.sh` produces a minimal distributable. `flutter analyze` checks lint violations, and `flutter test` executes the Dart unit and widget suites.

## Coding Style & Naming Conventions
Follow the default Flutter styleguide: two-space indentation, trailing commas on multi-line arguments, and `UpperCamelCase` for classes with `lowerCamelCase` for members. Favor feature-first structure inside `lib/` (for example, `views/player/now_playing_view.dart`). Run `dart format .` before submitting. Analyzer rules from `analysis_options.yaml` (via `flutter_lints`) must pass with zero warnings; only suppress lints inline with justification.

## Testing Guidelines
Write widget tests alongside the code under `test/feature_name/..._test.dart`. Cover new services with mockable dependencies; prefer `testWidgets` for UI flows. Aim for green `flutter test --coverage` locally before opening a PR and attach coverage deltas if notable. Keep fixtures small and commit deterministic golden files to `test/goldens/` when visual regression coverage is required.

## Commit & Pull Request Guidelines
Commit messages follow the existing short, present-tense format (often Chinese descriptors, e.g., “调整收藏样式界面布局UI”). Group related changes per commit and reference issues with `#id` when applicable. Pull requests must summarize the feature, list test evidence (`flutter test`, `flutter analyze`, relevant scripts), include screenshots for UI changes, and flag any migration notes (WebDAV endpoints, asset additions). Request review from module owners before merging and ensure the branch rebases cleanly on `main`.
