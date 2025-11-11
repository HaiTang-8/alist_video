#!/bin/bash

# 快速构建脚本 - 自动检测平台并构建
# 用法: ./scripts/quick_build.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="AlistPlayer"
VERSION=$(grep "version:" pubspec.yaml | cut -d' ' -f2)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    快速构建脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}应用名称: ${APP_NAME}${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"

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

# 自动检测操作系统
OS_TYPE=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macOS"
    PLATFORM="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS_TYPE="Windows"
    PLATFORM="windows"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="Linux"
    PLATFORM="linux"
else
    echo -e "${RED}错误: 不支持的操作系统: $OSTYPE${NC}"
    exit 1
fi

echo -e "${YELLOW}检测到操作系统: ${OS_TYPE}${NC}"
echo -e "${YELLOW}将构建平台: ${PLATFORM}${NC}"
echo ""

# 获取依赖
echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

# 图标生成需手动执行，脚本仅提示用户自行处理
echo -e "${YELLOW}跳过应用图标生成，请手动运行: dart run flutter_launcher_icons:main${NC}"

# 根据平台构建
case $PLATFORM in
    "macos")
        echo -e "${YELLOW}正在构建 macOS 应用...${NC}"
        flutter build macos --release
        
        OUTPUT_DIR="dist/macos"
        mkdir -p "$OUTPUT_DIR"
        
        APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
        if [ -d "$APP_PATH" ]; then
            # 删除已存在的应用
            if [ -d "$OUTPUT_DIR/${APP_NAME}.app" ]; then
                rm -rf "$OUTPUT_DIR/${APP_NAME}.app"
            fi
            cp -R "$APP_PATH" "$OUTPUT_DIR/"
            echo -e "${GREEN}macOS 应用构建完成: $OUTPUT_DIR/${APP_NAME}.app${NC}"
        else
            echo -e "${RED}macOS 构建失败${NC}"
            exit 1
        fi
        ;;
        
    "windows")
        echo -e "${YELLOW}正在构建 Windows 应用...${NC}"
        flutter build windows --release
        
        OUTPUT_DIR="dist/windows"
        mkdir -p "$OUTPUT_DIR"
        
        APP_PATH="build/windows/x64/runner/Release"
        if [ -d "$APP_PATH" ]; then
            APP_OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
            rm -rf "$APP_OUTPUT_DIR"
            cp -R "$APP_PATH" "$APP_OUTPUT_DIR"
            echo -e "${GREEN}Windows 应用构建完成: $APP_OUTPUT_DIR${NC}"
        else
            echo -e "${RED}Windows 构建失败${NC}"
            exit 1
        fi
        ;;
        
    "linux")
        echo -e "${YELLOW}正在构建 Linux 应用...${NC}"
        flutter build linux --release
        
        OUTPUT_DIR="dist/linux"
        mkdir -p "$OUTPUT_DIR"
        
        APP_PATH="build/linux/x64/release/bundle"
        if [ -d "$APP_PATH" ]; then
            APP_OUTPUT_DIR="$OUTPUT_DIR/$APP_NAME"
            rm -rf "$APP_OUTPUT_DIR"
            cp -R "$APP_PATH" "$APP_OUTPUT_DIR"
            echo -e "${GREEN}Linux 应用构建完成: $APP_OUTPUT_DIR${NC}"
        else
            echo -e "${RED}Linux 构建失败${NC}"
            exit 1
        fi
        ;;
esac

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    构建完成!${NC}"
echo -e "${GREEN}========================================${NC}"

# 显示输出目录内容
if [ -d "dist" ]; then
    echo -e "${GREEN}输出文件:${NC}"
    find dist -type d -name "$APP_NAME" | while read dir; do
        size=$(du -sh "$dir" | cut -f1)
        echo -e "${GREEN}  $dir (${size})${NC}"
    done
fi

echo -e "${GREEN}快速构建完成!${NC}"
