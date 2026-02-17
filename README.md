# Pro Micro + HC-SR04 在室検知システム

Pro MicroとHC-SR04超音波センサーを使った在室検知システム。Claude Codeの通知を在室時に制御するために作成。

## 構成

```
HC-SR04 → Pro Micro → USB → Mac → シェルスクリプト → Claude Code hooks
```

## 配線

| HC-SR04 | Pro Micro |
|---------|-----------|
| VCC | 5V |
| GND | GND |
| Trig | D4 |
| Echo | D5 |

## インストール

1. Arduino IDEで `promicro_presence/promicro_presence.ino` を開く
2. ボード: `Arduino Micro`、ポート: `/dev/cu.usbmodem*` を選択
3. Pro Microに書き込む

4. 設定ファイルを作成:
```bash
cp config.sh.example config.sh
vim config.sh  # DEVICEなどを編集
```

5. 動作確認:
```bash
./get_distance.sh    # 距離を1回だけ取得
./watch_distance.sh  # 継続監視モード（Ctrl+Cで終了）
```

## Claude Codeへの統合

`~/.claude/settings.json` の hooks に以下を追加:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/promicro-presence/notify_if_absent.sh"
          }
        ]
      }
    ]
  }
}
```

これで在室時（閾値以下）は通知せず、不在時（閾値以上）のみ通知が届きます。

## ファイル構成

- `config.sh` - 共通設定ファイル（git管理外）
- `config.sh.example` - 設定ファイルのテンプレート
- `get_distance.sh` - 距離を取得するスクリプト
- `watch_distance.sh` - 継続監視モード
- `notify_if_absent.sh` - 在室判定して通知するスクリプト
- `promicro_presence/promicro_presence.ino` - Pro Micro用スケッチ

## 設定項目（config.sh）

- `DEVICE` - Pro Microのデバイスパス（例: `/dev/cu.usbmodem124301`）
- `THRESHOLD_CM` - 在室判定の閾値（cm）、この距離以下なら在室とみなす
- `NOTIFY_URL` - ntfy.shのトピックURL
- `NOTIFY_MESSAGE` - 通知メッセージ
