# EraTest

極簡診斷 App：把 SideStore **0.6.4 年代**的連線棧與登入搬進一個獨立 App，
用來在真機上量測「舊連線序列能否通過裝置的第一個 lockdown 交換」。
巨魔（TrollStore）安裝未簽名 IPA 使用。

## 組成（版本釘死）

| 元件 | 釘版 | 來源 |
|---|---|---|
| minimuxer | `2e72b199801de268e2169d24ccc90357cf9ab692` | submodule → SideStore/minimuxer（0.6.4 的 gitlink，內含 idevice v0.1.66-ss） |
| SideSign | `7f818429fec3` + 我方 patch commit | submodule → yongshuai1013/SideSign 分支 `eratest-0.6.4` |
| AnisetteKit | `2b4a643f5302826828bf36580fee61aba655b6bb` | yongshuai1013/AnisetteKit（A10 安全版） |

## 刻意偏離（全部列明）

1. **AnisetteKit 不用 0.6.4 原 pin**（mahee96/AnisetteKit @ 9d8ad7050e）：
   原版 Unicorn 含 A10 跑不了的 LSE 指令，iPhone 7 上 ADI 配置會閃退
   （2026-11-17 已定讞）。改用我方 A10 安全版 `2b4a643`（原 pin 的後代，
   API 相容）。SideSign 的 Package.swift 亦同步改指此 fork 並把
   CodeSignKit / GSACryptoKit / libdeflate 由 branch 改釘 0.6.4 workspace
   實際解析的 revision。
2. **登入 403 修法**（SideSign fork 內，Swift 等效 EiliStore
   `3a7230d7` 的 Rust 正解，該修法 2026-11-19 真機驗過 PASS）：
   - Content-Type：**不改**。SideSign 的 SRP 端點寫死 gsa.apple.com，
     gsa 不擋 `text/x-xml-plist`（擋的是 gsd，而此客戶端不接觸 gsd）。
   - GsService2 尾斜線：**有改**。`Constants.URLs.grandSlamAuth`
     改為 `https://gsa.apple.com/grandslam/GsService2/`。
   - RINFO / Client-Time：**不改**。SRP 的 cpd 字典與 2FA 請求標頭
     本來就帶 `X-Apple-I-MD-RINFO` 與 `X-Apple-I-Client-Time`。

## App 功能

單頁三區＋即時日誌（同步寫入 `Documents/eratest.log`，已開檔案共享）：

1. **配對檔**：匯入 lockdown 配對 `.plist`、存入 Documents、顯示 UDID。
2. **連接測試**：以配對檔啟動 minimuxer → `fetchUDID` → 顯示結果或錯誤原文。
3. **登入與註冊**：Apple ID＋密碼 → SideSign SRP 登入（含 2FA：信任裝置／
   簡訊選號＋驗證碼輸入）→ 取 Team → 經 minimuxer 取得 UDID 並向
   Developer Portal 註冊裝置（順序照 0.6.4 SignInOperation）。

## 建置

CI（GitHub Actions, macOS）：XcodeGen 產生專案 → xcodebuild Release
（不簽名）→ 打包 `EraTest.ipa` 為 artifact。本機不需建置。
