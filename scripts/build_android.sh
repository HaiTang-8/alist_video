#!/bin/bash

# Android 编译打包脚本
# 用法: ./scripts/build_android.sh [--release|--debug] [--clean] [--apk|--aab]

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
BUILD_TYPE="apk"
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
        --apk)
            BUILD_TYPE="apk"
            shift
            ;;
        --aab)
            BUILD_TYPE="aab"
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --release    构建发布版本 (默认)"
            echo "  --debug      构建调试版本"
            echo "  --clean      清理构建缓存"
            echo "  --apk        构建APK文件 (默认)"
            echo "  --aab        构建AAB文件 (用于Google Play)"
            echo "  -h, --help   显示帮助信息"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Android 编译打包脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}应用名称: ${APP_NAME}${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"
echo -e "${YELLOW}构建模式: ${BUILD_MODE}${NC}"
echo -e "${YELLOW}构建类型: ${BUILD_TYPE}${NC}"
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

# 检查Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    echo -e "${RED}错误: 未设置 ANDROID_HOME 或 ANDROID_SDK_ROOT 环境变量${NC}"
    exit 1
fi

# 清理构建缓存
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}正在清理构建缓存...${NC}"
    flutter clean
    rm -rf build/
    echo -e "${GREEN}构建缓存清理完成${NC}"
fi

# 获取依赖
echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

# 为release构建准备额外的Dart编译参数，通过拆分调试符号与树摇图标压缩包体
BUILD_FLAGS=()
if [ "$BUILD_MODE" = "release" ]; then
    DEBUG_INFO_DIR="dist/debug/android"
    mkdir -p "$DEBUG_INFO_DIR"
    BUILD_FLAGS+=("--split-debug-info=$DEBUG_INFO_DIR" "--obfuscate" "--tree-shake-icons")
fi

# 图标生成需手动执行，避免脚本自动更新多端图标资源
echo -e "${YELLOW}跳过应用图标生成，请手动运行: dart run flutter_launcher_icons:main${NC}"

# 构建Android应用
echo -e "${YELLOW}正在构建 Android 应用...${NC}"
if [ "$BUILD_TYPE" = "aab" ]; then
    if [ "$BUILD_MODE" = "release" ]; then
        flutter build appbundle --release "${BUILD_FLAGS[@]}"
    else
        flutter build appbundle --debug
    fi
else
    if [ "$BUILD_MODE" = "release" ]; then
        flutter build apk --release --split-per-abi "${BUILD_FLAGS[@]}"
    else
        flutter build apk --debug
    fi
fi

# 创建输出目录
OUTPUT_DIR="dist/android"
mkdir -p "$OUTPUT_DIR"

# 记录所有需要输出的产物路径，便于统一展示
OUTPUT_PATHS=()

if [ "$BUILD_TYPE" = "apk" ] && [ "$BUILD_MODE" = "release" ]; then
    # 分ABI复制APK，确保用户仅下载所需架构的最小包
    ABI_LIST=("armeabi-v7a" "arm64-v8a" "x86_64")
    for abi in "${ABI_LIST[@]}"; do
        SOURCE_FILE="build/app/outputs/flutter-apk/app-${abi}-release.apk"
        if [ -f "$SOURCE_FILE" ]; then
            OUTPUT_FILE="${APP_NAME}_${VERSION}_android_${abi}.apk"
            OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"
            cp "$SOURCE_FILE" "$OUTPUT_PATH"
            OUTPUT_PATHS+=("$OUTPUT_PATH")
        else
            echo -e "${YELLOW}提示: 未找到 ${abi} 架构的APK，可能该平台未启用${NC}"
        fi
    done
else
    # 非分ABI场景仍保持单文件输出
    if [ "$BUILD_TYPE" = "aab" ]; then
        if [ "$BUILD_MODE" = "release" ]; then
            SOURCE_FILE="build/app/outputs/bundle/release/app-release.aab"
            OUTPUT_FILE="${APP_NAME}_${VERSION}_android.aab"
        else
            SOURCE_FILE="build/app/outputs/bundle/debug/app-debug.aab"
            OUTPUT_FILE="${APP_NAME}_${VERSION}_android_debug.aab"
        fi
    else
        if [ "$BUILD_MODE" = "release" ]; then
            SOURCE_FILE="build/app/outputs/flutter-apk/app-release.apk"
            OUTPUT_FILE="${APP_NAME}_${VERSION}_android.apk"
        else
            SOURCE_FILE="build/app/outputs/flutter-apk/app-debug.apk"
            OUTPUT_FILE="${APP_NAME}_${VERSION}_android_debug.apk"
        fi
    fi

    OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"
    if [ -f "$SOURCE_FILE" ]; then
        cp "$SOURCE_FILE" "$OUTPUT_PATH"
        OUTPUT_PATHS+=("$OUTPUT_PATH")
    fi
fi

if [ ${#OUTPUT_PATHS[@]} -eq 0 ]; then
    echo -e "${RED}错误: 构建失败，未找到任何输出文件${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    构建完成!${NC}"
echo -e "${GREEN}========================================${NC}"
for path in "${OUTPUT_PATHS[@]}"; do
    echo -e "${GREEN}输出文件: $path${NC}"
    echo -e "${GREEN}文件大小: $(du -h "$path" | cut -f1)${NC}"
done
echo ""

# 显示输出目录下的产物列表
echo -e "${BLUE}文件信息:${NC}"
ls -la "$OUTPUT_DIR"

# 如果是APK且本地有aapt，则输出每个APK的包信息
if [ "$BUILD_TYPE" = "apk" ] && command -v aapt &> /dev/null; then
    for path in "${OUTPUT_PATHS[@]}"; do
        echo ""
        echo -e "${BLUE}APK 信息 (${path}):${NC}"
        aapt dump badging "$path" | grep -E "(package|application-label|versionCode|versionName)"
    done
fi

echo -e "${GREEN}Android 构建打包完成!${NC}"
