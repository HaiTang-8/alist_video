#!/bin/bash

# 跨平台编译打包脚本
# 用法: ./scripts/build_all.sh [--release|--debug] [--clean] [--platforms platform1,platform2,...]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
BUILD_MODE="release"
CLEAN_BUILD=false
APP_NAME="AlistPlayer"
VERSION=$(grep "version:" pubspec.yaml | cut -d' ' -f2)
PLATFORMS="macos,windows,linux"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --debug)
            BUILD_MODE="debug"
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --release              构建发布版本 (默认)"
            echo "  --debug                构建调试版本"
            echo "  --clean                清理构建缓存"
            echo "  --platforms PLATFORMS  指定构建平台，用逗号分隔 (默认: macos,windows,linux)"
            echo "                         可选平台: macos, windows, linux, android, ios, web"
            echo "  -h, --help             显示帮助信息"
            echo ""
            echo "示例:"
            echo "  $0 --release --platforms macos,windows"
            echo "  $0 --debug --clean"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    跨平台编译打包脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}应用名称: ${APP_NAME}${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"
echo -e "${YELLOW}构建模式: ${BUILD_MODE}${NC}"
echo -e "${YELLOW}清理构建: ${CLEAN_BUILD}${NC}"
echo -e "${YELLOW}构建平台: ${PLATFORMS}${NC}"
echo ""

# 检查是否在项目根目录
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
    exit 1
fi

# 检查Flutter是否安装
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}错误: Flutter 未安装或不在 PATH 中${NC}"
    exit 1
fi

# 清理构建缓存
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}正在清理构建缓存...${NC}"
    flutter clean
    rm -rf build/
    rm -rf dist/
    echo -e "${GREEN}构建缓存清理完成${NC}"
fi

# 获取依赖
echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

# 生成图标
echo -e "${YELLOW}正在生成应用图标...${NC}"
dart run flutter_launcher_icons:main

# 创建输出目录
mkdir -p dist

