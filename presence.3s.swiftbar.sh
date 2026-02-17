#!/bin/bash
# <swiftbar.runInTerminal>false</swiftbar.runInTerminal>
# <swiftbar.debugLog>false</swiftbar.debugLog>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.image>system:name=person.fill</swiftbar.image>

. ~/promicro-presence/config.sh

# 距離を取得
DISTANCE=$(head -n 1 "$DEVICE" 2>/dev/null)

# デバイス接続エラー
if [ -z "$DISTANCE" ]; then
    echo "⚠️  No Device | color=red"
    echo "---"
    echo "Device: $DEVICE"
    echo "Refresh | refresh=true"
    exit 0
fi

# 整数に丸める
DISTANCE_INT=${DISTANCE%.*}

# 在室判定
if [ "$DISTANCE_INT" -le "$THRESHOLD_CM" ]; then
    # 在室
    echo "🟢 ${DISTANCE_INT}cm | color=green"
    echo "---"
    echo "Status: 在室"
else
    # 不在
    echo "🟠 ${DISTANCE_INT}cm | color=orange"
    echo "---"
    echo "Status: 不在"
fi

echo "---"
echo "Device: $DEVICE"
echo "Threshold: ${THRESHOLD_CM}cm"
echo "---"
echo "Refresh | refresh=true"
