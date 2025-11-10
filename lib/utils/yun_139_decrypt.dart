import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:alist_player/utils/logger.dart';

/// 统一的日志方法，确保 139Yun 加解密示例信息被纳入 AppLogger
void _logCrypto(
  String message, {
  LogLevel level = LogLevel.info,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger().captureConsoleOutput(
    'Yun139Crypto',
    message,
    level: level,
    error: error,
    stackTrace: stackTrace,
  );
}

/// 139Yun 加解密工具
/// 将 JavaScript 版本的加解密逻辑转换为 Dart
/// 支持加密和解密操作
class Yun139Crypto {
  /// 定义密钥 D
  static final List<int> _keyWords = [
    1347831620, // 1347831620
    2003657590, // 2003657590
    1718825333, // 1718825333
    1446208561, // 1446208561
  ];

  /// 将 32 位整数转换为 4 个字节
  static List<int> _wordToBytes(int word) {
    return [
      (word >> 24) & 0xFF,
      (word >> 16) & 0xFF,
      (word >> 8) & 0xFF,
      word & 0xFF,
    ];
  }

  /// 将密钥 words 转换为字节数组
  static List<int> get _keyBytes {
    List<int> bytes = [];
    for (int word in _keyWords) {
      bytes.addAll(_wordToBytes(word));
    }
    return bytes;
  }

  /// 加密字符串
  /// 生成随机 IV，并将 IV + 密文以 Base64 编码形式返回
  ///
  /// @param plainText - 待加密的明文字符串
  /// @returns 加密后的 Base64 字符串 (IV + 密文)
  static String encrypt(String plainText) {
    try {
      // 1. 创建 AES 密钥
      final key = Key(Uint8List.fromList(_keyBytes));

      // 2. 生成随机 IV (16 字节)
      final iv = IV.fromSecureRandom(16);

      // 3. 创建 AES 加密器 (CBC 模式, PKCS7 填充)
      final encrypter = Encrypter(
        AES(key, mode: AESMode.cbc, padding: 'PKCS7'),
      );

      // 4. 加密
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // 5. 拼接 IV 和密文，并进行 Base64 编码
      List<int> combinedBytes = [];
      combinedBytes.addAll(iv.bytes);
      combinedBytes.addAll(encrypted.bytes);

      return base64.encode(combinedBytes);
    } catch (e) {
      throw Exception('加密失败: $e');
    }
  }

  /// 根据原函数 j(e) 的逻辑解密 Base64 字符串
  /// 输入的 Base64 字符串需要是 IV (16 bytes) + Ciphertext 的拼接
  ///
  /// @param encryptedBase64 - 待解密的 Base64 字符串
  /// @returns 解密后的明文字符串
  static String decrypt(String encryptedBase64) {
    try {
      // 1. 将输入的 Base64 字符串解码为字节数组
      List<int> allBytes = base64.decode(encryptedBase64);

      // 2. 从字节数组中提取 IV (前 16 字节)
      List<int> ivBytes = allBytes.sublist(0, 16);

      // 3. 从字节数组中提取密文部分 (从第 16 字节开始)
      List<int> ciphertextBytes = allBytes.sublist(16);

      // 4. 创建 AES 密钥
      final key = Key(Uint8List.fromList(_keyBytes));

      // 5. 创建 IV
      final iv = IV(Uint8List.fromList(ivBytes));

      // 6. 创建 AES 加密器 (CBC 模式, PKCS7 填充)
      final encrypter = Encrypter(
        AES(key, mode: AESMode.cbc, padding: 'PKCS7'),
      );

      // 7. 解密
      final decrypted = encrypter.decrypt(
        Encrypted(Uint8List.fromList(ciphertextBytes)),
        iv: iv,
      );

      return decrypted;
    } catch (e) {
      throw Exception('解密失败: $e');
    }
  }

  /// 使用示例
  static void example() {
    // 原始文本
    const originalText =
        '{"getOutLinkInfoReq":{"account":"","linkID":"2nc6qeAi4Ldqc","passwd":"","caSrt":0,"coSrt":0,"srtDr":1,"bNum":1,"pCaID":"DFxcHJuuAEwA1611n9kDV5nd05620231211111605jef/Fg0EpY3OPm5KzIL2A-CFEC5RWLkWYD4iS","eNum":200}}';
    _logCrypto("原始文本: $originalText");

    // 加密
    try {
      final encryptedBase64 = encrypt(originalText);
      _logCrypto("加密结果 (Base64): $encryptedBase64");

      // 解密
      final decryptedText = decrypt(encryptedBase64);
      _logCrypto("解密结果: $decryptedText");

      // 验证
      _logCrypto(
        "验证结果: ${originalText == decryptedText ? '成功' : '失败'}",
      );
    } catch (e, stack) {
      _logCrypto("操作失败: $e",
          level: LogLevel.error, error: e, stackTrace: stack);
    }

    // 解密示例 (使用已有的加密字符串)
    const encryptedBase64String =
        "KreNxDepdMknQBGmKKc38oCTYz2b6mPhGtdLwcMGLoeqQqDK2KnkVtW1fP/9gin+Jgaw0BT7XKQ3viLbcqiHe5FjGLDsNyriGz8cwRNcYeja/DLjtJe+xF4OZGGdJH0I5Byk+3cBTOzmtNFC1WxuGr6iCa0tT38SbP2ZRxXLxid4pTZqunvcMGiFEnyYsiReMBqzkDjsjHKqkIkcNL4+x3AXK6Q5XgBaHcHvtnhA6YMg8D53pfn9AbjAmwxrdz0vbaSiarZnRzHv6K3o7wKDSjrbb7U/yBKLg9IXEBxrK0KvZZDlabQeREKOtaCmaCrK";

    try {
      final decryptedString = decrypt(encryptedBase64String);
      _logCrypto("解密已有字符串结果: $decryptedString");
    } catch (e, stack) {
      _logCrypto("解密失败: $e",
          level: LogLevel.error, error: e, stackTrace: stack);
      _logCrypto("请确保输入的 Base64 字符串正确且包含 IV 和密文。");
    }
  }
}

void main() {
  // 运行加解密示例
  Yun139Crypto.example();
}
