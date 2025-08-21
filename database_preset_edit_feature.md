# 数据库预设编辑功能

## 功能概述

为数据库设置添加了编辑已存在预设的功能，用户现在可以修改已保存的数据库配置预设。

## 新增功能

### 1. 编辑按钮
在预设列表中，每个非默认预设现在都有两个操作按钮：
- **编辑按钮**（蓝色）：用于编辑预设配置
- **删除按钮**（红色）：用于删除预设

### 2. 编辑对话框
点击编辑按钮后，会弹出编辑对话框，包含以下字段：
- 预设名称
- 主机地址
- 端口
- 数据库名称
- 用户名
- 密码（支持显示/隐藏切换）
- 描述（可选）

### 3. 数据验证
编辑时会进行以下验证：
- 端口号必须在 1-65535 范围内
- 预设名称不能与其他预设重复
- 所有必填字段不能为空

## 实现细节

### UI 组件更新
在 `lib/views/settings/database_preset_settings_dialog.dart` 中：

```dart
// 操作按钮
if (!preset.isDefault) ...[
  // 编辑按钮
  IconButton(
    onPressed: () => _editPreset(preset),
    icon: Icon(
      Icons.edit_outlined,
      color: Theme.of(context).colorScheme.primary,
      size: 20,
    ),
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  ),
  const SizedBox(width: 8),
  // 删除按钮
  IconButton(
    onPressed: () => _deletePreset(preset),
    icon: Icon(
      Icons.delete_outline,
      color: Theme.of(context).colorScheme.error,
      size: 20,
    ),
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  ),
],
```

### 编辑方法实现
新增 `_editPreset` 方法：
- 使用现有预设数据预填充表单
- 提供密码显示/隐藏功能
- 保持原有的ID和创建时间
- 进行重名检查（排除自己）

### 数据管理器更新
在 `lib/utils/database_config_manager.dart` 中更新了 `savePreset` 方法：
- 优先根据ID判断是否为更新操作
- 对于新增预设，检查名称重复
- 对于更新预设，直接替换

```dart
// 首先根据ID检查是否已存在（用于更新）
final existingIndexById = presets.indexWhere((p) => p.id == preset.id);
if (existingIndexById != -1) {
  // 更新现有配置
  presets[existingIndexById] = preset;
} else {
  // 检查是否已存在同名配置（用于新增时的重名检查）
  final existingIndexByName = presets.indexWhere((p) => p.name == preset.name);
  if (existingIndexByName != -1) {
    throw Exception('已存在同名的配置预设');
  }
  // 添加新配置
  presets.add(preset);
}
```

## 使用方法

1. **打开数据库设置**
   - 进入应用 → 个人页面 → 数据库设置

2. **选择预设标签页**
   - 在对话框中选择"预设配置"标签页

3. **编辑预设**
   - 找到要编辑的预设
   - 点击蓝色的编辑按钮
   - 在弹出的对话框中修改配置信息
   - 点击"保存"按钮

4. **验证更改**
   - 编辑成功后会显示绿色提示消息
   - 预设列表会自动刷新显示更新后的信息

## 功能特点

✅ **保持数据完整性**：编辑时保持原有的ID和创建时间  
✅ **重名检查**：防止创建重复名称的预设  
✅ **用户友好**：直观的编辑界面和清晰的反馈  
✅ **数据验证**：确保输入数据的有效性  
✅ **密码安全**：支持密码显示/隐藏切换  
✅ **实时更新**：编辑后立即刷新列表显示  

## 限制说明

- **默认预设不可编辑**：系统默认预设不显示编辑按钮
- **名称唯一性**：预设名称在所有预设中必须唯一
- **必填字段**：所有数据库连接相关字段都是必填的

## 错误处理

编辑过程中可能遇到的错误：
- 端口号无效：显示"请输入有效的端口号"
- 名称重复：显示"已存在同名的配置预设"
- 保存失败：显示具体的错误信息

所有错误都会通过 SnackBar 显示给用户，确保良好的用户体验。
