#!/bin/bash

# macOS 编译打包脚本
# 用法: ./scripts/build_macos.sh [--release|--debug] [--clean]

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
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --release    构建发布版本 (默认)"
            echo "  --debug      构建调试版本"
            echo "  --clean      清理构建缓存"
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
echo -e "${BLUE}    macOS 编译打包脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}应用名称: ${APP_NAME}${NC}"
echo -e "${YELLOW}版本号: ${VERSION}${NC}"
echo -e "${YELLOW}构建模式: ${BUILD_MODE}${NC}"
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
    echo -e "${RED}错误: 此脚本只能在 macOS 上运行${NC}"
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

# 图标生成需手动执行，避免脚本自动修改多端共用资源
echo -e "${YELLOW}跳过应用图标生成，请手动运行: dart run flutter_launcher_icons:main${NC}"

# 构建macOS应用
echo -e "${YELLOW}正在构建 macOS 应用...${NC}"
if [ "$BUILD_MODE" = "release" ]; then
    flutter build macos --release
else
    flutter build macos --debug
fi

# 创建输出目录
OUTPUT_DIR="dist/macos"
mkdir -p "$OUTPUT_DIR"

# 复制应用到输出目录
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
if [ "$BUILD_MODE" = "debug" ]; then
    APP_PATH="build/macos/Build/Products/Debug/${APP_NAME}.app"
fi

if [ -d "$APP_PATH" ]; then
    echo -e "${YELLOW}正在复制应用到输出目录...${NC}"
    # 删除已存在的应用
    if [ -d "$OUTPUT_DIR/${APP_NAME}.app" ]; then
        rm -rf "$OUTPUT_DIR/${APP_NAME}.app"
    fi
    cp -R "$APP_PATH" "$OUTPUT_DIR/"
    
    # 创建DMG文件
    DMG_NAME="${APP_NAME}_${VERSION}_macOS.dmg"
    DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
    
    echo -e "${YELLOW}正在创建 DMG 文件...${NC}"
    
    # 删除已存在的DMG文件
    if [ -f "$DMG_PATH" ]; then
        rm "$DMG_PATH"
    fi
    
    # 创建临时DMG
    TEMP_DMG="$OUTPUT_DIR/temp.dmg"
    hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" "$TEMP_DMG"
    
    # 挂载DMG
    MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" | grep Volumes | awk '{print $3}')
    
    # 复制应用到DMG
    cp -R "$OUTPUT_DIR/${APP_NAME}.app" "$MOUNT_DIR/"
    
    # 创建应用程序文件夹的符号链接
    ln -s /Applications "$MOUNT_DIR/Applications"
    
    # 卸载DMG
    hdiutil detach "$MOUNT_DIR"
    
    # 转换为压缩的DMG
    hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"
    
    # 删除临时文件
    rm "$TEMP_DMG"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    构建完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}应用路径: $OUTPUT_DIR/${APP_NAME}.app${NC}"
    echo -e "${GREEN}DMG文件: $DMG_PATH${NC}"
    echo -e "${GREEN}文件大小: $(du -h "$DMG_PATH" | cut -f1)${NC}"
    echo ""
    
    # 显示文件信息
    echo -e "${BLUE}文件信息:${NC}"
    ls -la "$OUTPUT_DIR"
    
else
    echo -e "${RED}错误: 构建失败，找不到应用文件${NC}"
    exit 1
fi

echo -e "${GREEN}macOS 构建打包完成!${NC}"
