# Dext - 花里胡哨的问卷调查

<p align="center">
  <img src="assets/images/Dext.png" alt="Dext Logo" width="120" height="120">
</p>

<p align="center">
  <a href='https://github.com/chuishui233/dext'><img alt="Github stars" src="https://img.shields.io/github/stars/chuishui233/dext?logo=github"></a>
  <a href='https://github.com/chuishui233/dext'><img alt="Github forks" src="https://img.shields.io/github/forks/chuishui233/dext?logo=github"></a>
  <a href='https://github.com/chuishui233/dext/releases'><img alt="Github releases" src="https://img.shields.io/github/v/release/chuishui233/dext?logo=github"></a>
  <a href='https://flutter.dev'><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.35.0+-blue?logo=flutter"></a>
</p>

## 项目简介

**Dext** 是一款基于 Flutter 的跨平台开源问卷 / 调研工具，主打 **「花里胡哨但好用」** 的编辑和填写体验。  
它提供从「问卷设计 → 发布分享 → 填写收集 → 结果分析导出」的一整套流程，适合个人、小团队甚至中小企业自建问卷系统使用。

### 功能一览

- **问卷编辑器**
  - 支持单选、多选、填空、评分、排序等常见题型
  - 支持题目分组、必答设置、校验规则等
  - 拖拽式编辑、所见即所得
- **分享与访问**
  - 生成公开访问链接，一键分享
  - 支持多端访问
- **结果统计与分析**
  - 填写数据实时统计
  - 支持图表展示
  - 支持导出为 Excel 等格式
- **安全与隐私**
  - 使用 RSA、对称加密等方案保护敏感数据
  - 支持安全本地存储
- **剪切板 + 深度链接**
  - 智能检测剪切板里的问卷链接并提示打开
  - 支持 App Links / 深度链接唤起应用
- **UI 与交互**
  - 使用 `forui` 等组件库构建现代化 UI
  - 支持多平台窗口管理、托盘图标、单实例等桌面增强能力

## 仓库地址

<a href='https://github.com/chuishui233/dext'><img alt="Github" src="https://img.shields.io/badge/GitHub-Dext-blue?logo=github"></a>

## 项目截图

### 桌面端界面

<p align="center">
  <img src=".preview/image_1.png" alt="登录界面" width="200"/>
  <img src=".preview/image_2.png" alt="主界面" width="200"/>
  <img src=".preview/image_3.png" alt="问卷创建" width="200"/>
  <img src=".preview/image_4.png" alt="问卷预览" width="200"/>
  <img src=".preview/image_5.png" alt="数据分析" width="200"/>
</p>

### 移动端界面

<p align="center">
  <img src=".preview/m_image_1.jpg" alt="移动端登录" width="200"/>
  <img src=".preview/m_image_2.jpg" alt="移动端主页" width="200"/>
  <img src=".preview/m_image_3.jpg" alt="移动端问卷" width="200"/>
</p>

<p align="center">
  <img src=".preview/m_image_4.jpg" alt="移动端填写" width="200"/>
  <img src=".preview/m_image_5.jpg" alt="移动端结果" width="200"/>
  <img src=".preview/m_image_6.jpg" alt="移动端分析" width="200"/>
</p>

### Web端界面

<p align="center">
  <img src=".preview/image_WEB.png" alt="Web端展示" width="800"/>
</p>


## 支持平台

| 平台                           | 支持状态
|------------------------------- | ---------------------------
| Android                        |  ✅
| iOS                            |  ✅
| Windows                        |  ✅
| Web                            |  ✅
| macOS                          |  ？
| Linux                          |  ？

>？ 为未测试编译运行

## 项目结构

```
lib/
├── main.dart                    -- 应用入口
├── components/                  -- 通用组件
│   ├── glass_card.dart         -- 玻璃拟态卡片
│   ├── media_gallery.dart      -- 媒体画廊
│   └── multi_select_actions.dart -- 多选操作
├── controllers/                 -- 控制器
│   └── survey_runtime.dart     -- 问卷运行时控制
├── models/                      -- 数据模型
│   ├── captcha.dart            -- 验证码模型
│   ├── home_state.dart         -- 首页状态
│   ├── project.dart            -- 项目模型
│   ├── survey.dart             -- 问卷模型
│   └── user.dart               -- 用户模型
├── pages/                       -- 页面
│   ├── create_survey_page.dart -- 创建问卷页面
│   ├── edit_question_page.dart -- 编辑题目页面
│   ├── survey_preview_page.dart -- 问卷预览页面
│   ├── survey_results_page.dart -- 问卷结果页面
│   ├── public_access_page.dart -- 公开访问页面
│   └── submission_detail_page.dart -- 提交详情页面
├── services/                    -- 服务层
│   ├── api_service.dart        -- API服务
│   ├── auth_service.dart       -- 认证服务
│   ├── crypto_service.dart     -- 加密服务
│   ├── clipboard_service.dart  -- 剪切板服务
│   └── url_handler.dart        -- URL处理服务
├── utils/                       -- 工具类
│   ├── constants.dart          -- 常量定义
│   ├── helpers.dart            -- 辅助函数
│   └── validators.dart         -- 验证器
└── widgets/                     -- 自定义组件
    ├── question_display_widget.dart -- 题目显示组件
    └── survey_form_widget.dart -- 问卷表单组件
```

## 技术栈