# 构建函数
build_platform() {
    local platform=$1
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}正在构建 ${platform} 平台${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    case $platform in
        "macos")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build macos --$BUILD_MODE
                
                # 创建输出目录
                OUTPUT_DIR="dist/macos"
                mkdir -p "$OUTPUT_DIR"
                
                # 复制应用
                APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
                if [ "$BUILD_MODE" = "debug" ]; then
                    APP_PATH="build/macos/Build/Products/Debug/${APP_NAME}.app"
                fi
                
                if [ -d "$APP_PATH" ]; then
                    cp -R "$APP_PATH" "$OUTPUT_DIR/"
                    
                    # 创建DMG
                    DMG_NAME="${APP_NAME}_${VERSION}_macOS.dmg"
                    DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
                    
                    if [ -f "$DMG_PATH" ]; then
                        rm "$DMG_PATH"
                    fi
                    
                    TEMP_DMG="$OUTPUT_DIR/temp.dmg"
                    hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" "$TEMP_DMG"
                    MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" | grep Volumes | awk '{print $3}')
                    cp -R "$OUTPUT_DIR/${APP_NAME}.app" "$MOUNT_DIR/"
                    ln -s /Applications "$MOUNT_DIR/Applications"
                    hdiutil detach "$MOUNT_DIR"
                    hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"
                    rm "$TEMP_DMG"
                    
                    echo -e "${GREEN}macOS 构建完成: $DMG_PATH${NC}"
                else
                    echo -e "${RED}macOS 构建失败${NC}"
                fi
            else
                echo -e "${YELLOW}跳过 macOS 构建 (需要在 macOS 上运行)${NC}"
            fi
            ;;
            
        "windows")
            flutter build windows --$BUILD_MODE
            
            OUTPUT_DIR="dist/windows"
            mkdir -p "$OUTPUT_DIR"
            
            APP_PATH="build/windows/x64/runner/Release"
            if [ "$BUILD_MODE" = "debug" ]; then
                APP_PATH="build/windows/x64/runner/Debug"
            fi
            
            if [ -d "$APP_PATH" ]; then
                APP_OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
                rm -rf "$APP_OUTPUT_DIR"
                cp -R "$APP_PATH" "$APP_OUTPUT_DIR"
                
                # 创建ZIP文件
                ZIP_NAME="${APP_NAME}_${VERSION}_Windows.zip"
                ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
                
                cd "$OUTPUT_DIR"
                zip -r "$ZIP_NAME" "$APP_NAME"
                cd - > /dev/null
                
                echo -e "${GREEN}Windows 构建完成: $ZIP_PATH${NC}"
            else
                echo -e "${RED}Windows 构建失败${NC}"
            fi
            ;;
            
        "linux")
            flutter build linux --$BUILD_MODE
            
            OUTPUT_DIR="dist/linux"
            mkdir -p "$OUTPUT_DIR"
            
            APP_PATH="build/linux/x64/release/bundle"
            if [ "$BUILD_MODE" = "debug" ]; then
                APP_PATH="build/linux/x64/debug/bundle"
            fi
            
            if [ -d "$APP_PATH" ]; then
                APP_OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
                rm -rf "$APP_OUTPUT_DIR"
                cp -R "$APP_PATH" "$APP_OUTPUT_DIR"
                
                # 创建tar.gz文件
                TAR_NAME="${APP_NAME}_${VERSION}_Linux.tar.gz"
                TAR_PATH="$OUTPUT_DIR/$TAR_NAME"
                
                cd "$OUTPUT_DIR"
                tar -czf "$TAR_NAME" "$APP_NAME"
                cd - > /dev/null
                
                echo -e "${GREEN}Linux 构建完成: $TAR_PATH${NC}"
            else
                echo -e "${RED}Linux 构建失败${NC}"
            fi
            ;;
            
        "android")
            flutter build apk --$BUILD_MODE
            
            OUTPUT_DIR="dist/android"
            mkdir -p "$OUTPUT_DIR"
            
            APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
            if [ "$BUILD_MODE" = "debug" ]; then
                APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
            fi
            
            if [ -f "$APK_PATH" ]; then
                APK_NAME="${APP_NAME}_${VERSION}_Android.apk"
                cp "$APK_PATH" "$OUTPUT_DIR/$APK_NAME"
                echo -e "${GREEN}Android 构建完成: $OUTPUT_DIR/$APK_NAME${NC}"
            else
                echo -e "${RED}Android 构建失败${NC}"
            fi
            ;;
            
        "ios")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                flutter build ios --$BUILD_MODE --no-codesign
                echo -e "${GREEN}iOS 构建完成 (需要在 Xcode 中进行代码签名和打包)${NC}"
            else
                echo -e "${YELLOW}跳过 iOS 构建 (需要在 macOS 上运行)${NC}"
            fi
            ;;
            
        "web")
            flutter build web --$BUILD_MODE
            
            OUTPUT_DIR="dist/web"
            mkdir -p "$OUTPUT_DIR"
            
            if [ -d "build/web" ]; then
                cp -R build/web/* "$OUTPUT_DIR/"
                
                # 创建ZIP文件
                ZIP_NAME="${APP_NAME}_${VERSION}_Web.zip"
                ZIP_PATH="dist/$ZIP_NAME"
                
                cd dist
                zip -r "$ZIP_NAME" web
                cd - > /dev/null
                
                echo -e "${GREEN}Web 构建完成: $ZIP_PATH${NC}"
            else
                echo -e "${RED}Web 构建失败${NC}"
            fi
            ;;
            
        *)
            echo -e "${RED}不支持的平台: $platform${NC}"
            ;;
    esac
}

# 构建指定平台
IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
for platform in "${PLATFORM_ARRAY[@]}"; do
    platform=$(echo "$platform" | xargs)  # 去除空格
    build_platform "$platform"
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    所有构建完成!${NC}"
echo -e "${BLUE}========================================${NC}"

# 显示输出目录内容
if [ -d "dist" ]; then
    echo -e "${GREEN}输出文件:${NC}"
    find dist -type f -name "*.dmg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.apk" | while read file; do
        size=$(du -h "$file" | cut -f1)
        echo -e "${GREEN}  $file (${size})${NC}"
    done
fi

echo -e "${GREEN}跨平台构建打包完成!${NC}"
