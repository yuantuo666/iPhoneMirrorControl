# iPhoneMirror

在 macOS 上观察并操作「iPhone 镜像」窗口的小工具。

- `mirrorctl`：命令行工具。截图会裁剪到 iPhone 显示屏并叠加百分比网格/刻度尺；支持按百分比坐标点击、拖拽、键盘输入、点击前后差异校验、Vision OCR 文字定位。
- `ClaudeMirrorHelper.app`：常驻的截屏辅助程序（ScreenCaptureKit），把镜像窗口写入 PNG + JSON。因为系统「屏幕录制」权限只认应用签名，CLI 本身不需要该权限。

## 构建

```bash
# CLI
swift build -c release
.build/release/mirrorctl --help

# 截屏 helper（ad-hoc 签名）
./Helper/build.sh            # 生成 Helper/ClaudeMirrorHelper.app
./Helper/build.sh --install  # 安装到 ~/Library/Application Support/iPhoneMirror/Helper 并启动
```

首次运行 helper 时，系统会请求「屏幕录制」权限，请在弹窗或
系统设置 → 隐私与安全性 → 屏幕录制 中允许 `ClaudeMirrorHelper`。

> TCC 说明：helper 使用 ad-hoc 签名，系统把授权绑定到二进制的 cdhash。
> **每次重新构建 helper 后都需要重新授权**。如果看到反复弹出的授权请求，
> 先确认只有一个 helper 进程在运行：
> `pgrep -fl ClaudeMirrorHelper`，多余的用 `pkill -f <path>` 结束。

## 常用命令

```bash
mirrorctl status                  # 窗口/显示屏几何信息
mirrorctl capture                 # 生成带 0–100% 网格和刻度尺的截图，输出路径
mirrorctl capture --ocr-boxes     # 额外画出 OCR 识别框
mirrorctl ocr                     # 列出识别到的文字及百分比坐标
mirrorctl find 支付有礼            # 查找文字，返回坐标
mirrorctl click 50 65             # 按百分比点击（0,0 = 显示屏左上角）
mirrorctl click 50 65 --dry-run   # 只生成带准星的瞄准图，不点击
mirrorctl click 50 65 --verify    # 点击并报告屏幕变化比例（判断是否点中）
mirrorctl click-text 去领取 --verify   # OCR 找到文字并点击
mirrorctl drag 50 80 50 30 --duration 300
mirrorctl text "碰一碰"
mirrorctl key 53                  # 发送 keycode（53 = Escape）
mirrorctl calibrate --save        # 检测显示屏矩形并保存标定
```

### 坐标约定

- `--space norm`（默认）：iPhone 显示屏的百分比坐标，`0,0` 是显示屏左上角，`100,100` 是右下角。截图网格上的刻度就是这套坐标。
- `--space px`：相对显示屏裁剪图的像素坐标。
- `--space screen`：Mac 全局屏幕坐标（points）。

每次截图/点击时都会重新检测窗口内的显示屏矩形，因此窗口移动、标题栏浮现、缩放变化不会影响百分比坐标。`click --dry-run` 会把准星画在目标位置，便于点击前核对；`--verify` 会在点击后比较像素差异。

### 输出

- 原始窗口帧：`~/.local/share/iphone-mirror/capture/live.png`
- 状态：`.../status.json`
- 标注截图：`.../annotated.png`，瞄准图：`.../aim.png`
- 标定：`~/Library/Application Support/iPhoneMirror/calibration.json`
- 最近一次点击：`~/Library/Application Support/iPhoneMirror/last-tap.json`
  （`capture` 会在截图上用蓝色标记画出上次点击位置，便于校准）

可用环境变量：`MIRROR_CAPTURE_DIR`、`MIRROR_HELPER_APP`。

## Skills

仓库内附了两份可复用的操作手册（Claude Code skill 格式）：

- `.claude/skills/iphone-mirror-control/SKILL.md`：工具、坐标轴、校准、排错。
- `.claude/skills/alipay-pay-reward-browse-tasks/SKILL.md`：支付宝「支付有礼 → 做任务领红包」浏览任务的完整流程、坐标与坑。

## 实现要点

- 辅助程序每 0.5s 用 ScreenCaptureKit 截取 `com.apple.ScreenContinuity` 的窗口，原子写入 PNG/JSON。
- `mirrorctl` 读取帧后，用列/行像素剖面检测黑色背景中的圆角 iPhone 显示屏矩形（并排除窗口工具栏行），置信度不足时回退到已保存标定或按 0.46025 的屏幕比例计算。
- 标注图使用 10% 主网格、2% 刻度、顶部/左侧百分比标尺；点击坐标按检测到的显示屏矩形换算到窗口，再按窗口 frame 换算到全局屏幕坐标。
- 输入通过 `CGEvent`（需要终端/宿主进程具备「辅助功能」事件注入权限）。
