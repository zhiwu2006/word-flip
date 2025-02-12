# 单词学习卡片 (Word Learning Cards)

一个基于 Flutter 开发的现代化单词学习应用，帮助用户通过卡片翻转、语音朗读等交互方式高效地学习和记忆英语单词。

## 功能特点

- 精美的单词卡片展示
- 流畅的卡片翻转动画
- 支持文字转语音朗读
- 自动保存学习进度
- 支持自定义主题和字体
- 支持导入自定义单词文件
- 支持多个单词本切换
- 左右滑动切换单词
- 双击显示/隐藏中文含义
- 自动发音功能
- 显示学习进度
- 词组和例句展示
- 优雅的渐变背景
- 全屏沉浸式体验
- 优雅的页面切换动画
- 智能的状态保存和恢复
- 透明磨砂玻璃风格界面

## 技术栈

- Flutter
- Material Design 3
- flutter_tts（文字转语音）
- shared_preferences（数据持久化）
- google_fonts（字体支持）
- file_picker（文件选择）
- Google Fonts
- Flutter TTS
- Shared Preferences

## 项目结构

```
lib/
├── main.dart              # 主程序入口
├── models/               
    └── word_model.dart    # 单词数据模型
```

## 数据格式

单词数据存储在 JSON 文件中，格式如下：

```json
{
  "word": "example",
  "chinese_meaning": "例子；实例",
  "phrases": {
    "for example": "例如",
    "set an example": "树立榜样"
  },
  "example_sentences": [
    "This is an example.",
    "这是一个例子。"
  ]
}
```

单词数据也可以存储在 `assets` 目录下的 JSON 文件中，格式如下：

```json
[
  {
    "word": "英文单词",
    "chinese_meaning": "中文含义",
    "phrases": {
      "英文词组": "中文解释"
    },
    "example_sentences": [
      "英文例句",
      "中文翻译"
    ]
  }
]
```

## 使用说明

1. 启动应用后，将显示单词卡片界面
2. 点击卡片可以翻转查看单词释义和例句
3. 点击语音图标可以收听单词发音
4. 左右滑动可以切换不同的单词卡片
5. 学习进度会自动保存
6. 安装 Flutter 环境
7. 克隆仓库
8. 运行 `flutter pub get` 安装依赖
9. 运行 `flutter run` 启动应用

## 开发环境配置

1. 确保已安装 Flutter SDK
2. 克隆项目到本地
3. 运行以下命令安装依赖：
   ```bash
   flutter pub get
   ```
4. 运行项目：
   ```bash
   flutter run
   ```

## 待实现功能

- [ ] 单词复习计划
- [ ] 学习数据统计
- [ ] 单词收藏功能
- [ ] 搜索和筛选
- [ ] 在线词典集成
- [ ] 学习提醒功能
- [ ] 云端数据同步

## 最新更新 (v1.1.0)

- 全新的全屏沉浸式体验
- 优化的动画效果和转场
- 完整的状态保存机制
- 改进的界面设计
- 详细更新内容请查看 [CHANGELOG.md](CHANGELOG.md)

## 贡献指南

欢迎提交 Issue 和 Pull Request 来帮助改进这个项目。在提交之前，请确保：

1. 代码符合项目的编码规范
2. 新功能包含适当的测试
3. 所有测试都能通过
4. 更新相关文档

## 开源协议

本项目采用 MIT 协议开源，详见 [LICENSE](LICENSE) 文件。
