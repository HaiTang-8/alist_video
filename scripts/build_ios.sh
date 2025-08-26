#!/bin/bash

# iOS 编译打包脚本
# 用法: ./scripts/build_ios.sh [--release|--debug] [--clean] [--simulator|--device]

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
TARGET_PLATFORM="device"
APP_NAME="AlistPlayer"
VERSION=$(grep "version:" pubspec.yaml | cut -d' ' -f2)

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
        --simulator)
            TARGET_PLATFORM="simulator"
            shift
            ;;
        --device)
            TARGET_PLATFORM="device"
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --release     构建发布版本 (默认)"
            echo "  --debug       构建调试版本"
            echo "  --clean       清理构建缓存"
            echo "  --simulator   构建模拟器版本"
            echo "  --device      构建真机版本 (默认)"
            echo "  -h, --help    显示帮助信息"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    iOS 编译打包脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}应用名称: ${APP_NAME}${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"
echo -e "${YELLOW}构建模式: ${BUILD_MODE}${NC}"
echo -e "${YELLOW}目标平台: ${TARGET_PLATFORM}${NC}"
echo -e "${YELLOW}清理构建: ${CLEAN_BUILD}${NC}"
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

# 检查是否在macOS上运行
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}错误: iOS 构建只能在 macOS 上运行${NC}"
    exit 1
fi

# 检查Xcode是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}错误: Xcode 未安装或不在 PATH 中${NC}"
    exit 1
fi

# 检查CocoaPods版本
if command -v pod &> /dev/null; then
    POD_VERSION=$(pod --version)
    echo -e "${YELLOW}当前CocoaPods版本: ${POD_VERSION}${NC}"

    # 检查是否需要更新CocoaPods
    REQUIRED_VERSION="1.16.2"
    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$POD_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]]; then
        echo -e "${GREEN}CocoaPods版本满足要求${NC}"
    else
        echo -e "${YELLOW}警告: 建议更新CocoaPods到${REQUIRED_VERSION}或更高版本${NC}"
        echo -e "${YELLOW}更新命令: sudo gem install cocoapods${NC}"
    fi
else
    echo -e "${RED}错误: CocoaPods 未安装${NC}"
    echo -e "${YELLOW}安装命令: sudo gem install cocoapods${NC}"
    exit 1
fi

# 清理构建缓存
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}正在清理构建缓存...${NC}"
    flutter clean
    rm -rf build/
    # 清理iOS构建缓存
    if [ -d "ios/build" ]; then
        rm -rf ios/build
    fi
    echo -e "${GREEN}构建缓存清理完成${NC}"
fi

# 获取依赖
echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

# 清理iOS Pods缓存（解决SDWebImage兼容性问题）
echo -e "${YELLOW}正在清理iOS Pods缓存...${NC}"
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
cd ..

# 重新安装Pods
echo -e "${YELLOW}正在重新安装Pods...${NC}"
cd ios
pod install --repo-update
cd ..

# 生成图标
echo -e "${YELLOW}正在生成应用图标...${NC}"
dart run flutter_launcher_icons:main

# 构建iOS应用
echo -e "${YELLOW}正在构建 iOS 应用...${NC}"
if [ "$TARGET_PLATFORM" = "simulator" ]; then
    if [ "$BUILD_MODE" = "release" ]; then
        flutter build ios --release --simulator
    else
        flutter build ios --debug --simulator
    fi
else
    if [ "$BUILD_MODE" = "release" ]; then
        flutter build ios --release --no-codesign
    else
        flutter build ios --debug --no-codesign
    fi
fi

# 创建输出目录
OUTPUT_DIR="dist/ios"
mkdir -p "$OUTPUT_DIR"

# 设置应用路径
if [ "$TARGET_PLATFORM" = "simulator" ]; then
    if [ "$BUILD_MODE" = "release" ]; then
        APP_PATH="build/ios/iphonesimulator/Runner.app"
    else
        APP_PATH="build/ios/iphonesimulator/Runner.app"
    fi
    OUTPUT_NAME="${APP_NAME}_${VERSION}_iOS_Simulator"
else
    if [ "$BUILD_MODE" = "release" ]; then
        APP_PATH="build/ios/iphoneos/Runner.app"
    else
        APP_PATH="build/ios/iphoneos/Runner.app"
    fi
    OUTPUT_NAME="${APP_NAME}_${VERSION}_iOS"
fi

if [ "$BUILD_MODE" = "debug" ]; then
    OUTPUT_NAME="${OUTPUT_NAME}_Debug"
fi

if [ -d "$APP_PATH" ]; then
    echo -e "${YELLOW}正在复制应用到输出目录...${NC}"
    
    # 复制.app文件
    APP_OUTPUT_PATH="$OUTPUT_DIR/${OUTPUT_NAME}.app"
    if [ -d "$APP_OUTPUT_PATH" ]; then
        rm -rf "$APP_OUTPUT_PATH"
    fi
    cp -R "$APP_PATH" "$APP_OUTPUT_PATH"
    
    # 创建IPA文件 (仅适用于真机版本)
    if [ "$TARGET_PLATFORM" = "device" ]; then
        echo -e "${YELLOW}正在创建 IPA 文件...${NC}"
        
        IPA_NAME="${OUTPUT_NAME}.ipa"
        IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
        
        # 创建Payload目录
        PAYLOAD_DIR="$OUTPUT_DIR/Payload"
        if [ -d "$PAYLOAD_DIR" ]; then
            rm -rf "$PAYLOAD_DIR"
        fi
        mkdir "$PAYLOAD_DIR"
        
        # 复制.app到Payload目录
        cp -R "$APP_OUTPUT_PATH" "$PAYLOAD_DIR/"
        
        # 创建IPA文件
        cd "$OUTPUT_DIR"
        zip -r "$IPA_NAME" Payload/
        cd - > /dev/null
        
        # 清理临时目录
        rm -rf "$PAYLOAD_DIR"
        
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}    构建完成!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}应用路径: $APP_OUTPUT_PATH${NC}"
        echo -e "${GREEN}IPA文件: $IPA_PATH${NC}"
        echo -e "${GREEN}IPA大小: $(du -h "$IPA_PATH" | cut -f1)${NC}"
    else
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}    构建完成!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}应用路径: $APP_OUTPUT_PATH${NC}"
        echo -e "${YELLOW}注意: 模拟器版本不生成IPA文件${NC}"
    fi
    
    echo ""
    
    # 显示文件信息
    echo -e "${BLUE}文件信息:${NC}"
    ls -la "$OUTPUT_DIR"
    
else
    echo -e "${RED}错误: 构建失败，找不到应用文件${NC}"
    exit 1
fi

echo -e "${GREEN}iOS 构建打包完成!${NC}"
