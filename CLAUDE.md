# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## work
- 最后的回答要有一段用于git提交的总结话语
- 必须使用中文回答
- 改动代码必须要有正确详细的代码注释
- 因为是跨端项目必须同时考虑移动端和桌面端

## Project Overview

AList Player is a cross-platform video player built with Flutter that integrates with [AList](https://alist.nn.ci/) file management system. It supports Android, iOS, Windows, macOS, Linux, and Web platforms. The app provides video playback with progress saving, history tracking, and multi-device data sync via PostgreSQL/SQLite.

## Build and Development Commands

```bash
# Install dependencies
flutter pub get

# Run with hot reload
flutter run

# Code analysis (must pass with zero warnings)
flutter analyze

# Run tests
flutter test

# Format code
dart format .

# Generate code from annotations (Freezed, JSON serialization)
flutter pub run build_runner build --delete-conflicting-outputs

# Generate app icons
flutter pub run flutter_launcher_icons
```

### Platform-Specific Builds

```bash
# Android
./scripts/build_android.sh [--release|--debug] [--apk|--aab] [--clean]

# iOS (requires macOS)
./scripts/build_ios.sh [--release|--debug] [--simulator|--device] [--clean]

# macOS
./scripts/build_macos.sh [--release|--debug] [--clean]

# Multi-platform
./scripts/build_all.sh --platforms macos,windows,linux,android,ios [--clean]

# Go database bridge (in go/go_bridge/)
go run .
./build_release.sh  # For production
```

## Architecture

```
lib/
├── apis/           # HTTP API bindings (AList REST endpoints)
├── constants/      # App-wide constants
├── models/         # DTOs and data classes
├── services/       # Business logic layer
│   ├── persistence/  # Database drivers (PostgreSQL, SQLite, Go bridge)
│   ├── player/       # Media playback services
│   └── go_bridge/    # Go service integration
├── utils/          # Helpers (logger, config managers, download adapters)
├── views/          # Screen pages
│   ├── settings/     # Settings dialogs and pages
│   └── admin/        # Admin dashboard
├── widgets/        # Reusable UI components
└── main.dart       # Entry point with initialization
```

### Key Components

- **media_kit**: Cross-platform video playback engine with hardware acceleration
- **Persistence Layer**: Pluggable database support - PostgreSQL (remote sync), SQLite (local), or Go bridge proxy for MySQL/Oracle
- **ApiConfigManager / DatabaseConfigManager**: Manage multiple server presets for easy switching
- **AppLogger**: Global logging with file persistence, captures print/debugPrint/FlutterError
- **ConfigServer**: Built-in HTTP server for cross-device configuration sync

## Coding Conventions

- Use Chinese comments for code documentation
- Final git commit messages should be in Chinese
- Must consider both mobile and desktop platforms for all changes
- Use `log` instead of `print` for debugging
- Lines should not exceed 80 characters
- Use trailing commas for multi-line arguments
- Prefer `ConsumerWidget` (Riverpod) or `HookConsumerWidget` for state-dependent widgets
- Use `AsyncValue` for async state handling with proper loading/error states
- Create small private widget classes instead of `Widget _build...()` methods
- Always include `errorBuilder` when using `Image.network`

## State Management

- Uses Riverpod with `@riverpod` annotation for provider generation
- Prefer `AsyncNotifierProvider` and `NotifierProvider` over deprecated `StateProvider`
- Use `ref.invalidate()` for manual provider updates

## Database Schema

- Tables include `createdAt`, `updatedAt`, and `isDeleted` fields
- Models use `@JsonSerializable(fieldRename: FieldRename.snake)`
- Read-only fields use `@JsonKey(includeFromJson: true, includeToJson: false)`

## CI/CD

GitHub Actions workflow (`.github/workflows/flutter.yml`) builds all platforms on tag push. Flutter version: 3.29.3 stable.
