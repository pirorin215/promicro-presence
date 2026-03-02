// Pro Micro + HC-SR04 距離センサー + LED
// 距離をcm単位でシリアル送信
// 閾値はシリアルコマンド 'T150' で設定可能
// 'W' コマンドでキーを送信してディスプレイを起こす
// distanceが閾値以内ならLED点灯

#include <Keyboard.h>

const int TRIG_PIN = 4;
const int ECHO_PIN = 5;
const int LED_PIN = 9;
const int DISPLAY_USB_POWER_PIN = A10;  // ディスプレイUSB給電検知用（アナログ入力）
const int USB_POWER_THRESHOLD = 300;    // USB給電判定閾値（0V=0, 1.5V≒465）

// HIDキーコード定数（未定義の無効なキーコード）
const uint8_t WAKE_KEYCODE = 0xA5;

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

  // LEDを3回素早く点滅させる
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(100);  // 100ms点灯
    digitalWrite(LED_PIN, LOW);
    delay(100);  // 100ms消灯
  }
}

float distance_old = 0;

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

  if(distance > 1000) {
    distance = distance_old;
  } else {
    distance_old = distance;
  }

  // 距離とGPIO状態を送信（デバッグ用）
  int usbPower = analogRead(DISPLAY_USB_POWER_PIN);
  Serial.print(distance, 1);
  Serial.print(",");
  Serial.println(usbPower);

  // distanceが閾値以内ならLED点灯
  if (distance <= threshold_cm) {
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
