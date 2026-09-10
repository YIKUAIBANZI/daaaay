# daaaay for Mac

daaaay 的 macOS 客户端使用 SwiftUI 与 AppKit，提供完整日程窗口、菜单栏入口和 340×340 悬浮计时窗。客户端继续连接既有回环 HTTP 服务；它不会建立第二份数据库，也不会扩大网站限制或采集屏幕、键盘和浏览历史。

## 界面与操作

第一版固定使用浅色“日光工作台”：柔和白色画布、白色内容表面、蓝色主操作、青色进行中标记，以及只在今天显示的日光轨道。系统切到深色模式时，应用仍保持这套浅色外观。

主窗口默认是月历与分类、日程列表、当前事项与进度三栏。窗口宽度小于 1120 pt 时，左栏收进工具栏按钮，当前事项与进度移到日程上方；最小窗口为 1020×680 pt。

| 操作 | 入口 |
| --- | --- |
| 显示或隐藏悬浮窗 | Control + Option + Space |
| 呼出完整日程 | Control + Option + D |
| 应用内打开日程或切换小窗 | Command + 1 / Command + 2 |
| 关闭主窗口并保留菜单栏、小窗 | Command + W |
| 退出应用 | Command + Q 或菜单栏中的退出 |

悬浮窗可从空白处拖动，图钉按钮切换置顶，并可跨 Space 显示。隐藏窗口不会停止计时；需要停止累计时应点击“暂停”。

## 编辑日程

新建或编辑事项时，可以从小月历选择日期，并使用小时/分钟双列滚轮选择时间。分钟按 5 分钟递进；鼠标滚轮、触控板、方向键、Page Up/Page Down 和直接输入都可操作。快捷时长提供 30、60、90、120 分钟，“无固定时间”会明确清空开始和结束时间。

较早的结束时间会显示为“次日”，单个事项最长 24 小时。同一开始和结束时间可显式选择持续到次日。修改事项日期会走服务端的事务式跨日移动；正在计时的事项必须先暂停。来源日或目标日 revision 冲突时，两天都不会被部分覆盖，界面要求重新载入最新内容。

计时和网站限制语义保持不变：服务端维护 `elapsedSeconds` 与 `startedAt`；暂停、完成和切换事项时结算累计时间。退出客户端或系统休眠不会自动暂停。事项上的网站限制仍由既有 Chrome 扩展与本地服务执行，原生端不会扩大域名或时段。监督检查的触发时间也不会因本地保存而自动改变。

## 构建与验证

需要 macOS 13+ 与 Swift 5.9 或更新版本，不依赖第三方 Swift 包。

```sh
bash native/build.sh
swift run --package-path native DayCoreChecks --http
python3 -m unittest discover -s tests
node --test tests/schedule.test.mjs
codesign --verify --deep --strict native/build/daaaay.app
```

`DayCoreChecks --http` 使用临时目录和隔离回环端口，不会写入正式日程。公开仓库不包含真实 `blocker/schedule.json`；验证限制规则时，应复制公开的空示例到临时目录：

```sh
fixture="$(mktemp -d)"
cp -R blocker "$fixture/"
cp blocker/schedule.example.json "$fixture/blocker/schedule.json"
node "$fixture/blocker/validate.mjs"
```

隔离 UI 截图工具不启动数据服务，也不读取真实日程：

```sh
bash native/scripts/check-daylight-ui.sh --capture native/build/daylight-captures
```

它生成空日程、待开始、进行中、已完成、离线和待同步六种状态，分别覆盖 1020×680、1440×900 主窗口及 340×340 悬浮窗。截图只能验证渲染与静态结构；物理全局快捷键、多显示器拖动、全屏 Space 和 VoiceOver 实际朗读仍需要在目标 Mac 上人工验收。

构建产物位于 `native/build/daaaay.app`，使用本机 ad-hoc 签名，未做 Developer ID 签名或公证。应用依赖已有本地服务；复制 `.app` 到另一台 Mac 不会自动迁移日程或安装服务。
