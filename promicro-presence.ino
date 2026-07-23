// Pro Micro + HC-SR04 距離センサー + LED
// 距離をcm単位でシリアル送信
// 閾値はシリアルコマンド 'T150' で設定可能
// 'W' コマンドでキーを送信してディスプレイを起こす
// distanceが閾値以内ならLED点灯
//
// ノイズ対策（標準）:
//   1. 中央値フィルタ（直近 FILTER_SIZE サンプルの中央値）
//      → 単発スパイクを除去
//   2. 状態確定 debounce（連続 DEBOUNCE_NEEDED 回の同一判定で状態切替）
//      → 1回のノイズで「在室」が確定してディスプレイが点灯するのを防止
//   出力は常に「確定状態に基づく安定距離」なので、
//   SwiftBar / notify_if_absent.sh は既存の1回読み取り判定のままで正しく動く。

#include <Keyboard.h>

const int TRIG_PIN = 4;
const int ECHO_PIN = 5;
const int LED_PIN = 9;
const int DISPLAY_USB_POWER_PIN = A10;  // ディスプレイUSB給電検知用（アナログ入力）
const int USB_POWER_THRESHOLD = 300;    // USB給電判定閾値（0V=0, 1.5V≒465）

// HIDキーコード定数（未定義の無効なキーコード）
const uint8_t WAKE_KEYCODE = 0xA5;

// ---- ノイズ対策 定数 ----
const int FILTER_SIZE = 5;       // 中央値フィルタのサンプル数
const int DEBOUNCE_NEEDED = 3;   // 状態切替に必要な連続一致回数

int threshold_cm = 150;  // デフォルト値（フェイルセーフ）
bool threshold_received = false;  // 閾値受信フラグ
bool keyboard_initialized = false;  // キーボード初期化フラグ

void setup() {
  Serial.begin(9600);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(LED_PIN, OUTPUT);
  pinMode(DISPLAY_USB_POWER_PIN, INPUT);  // ディスプレイUSB給電検知

  // Keyboard.begin()は最初の'W'コマンド時のみ呼ぶ
  // （起動時に呼ぶとシリアル接続が切れる可能性があるため）

  // TX/RX LEDを無効にする (PD5, PB0を入力モードに設定)
  DDRD &= ~(1 << 5);  // TX LED (PD5) Input
  PORTD &= ~(1 << 5); // TX LED (PD5) No Pull-up (Hi-Z) - 消灯

  DDRB &= ~(1 << 0);  // RX LED (PB0) Input
  PORTB &= ~(1 << 0); // RX LED (PB0) No Pull-up (Hi-Z) - 消灯
}

// Raw HIDキー送信関数（無効なキーコードを送信してディスプレイを起こす）
void sendRawHIDKey(uint8_t hidKeycode) {
  uint8_t buf[8] = {0};
  buf[2] = hidKeycode;
  HID().SendReport(2, buf, 8);
  delay(50);
  memset(buf, 0, 8);
  HID().SendReport(2, buf, 8);
}

// ディスプレイON関数（'W'コマンドでHID送信）
void display_on() {
  if (!keyboard_initialized) {
    Keyboard.begin();
    delay(1000);
    keyboard_initialized = true;
  }
  sendRawHIDKey(WAKE_KEYCODE);

  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH);
    digitalWrite(LED_PIN, LOW);
  }
}

// ---- 中央値フィルタ（リングバッファ） ----
float sampleBuf[FILTER_SIZE];  // 直近サンプル
int sampleIdx = 0;             // 次の書き込み位置
int sampleCount = 0;           // 有効サンプル数（FILTER_SIZE まで）

// バッファの中央値を返す。有効サンプルが0のときは0を返す。
float medianOfBuffer() {
  if (sampleCount == 0) return 0;

  // 有効サンプル分だけコピーしてソート
  float tmp[FILTER_SIZE];
  int n = 0;
  for (int i = 0; i < sampleCount; i++) {
    tmp[n++] = sampleBuf[i];
  }

  // 挿入ソート（FILTER_SIZE が小さいので十分）
  for (int i = 1; i < n; i++) {
    float key = tmp[i];
    int j = i - 1;
    while (j >= 0 && tmp[j] > key) {
      tmp[j + 1] = tmp[j];
      j--;
    }
    tmp[j + 1] = key;
  }

  return tmp[n / 2];  // 中央要素
}

// ---- 状態確定 debounce ----
// 確定状態（true=在室, false=不在）と、反対判定の連続カウンタ
bool confirmedPresent = false;
bool stateInitialized = false;  // 初回確定済みか
int debounceCounter = 0;

float distance_old = 0;        // 極端値フィルタ用の前回有効生値
float stableDistance = 0;      // 確定状態に基づく出力用安定距離

void loop() {
  // Trigパルスを送信 (10μ秒以上)
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  // Echoパルスの時間を計測
  long duration = pulseIn(ECHO_PIN, HIGH);

  // 距離を計算 (cm) = 時間(μ秒) × 0.034 / 2
  float distance = duration * 0.034 / 2;

  // エラー値と異常値のフィルタリング（中央値フィルタの前段）
  // duration=0 はタイムアウト（pulseInのデフォルト）、1cm未満はノイズとみなす
  if (distance < 1.0 || distance > 1000) {
    // 無効な値の場合は前回の有効値を保持
    distance = distance_old;
  } else {
    distance_old = distance;
  }

  // ---- 中央値フィルタ: サンプル追加 ----
  sampleBuf[sampleIdx] = distance;
  sampleIdx = (sampleIdx + 1) % FILTER_SIZE;
  if (sampleCount < FILTER_SIZE) sampleCount++;

  float filtered = medianOfBuffer();

  // ---- 状態確定 debounce ----
  // フィルタ後距離による今回の在室判定
  bool nowPresent = (filtered <= threshold_cm);

  if (!stateInitialized) {
    // 初回（バッファ溜まり直後）は即確定して安定動作の起点を作る
    confirmedPresent = nowPresent;
    stableDistance = filtered;
    debounceCounter = 0;
    stateInitialized = true;
  } else if (nowPresent == confirmedPresent) {
    // 現在の確定状態と同じ判定ならカウンタリセット、安定距離を更新
    debounceCounter = 0;
    stableDistance = filtered;
  } else {
    // 反対判定が続いた場合のみカウントアップ
    debounceCounter++;
    if (debounceCounter >= DEBOUNCE_NEEDED) {
      // 連続一致に到達 → 状態切替確定
      confirmedPresent = nowPresent;
      stableDistance = filtered;
      debounceCounter = 0;
    }
    // 確定前は stableDistance をホールド（過渡期にノイズ距離を出さない）
  }

  // 距離とGPIO状態を送信（デバッグ用）
  int usbPower = analogRead(DISPLAY_USB_POWER_PIN);
  Serial.print(stableDistance, 1);
  Serial.print(",");
  Serial.println(usbPower);

  // distanceが閾値以内ならLED点灯（確定状態で判定）
  if (stableDistance <= threshold_cm) {
    digitalWrite(LED_PIN, HIGH);
  } else {
    digitalWrite(LED_PIN, LOW);
  }

  // シリアルコマンドをチェック
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();

    // 'W' コマンド：キーを送信してディスプレイを起こす
    if (command == "W") {
      display_on();  // GPIO10チェック済みの関数を呼ぶ
    }
    // 'T' コマンド：閾値更新
    else if (command.startsWith("T")) {
      int new_threshold = command.substring(1).toInt();
      if (new_threshold > 0 && new_threshold < 1000) {
        threshold_cm = new_threshold;
        threshold_received = true;
      }
    }
  }

  delay(10);
}
