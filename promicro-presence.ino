// Pro Micro + HC-SR04 距離センサー + LED
// 距離をcm単位でシリアル送信
// 閾値はシリアルコマンド 'T150' で設定可能
// distanceが閾値以内ならLED点灯

const int TRIG_PIN = 4;
const int ECHO_PIN = 5;
const int LED_PIN = 9;

int threshold_cm = 150;  // デフォルト値（フェイルセーフ）
bool threshold_received = false;  // 閾値受信フラグ

void setup() {
  Serial.begin(9600);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(LED_PIN, OUTPUT);

  // TX/RX LEDを無効にする (PD5, PB0を入力モードに設定)
  DDRD &= ~(1 << 5);  // TX LED (PD5) Input
  PORTD &= ~(1 << 5); // TX LED (PD5) No Pull-up (Hi-Z) - 消灯

  DDRB &= ~(1 << 0);  // RX LED (PB0) Input
  PORTB &= ~(1 << 0); // RX LED (PB0) No Pull-up (Hi-Z) - 消灯
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

  // 距離を送信
  Serial.println(distance, 1);

  // distanceが閾値以内ならLED点灯
  if (distance <= threshold_cm) {
    digitalWrite(LED_PIN, HIGH);
  } else {
    digitalWrite(LED_PIN, LOW);
  }

  // シリアルコマンドをチェック（閾値更新）
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    if (command.startsWith("T")) {
      int new_threshold = command.substring(1).toInt();
      if (new_threshold > 0 && new_threshold < 1000) {
        threshold_cm = new_threshold;
        threshold_received = true;
      }
    }
  }

  delay(10);
}
