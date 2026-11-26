---
name: alipay-pay-reward-browse-tasks
description: Walk the Alipay 碰一碰 → 支付有礼 → 做任务领红包 browsing tasks on a mirrored iPhone, claim every 去领取/开心收下 reward, and skip tasks that require spending money. Includes the quirks for 蚂蚁阿福/蚂蚁财富 embedded pages and 13-second campaign pages.
---

# Alipay 支付有礼 · 做任务领红包 (browse tasks)

Goal: complete every **browsing** task in 支付有礼 and claim the red packets, without
doing tasks that require spending money (recharge, ride orders, utility bills,
bank spending, insurance activation).

Use the `iphone-mirror-control` skill for tooling and calibration.

## Navigation

1. Open Alipay (dock icon, bottom-right).
2. Tap the search bar → choose the **碰一碰** history chip (or type it).
3. On the 碰一碰 results page, tap the **支付有礼** tile in the 碰一下 service card
   (the right tile; the left tile 使用攻略 opens a different guide page).
4. The 支付有礼 campaign page opens at the top. **Scroll up** (swipe content up)
   to reach `做任务领红包 下笔更省`.
5. Tap **全部任务** to open the task sheet. The sheet only scrolls; tasks that
   finish move to the top with a **去领取** button, and new tasks rotate in.

## Completing browsing tasks

Task rows look like `逛一逛…`, `逛15s…`, `去蚂蚁森林收大额能量`, `逛一逛金豆…`,
`逛一逛芭芭农场`, `逛一逛蚂蚁庄园`, `逛一逛蚂蚁阿福`, `逛一逛蚂蚁财富APP`.

Two completion patterns:

1. **Campaign mini-pages** (金豆矿工, 金豆夺宝, 蚂蚁森林, 芭芭农场, 蚂蚁庄园):
   - Tap the row's 去完成.
   - Stay until the bottom-right badge changes to **任务完成 返回会场**
     (13 s browse timer; ~14–15 s from the tap) or the page shows
     **恭喜获得红包奖励，返回领取**.
   - Tap that banner/badge to return.
2. **Embedded apps** (蚂蚁阿福, 蚂蚁财富APP):
   - Tap 去完成; dismiss any system dialog (e.g., location → **不允许**).
   - Browse the page briefly (these usually count on open).
   - **Tap the top-left “支付宝” breadcrumb** to exit back to Alipay. OCR
     `find 支付宝` / `click-text 支付宝` is the reliable way; it sat at
     ≈7.4%, 4.7% on these pages. Do not rely on the faint left chevron — it
     can disappear or be non-interactive.

## Claiming

After returning, the task row shows **去领取** (often at ≈85%, 42% near the top of
the sheet) and/or on the main page. Tap it, then tap **开心收下** in the reward
popup (≈49.7%, 59.5%). One-shot:

```bash
mirrorctl collect --timeout 10
```

`collect` waits for 去领取, taps it, waits for 开心收下, and taps it.

Fast loop per task:

```bash
mirrorctl click-text 去完成 --index N --verify
mirrorctl wait-any 返回会场 返回领取 任务完成 --click --timeout 25 --verify
mirrorctl collect --timeout 10
```

For 蚂蚁阿福/蚂蚁财富, replace the `wait-any` step with:

```bash
mirrorctl click-text 支付宝 --verify     # top-left breadcrumb
mirrorctl collect --timeout 10
```

## Observed results (2026-11-26)

Completed browsing tasks and rewards: 逛一逛支付宝会员 0.05, 逛一逛金豆矿工 0.05,
蚂蚁森林收能量 0.05, 逛一逛芭芭农场 0.10, 逛一逛蚂蚁庄园 0.10, 逛一逛金豆夺宝 0.05,
逛一逛蚂蚁阿福 0.20, 逛一逛蚂蚁财富APP 0.20 → **¥0.8** accumulated (main page shows
`下笔到店支付 ¥0.8`). Remaining tasks were non-browsing (油卡充值, 顺风车订单,
电费, 网商银行消费, 学知识添加健康保障) and were intentionally skipped.

## Gotchas

- The App Switcher / Home buttons live in the Mac title bar, not the phone UI.
  If an embedded page traps you (e.g., 阿福 splash), use Home → App Switcher →
  swipe the Alipay card up to force-quit, then reopen Alipay and repeat navigation.
- Task list order changes after each completion; re-run `全部任务` and re-read
  OCR instead of reusing old row indices.
- The main 支付有礼 page resets to the top after returning from certain tasks;
  scroll down again before looking for 全部任务.
- Money-spending tasks are left untouched. Never tap 去完成 on them.