### 开发环境
|                                | 版本
|------------------------------- | ---------------------------
| Flutter SDK                    |  3.35.0+
| Dart SDK                       |  3.9+

### 核心依赖（功能相关）
|                                | 版本              | 用途
|------------------------------- | ----------------- | ---------------------------|
| forui                          |  ^0.16.0          | UI 组件库 / 交互控件       |
| layout                         |  ^1.0.5           | 响应式布局                 |
| provider                       |  ^6.1.5+1         | 状态管理                   |
| http                           |  ^1.1.0           | 基础 HTTP 请求            |
| dio                            |  ^5.9.0           | 高级 HTTP 客户端 / 拦截器 |
| shared_preferences             |  ^2.5.3           | 轻量本地 KV 存储          |
| flutter_secure_storage         |  ^10.0.0-beta.4   | 安全存储（如 Token 等）   |
| path_provider                  |  ^2.1.1           | 本地路径访问               |
| file_picker                    |  ^10.1.9          | 文件选择                   |
| image_picker                   |  ^1.0.4           | 图片选择                   |
| video_player                   |  ^2.10.0          | 视频播放                   |
| video_player_win               |  ^3.2.0           | Windows 平台视频支持       |
| radio_player                   |  ^2.1.0           | 音频播放                   |
| cached_network_image           |  ^3.4.1           | 网络图片缓存               |
| pull_to_refresh                |  ^2.0.0           | 下拉刷新                   |
| flutter_staggered_grid_view    |  ^0.7.0           | 瀑布流布局                 |
| syncfusion_flutter_xlsio       |  ^31.1.19         | 导出 Excel 报表            |
| fl_chart                       |  0.71.0           | 图表展示                   |
| app_links                      |  ^3.5.0           | 深度链接 / 唤起应用        |
| url_launcher                   |  ^6.2.5           | 打开浏览器、外部应用       |
| clipboard_watcher              |  ^0.2.0           | 剪切板内容监听             |
| window_manager                 |  ^0.5.1           | 多平台窗口管理             |
| tray_manager                   |  ^0.5.2           | 系统托盘                   |
| desktop_drop                   |  ^0.6.1           | 桌面拖拽文件               |
| windows_single_instance        |  ^1.0.1           | 单实例应用                 |
| package_info_plus              |  ^8.0.0           | 应用版本信息               |
| shimmer                        |  ^3.0.0           | 骨架屏 / 加载动画          |
| photo_view                     |  ^0.15.0          | 图片预览与缩放             |
| flutter_speed_dial             |  ^7.0.0           | 悬浮菜单按钮               |
| connectivity_plus              |  ^7.0.0           | 网络状态监测               |
| oauth2_client                  |  ^4.2.0           | OAuth2 客户端              |
| crop_image_plus                |  git              | 图片裁剪                   |
| getuiflut                      |  git              | 个推推送 SDK               |
| image                          |  ^4.2.0           | 本地图片处理               |
| http_parser                    |  ^4.1.2           | HTTP 工具与解析            |
| cupertino_icons                |  ^1.0.2           | iOS 风格图标               |

### 安全与加密
|                                | 版本              | 用途
|------------------------------- | ----------------- | ---------------------------|
| pointycastle                   |  ^4.0.0           | 加密算法实现               |
| fast_rsa                       |  ^3.8.5           | RSA 加解密                 |
| crypto                         |  ^3.0.6           | 常用散列 / HMAC 等        |
| cryptography                   |  ^2.5.0           | 现代加密算法封装           |
| basic_utils                    |  ^5.8.2           | 证书处理等基础工具         |


## 快速开始

### 环境要求

- Flutter SDK 3.35.0 或更高版本（最低支持版本）
- Dart SDK 3.9 或更高版本（最低支持版本）
- Android Studio / VS Code
- Git

### 安装步骤

1. **克隆项目**
```bash
git clone https://github.com/chuishui233/dext.git
cd dext
```

2. **安装依赖**
```bash
flutter pub get
```

3. **生成图标**
```bash
flutter pub run flutter_launcher_icons:main
```

4. **运行应用**
```bash
# 调试模式
flutter run

# 发布模式
flutter run --release
```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release

# Web
flutter build web --release
```

## 功能特性

### 问卷管理
- 创建、编辑、删除问卷
- 支持多种题型：单选、多选、填空、评分、排序等
- 问卷模板和主题自定义
- 问卷发布和分享

### 数据分析
- 实时数据统计
- 可视化图表展示
- 数据导出功能
- 详细的提交记录

## 贡献指南

欢迎提交 Issue 和 Pull Request 来帮助改进项目。

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 开源协议

本项目采用 MPL2.0 协议 - 查看 [LICENSE](LICENSE.txt) 文件了解详情。

## 免责声明

1. 本项目提供的源代码仅供学习和研究使用，请勿用于商业盈利。

2. 用户使用本系统从事任何违法违规的事情，一切后果由用户自行承担，作者不承担任何法律责任。

3. 如有侵犯权利，请联系作者删除。

4. 下载或使用本项目源码则代表您同意上述免责声明协议。

## 联系方式

- 项目地址：[https://github.com/chuishui233/dext](https://github.com/chuishui233/dext)
- 问题反馈：[Issues](https://github.com/chuishui233/dext/issues)

---

⭐ 如果这个项目对您有帮助或者很有意思，请给它一个星标，非常感谢！
