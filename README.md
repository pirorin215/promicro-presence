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

1. Arduino IDEで `promicro_presence.ino` を開く
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
    ],
    "Notification": [
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

### Hookの発火タイミング

| Hook | 発火タイミング |
|------|--------------|
| `Stop` | Claudeが一連の応答を完了したとき |
| `Notification` | ツールの実行許可（パーミッション確認ダイアログ）を求めるとき / 入力待ちが60秒以上続いたとき |

両方に設定することで、「作業完了」と「許可待ち（例: `chmod` などの確認ダイアログ）」のどちらでも通知が届きます。

## 通知の流れ

1. Claude CodeがHookを発火
2. `notify_if_absent.sh` がHC-SR04で距離を計測
3. 在室（閾値以下）→ 音のみ鳴らす（通知は送らない）
4. 不在（閾値超え）→ 音を鳴らして、ntfy.sh経由でスマホに通知送信

## ntfy.sh の設定

**ntfy.sh** は無料のプッシュ通知サービスです。登録なしで誰でも使用できます。

### トピックの作成

特別な登録は不要。`config.sh` でトピック名を指定するだけです：

```bash
# config.sh
NOTIFY_URL="ntfy.sh/your-unique-topic-name"
```

**セキュリティ推奨**: 他人が推測しにくいランダムなトピック名を使用してください：

```bash
NOTIFY_URL="ntfy.sh/$(uuidgen | tr -d '-')"
```

### スマホで通知を受け取る

1. **アプリをインストール**:
   - iOS: [ntfy - Push Notifications](https://apps.apple.com/app/id1625396809)
   - Android: [ntfy - Push Notifications](https://play.google.com/store/apps/details?id=io.heckel.ntfy)

2. **トピックを購読**:
   - アプリを開く
   - 「Subscribe」タブをタップ
   - トピック名を入力（例: `your-unique-topic-name`）
   - Subscribeをタップ

3. **通知テスト**:
   ```bash
   curl -d "テスト通知" "ntfy.sh/your-unique-topic-name"
   ```

公式サイト: https://ntfy.sh/

## ファイル構成

- `config.sh` - 共通設定ファイル（git管理外）
- `config.sh.example` - 設定ファイルのテンプレート
- `get_distance.sh` - 距離を取得するスクリプト
- `watch_distance.sh` - 継続監視モード
- `notify_if_absent.sh` - 在室判定して通知するスクリプト
- `promicro_presence/promicro_presence.ino` - Pro Micro用スケッチ

## 設定項目（config.sh）

- `DEVICE` - Pro Microのデバイスパス（例: `/dev/cu.usbmodemHIDPC1`）
- `THRESHOLD_CM` - 在室判定の閾値（cm）、この距離以下なら在室とみなす
- `NOTIFY_URL` - ntfy.shのトピックURL
- `NOTIFY_MESSAGE` - 通知メッセージ
- `SOUND_FILE` - 在室時に鳴らす音声ファイルのパス
