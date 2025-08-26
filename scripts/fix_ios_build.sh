#!/bin/bash

# iOS构建问题修复脚本
# 用法: ./scripts/fix_ios_build.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    iOS构建问题修复脚本${NC}"
echo -e "${BLUE}========================================${NC}"

# 检查是否在项目根目录
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
    exit 1
fi

# 检查是否在macOS上运行
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}错误: iOS 构建只能在 macOS 上运行${NC}"
    exit 1
fi

echo -e "${YELLOW}1. 检查CocoaPods版本...${NC}"
if command -v pod &> /dev/null; then
    POD_VERSION=$(pod --version)
    echo -e "${YELLOW}当前CocoaPods版本: ${POD_VERSION}${NC}"
    
    # 检查是否需要更新CocoaPods
    REQUIRED_VERSION="1.16.2"
    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$POD_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]]; then
        echo -e "${GREEN}CocoaPods版本满足要求${NC}"
    else
        echo -e "${YELLOW}正在更新CocoaPods...${NC}"
        sudo gem install cocoapods
        echo -e "${GREEN}CocoaPods更新完成${NC}"
    fi
else
    echo -e "${YELLOW}正在安装CocoaPods...${NC}"
    sudo gem install cocoapods
    echo -e "${GREEN}CocoaPods安装完成${NC}"
fi

echo -e "${YELLOW}2. 清理Flutter缓存...${NC}"
flutter clean

echo -e "${YELLOW}3. 清理iOS构建缓存...${NC}"
rm -rf build/
if [ -d "ios/build" ]; then
    rm -rf ios/build
fi

echo -e "${YELLOW}4. 清理Pods缓存...${NC}"
cd ios
rm -rf Pods
rm -rf Podfile.lock
rm -rf .symlinks
rm -rf ~/Library/Caches/CocoaPods
cd ..

echo -e "${YELLOW}5. 更新Podfile以修复SDWebImage兼容性问题...${NC}"

# 备份原始Podfile
cp ios/Podfile ios/Podfile.backup

# 创建新的Podfile内容
cat > ios/Podfile << 'EOF'
# Uncomment this line to define a global platform for your project
platform :ios, '12.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    # 修复SDWebImage兼容性问题
    if target.name == 'SDWebImage'
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
        # 禁用有问题的编译器警告
        config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
        config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
      end
    end
    
    # 确保所有target的最低部署版本
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 12.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      end
    end
  end
end
EOF

echo -e "${GREEN}Podfile已更新${NC}"

echo -e "${YELLOW}6. 获取Flutter依赖...${NC}"
flutter pub get

echo -e "${YELLOW}7. 重新安装Pods...${NC}"
cd ios
pod deintegrate || true
pod setup
pod install --repo-update --verbose
cd ..

echo -e "${YELLOW}8. 生成应用图标...${NC}"
dart run flutter_launcher_icons:main

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    iOS构建问题修复完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}现在可以尝试重新构建iOS应用:${NC}"
echo -e "${GREEN}  ./scripts/build_ios.sh${NC}"
echo ""
echo -e "${YELLOW}如果仍有问题，请尝试:${NC}"
echo -e "${YELLOW}1. 在Xcode中打开ios/Runner.xcworkspace${NC}"
echo -e "${YELLOW}2. 清理构建文件夹 (Product -> Clean Build Folder)${NC}"
echo -e "${YELLOW}3. 重新构建项目${NC}"
