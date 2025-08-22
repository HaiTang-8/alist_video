@echo off
setlocal enabledelayedexpansion

REM Windows 编译打包脚本
REM 用法: scripts\build_windows.bat [release|debug] [clean]

REM 默认参数
set BUILD_MODE=release
set CLEAN_BUILD=false
set APP_NAME=AlistPlayer

REM 获取版本号
for /f "tokens=2" %%i in ('findstr "version:" pubspec.yaml') do set VERSION=%%i

REM 解析命令行参数
:parse_args
if "%~1"=="" goto start_build
if /i "%~1"=="release" (
    set BUILD_MODE=release
    shift
    goto parse_args
)
if /i "%~1"=="debug" (
    set BUILD_MODE=debug
    shift
    goto parse_args
)
if /i "%~1"=="clean" (
    set CLEAN_BUILD=true
    shift
    goto parse_args
)
if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
echo 未知参数: %~1
goto show_help

:show_help
echo 用法: %0 [选项]
echo 选项:
echo   release      构建发布版本 (默认)
echo   debug        构建调试版本
echo   clean        清理构建缓存
echo   -h, --help   显示帮助信息
exit /b 0

:start_build
echo ========================================
echo     Windows 编译打包脚本
echo ========================================
echo 应用名称: %APP_NAME%
echo 版本号: %VERSION%
echo 构建模式: %BUILD_MODE%
echo 清理构建: %CLEAN_BUILD%
echo.

REM 检查是否在项目根目录
if not exist "pubspec.yaml" (
    echo 错误: 请在项目根目录运行此脚本
    exit /b 1
)

REM 检查Flutter是否安装
flutter --version >nul 2>&1
if errorlevel 1 (
    echo 错误: Flutter 未安装或不在 PATH 中
    exit /b 1
)

REM 清理构建缓存
if /i "%CLEAN_BUILD%"=="true" (
    echo 正在清理构建缓存...
    flutter clean
    if exist build rmdir /s /q build
    echo 构建缓存清理完成
)

REM 获取依赖
echo 正在获取依赖...
flutter pub get
if errorlevel 1 (
    echo 错误: 获取依赖失败
    exit /b 1
)

REM 生成图标
echo 正在生成应用图标...
dart run flutter_launcher_icons:main

REM 构建Windows应用
echo 正在构建 Windows 应用...
if /i "%BUILD_MODE%"=="release" (
    flutter build windows --release
) else (
    flutter build windows --debug
)

if errorlevel 1 (
    echo 错误: 构建失败
    exit /b 1
)

REM 创建输出目录
set OUTPUT_DIR=dist\windows
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM 设置应用路径
set APP_PATH=build\windows\x64\runner\Release
if /i "%BUILD_MODE%"=="debug" (
    set APP_PATH=build\windows\x64\runner\Debug
)

if exist "%APP_PATH%" (
    echo 正在复制应用到输出目录...
    
    REM 创建应用目录
    set APP_OUTPUT_DIR=%OUTPUT_DIR%\%APP_NAME%
    if exist "!APP_OUTPUT_DIR!" rmdir /s /q "!APP_OUTPUT_DIR!"
    mkdir "!APP_OUTPUT_DIR!"
    
    REM 复制所有文件
    xcopy "%APP_PATH%\*" "!APP_OUTPUT_DIR!\" /E /I /H /Y
    
    REM 创建ZIP文件
    set ZIP_NAME=%APP_NAME%_%VERSION%_Windows.zip
    set ZIP_PATH=%OUTPUT_DIR%\!ZIP_NAME!
    
    echo 正在创建 ZIP 文件...
    
    REM 删除已存在的ZIP文件
    if exist "!ZIP_PATH!" del "!ZIP_PATH!"
    
    REM 使用PowerShell创建ZIP文件
    powershell -command "Compress-Archive -Path '!APP_OUTPUT_DIR!' -DestinationPath '!ZIP_PATH!' -Force"
    
    if exist "!ZIP_PATH!" (
        echo ========================================
        echo     构建完成!
        echo ========================================
        echo 应用目录: !APP_OUTPUT_DIR!
        echo ZIP文件: !ZIP_PATH!
        
        REM 显示文件大小
        for %%F in ("!ZIP_PATH!") do echo 文件大小: %%~zF 字节
        echo.
        
        REM 显示文件信息
        echo 文件信息:
        dir "%OUTPUT_DIR%" /B
        
    ) else (
        echo 错误: 创建ZIP文件失败
        exit /b 1
    )
    
) else (
    echo 错误: 构建失败，找不到应用文件
    exit /b 1
)

echo Windows 构建打包完成!
pause
