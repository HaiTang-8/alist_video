# 编译打包脚本说明

本目录包含了用于编译和打包 AlistPlayer 应用的脚本，支持 macOS、Windows 和其他平台。

## 脚本列表

### 1. `build_macos.sh` - macOS 专用构建脚本

专门用于在 macOS 上构建和打包应用，生成 `.app` 文件和 `.dmg` 安装包。

**用法:**
```bash
./scripts/build_macos.sh [选项]
```

**选项:**
- `--release` - 构建发布版本 (默认)
- `--debug` - 构建调试版本
- `--clean` - 清理构建缓存
- `-h, --help` - 显示帮助信息

**示例:**
```bash
# 构建发布版本
./scripts/build_macos.sh

# 构建调试版本并清理缓存
./scripts/build_macos.sh --debug --clean
```

**输出:**
- `dist/macos/AlistPlayer.app` - macOS 应用程序
- `dist/macos/AlistPlayer_版本号_macOS.dmg` - DMG 安装包

### 2. `build_windows.bat` - Windows 专用构建脚本

专门用于在 Windows 上构建和打包应用，生成可执行文件和 ZIP 压缩包。

**用法:**
```cmd
scripts\build_windows.bat [选项]
```

**选项:**
- `release` - 构建发布版本 (默认)
- `debug` - 构建调试版本
- `clean` - 清理构建缓存
- `-h, --help` - 显示帮助信息

**示例:**
```cmd
REM 构建发布版本
scripts\build_windows.bat

REM 构建调试版本并清理缓存
scripts\build_windows.bat debug clean
```

**输出:**
- `dist\windows\AlistPlayer\` - Windows 应用程序目录
- `dist\windows\AlistPlayer_版本号_Windows.zip` - ZIP 压缩包

### 3. `build_all.sh` - 跨平台构建脚本

支持一次性构建多个平台的应用，适用于 CI/CD 或批量构建。

**用法:**
```bash
./scripts/build_all.sh [选项]
```

**选项:**
- `--release` - 构建发布版本 (默认)
- `--debug` - 构建调试版本
- `--clean` - 清理构建缓存
- `--platforms PLATFORMS` - 指定构建平台，用逗号分隔
- `-h, --help` - 显示帮助信息

**支持的平台:**
- `macos` - macOS 应用 (需要在 macOS 上运行)
- `windows` - Windows 应用
- `linux` - Linux 应用
- `android` - Android APK
- `ios` - iOS 应用 (需要在 macOS 上运行)
- `web` - Web 应用

**示例:**
```bash
# 构建所有平台 (默认: macos,windows,linux)
./scripts/build_all.sh

# 只构建 macOS 和 Windows
./scripts/build_all.sh --platforms macos,windows

# 构建调试版本并清理缓存
./scripts/build_all.sh --debug --clean

# 构建 Android 和 Web 版本
./scripts/build_all.sh --platforms android,web
```

## 前置要求

### 通用要求
- Flutter SDK (3.4.1 或更高版本)
- Dart SDK
- 项目依赖已安装 (`flutter pub get`)

### macOS 构建要求
- macOS 操作系统
- Xcode 和 Xcode Command Line Tools
- CocoaPods

### Windows 构建要求
- Windows 操作系统
- Visual Studio 2019 或更高版本 (包含 C++ 构建工具)
- Windows 10 SDK

### Android 构建要求
- Android SDK
- Android NDK
- Java JDK 8 或更高版本

### iOS 构建要求
- macOS 操作系统
- Xcode
- iOS SDK
- Apple Developer 账户 (用于代码签名)

## 输出目录结构

```
dist/
├── macos/
│   ├── AlistPlayer.app
│   └── AlistPlayer_1.0.0_macOS.dmg
├── windows/
│   ├── AlistPlayer/
│   └── AlistPlayer_1.0.0_Windows.zip
├── linux/
│   ├── AlistPlayer/
│   └── AlistPlayer_1.0.0_Linux.tar.gz
├── android/
│   └── AlistPlayer_1.0.0_Android.apk
└── web/
    ├── index.html
    ├── main.dart.js
    └── AlistPlayer_1.0.0_Web.zip
```

## 故障排除

### 常见问题

1. **Flutter 未找到**
   ```
   错误: Flutter 未安装或不在 PATH 中
   ```
   解决方案: 确保 Flutter SDK 已安装并添加到系统 PATH 中。

2. **构建失败**
   ```
   错误: 构建失败
   ```
   解决方案: 
   - 运行 `flutter doctor` 检查环境配置
   - 确保所有依赖已正确安装
   - 尝试使用 `--clean` 选项清理缓存

3. **权限问题 (macOS/Linux)**
   ```
   Permission denied
   ```
   解决方案: 给脚本添加执行权限
   ```bash
   chmod +x scripts/build_macos.sh scripts/build_all.sh
   ```

4. **DMG 创建失败 (macOS)**
   解决方案: 确保有足够的磁盘空间，并且没有其他进程占用相关文件。

5. **names_launcher 包错误**
   ```
   Could not find bin/main.dart in package names_launcher.
   ```
   解决方案: 这个错误已在脚本中修复。应用名称已在各平台配置文件中正确设置，无需使用 names_launcher 包。

### 调试技巧

1. **启用详细输出**
   在脚本中添加 `set -x` (bash) 或使用 `flutter build` 的 `--verbose` 选项。

2. **检查构建日志**
   查看 Flutter 构建过程中的详细日志信息。

3. **逐步构建**
   先尝试单独运行 `flutter build` 命令，确认基本构建流程正常。

## 自定义配置

### 修改应用名称
应用名称已在各平台配置文件中设置：
- **macOS**: `macos/Runner/Configs/AppInfo.xcconfig` 中的 `PRODUCT_NAME`
- **Windows**: `windows/runner/Runner.rc` 中的应用信息
- **Linux**: `linux/CMakeLists.txt` 中的 `BINARY_NAME`
- **Android**: `android/app/src/main/AndroidManifest.xml` 中的 `android:label`
- **iOS**: `ios/Runner/Info.plist` 中的 `CFBundleDisplayName`

### 修改应用图标
替换 `assets/icon/1024_logo.png` 文件，然后重新运行构建脚本。

### 修改版本号
编辑 `pubspec.yaml` 中的 `version` 字段。

## 注意事项

1. **代码签名**: iOS 和 macOS 应用可能需要代码签名才能在其他设备上运行。
2. **权限**: 某些平台的构建需要特定的开发者权限和证书。
3. **依赖**: 确保所有原生依赖都已正确配置。
4. **测试**: 建议在目标平台上测试构建的应用程序。

## 支持

如果遇到问题，请检查:
1. Flutter 官方文档
2. 项目的 `flutter doctor` 输出
3. 相关平台的构建要求
