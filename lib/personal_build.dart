/// 私人构建（Yuri 版）的标识与开关。
///
/// 与上游无关的定制集中在这里，合并上游时只需处理本文件与少数引用点，
/// 避免每次同步都在业务代码里解冲突。
///
/// 对应 Windows 侧的同类常量在 `windows/runner/main.cpp` 与
/// `windows/runner/Runner.rc`，两边改名时需一起改。
library;

/// 是否私人构建。个人分支恒为 true；cherry-pick 回上游时应为 false。
const bool kPersonalBuild = true;

/// 显示名，用于窗口标题、关于页等处。
const String kPersonalName = 'Baka Yuri';

/// 桌面数据目录名，位于「文档」下。官方的 `baka` 保持不动，两边互不覆盖。
const String kPersonalDataFolder = 'baka-yuri';

/// 私人构建是否仍检查官方更新。false 表示跳过 version.anibaka.com。
const bool kPersonalCheckOfficialUpdate = false;
