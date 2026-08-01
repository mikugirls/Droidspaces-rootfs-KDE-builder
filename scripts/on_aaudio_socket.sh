#!/usr/bin/env bash

# 1. 权限检测
if ! su -c "id -u" 2>/dev/null | grep -q "^0$"; then
    echo "❌ 需要 Root 权限，请授予 Termux Root 后重试。"
    exit 1
fi

#  自动扫描 /mnt/Droidspaces/ 下的容器（使用 root 权限）
CONTAINER_BASE="/mnt/Droidspaces"

if [ ! -d "$CONTAINER_BASE" ]; then
    echo "❌ 错误：容器目录 $CONTAINER_BASE 不存在"
    exit 1
fi

# 使用 su -c 以 root 权限列出子目录，并忽略权限错误
CONTAINER_LIST=$(su -c "find '$CONTAINER_BASE' -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null" | sort)

if [ -z "$CONTAINER_LIST" ]; then
    echo "❌ 错误：在 $CONTAINER_BASE 下未找到任何容器目录"
    echo "提示：请确认容器目录存在且 root 可访问"
    exit 1
fi

mapfile -t CONTAINERS <<< "$CONTAINER_LIST"

# 选择容器（只有一个则自动选用）
if [ ${#CONTAINERS[@]} -eq 1 ]; then
    CONTAINER_NAME="${CONTAINERS[0]}"
    echo "📂 仅发现一个容器，自动选中：$CONTAINER_NAME"
else
    echo "📂 发现以下容器："
    for i in "${!CONTAINERS[@]}"; do
        echo "  $((i+1))) ${CONTAINERS[$i]}"
    done
    read -p "请选择容器编号 [1-${#CONTAINERS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#CONTAINERS[@]} ]; then
        echo "❌ 无效选择"
        exit 1
    fi
    CONTAINER_NAME="${CONTAINERS[$((choice-1))]}"
fi

echo "✅ 已选择容器: $CONTAINER_NAME"

USERNAME="miku"  # 容器内用户名
DISPLAY_NUMBER=":5"  #开启桌面编号 :0 :1 :2
DPI=315                #termux-x11 DPI

# 2. 依赖检测 + 自动安装
required_commands=("pulseaudio" "pacmd" "pactl" "termux-x11" "id")
missing=()
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done

# 存在缺失依赖则自动执行安装
if [ ${#missing[@]} -ne 0 ]; then
    echo "⚠️ 检测到缺失依赖：${missing[*]}"
    echo "🔧 开始自动安装依赖..."
    pkg install pulseaudio sshpass openssh grep gawk coreutils x11-repo -y && pkg install termux-x11 -y
    echo "✅ 依赖安装完成，继续启动流程..."
fi

# 3. 启动 PulseAudio 音频
if pgrep -x "pulseaudio" > /dev/null; then
    echo "ℹ️ PulseAudio 已运行，跳过启动"
else
    echo "🚀 启动 PulseAudio..."
    pulseaudio -k 2>/dev/null
    sleep 0.2
    pulseaudio --start --load="module-native-protocol-unix socket=$PREFIX/tmp/.pulse-socket auth-anonymous=1" --exit-idle-time=-1 &
    sleep 0.2
    pacmd load-module module-aaudio-sink
    sleep 0.3
fi

# 设置 AAudio 为默认输出
AAUDIO_SINK=$(pactl list sinks short | grep "aaudio" | awk '{print $2}')
if [ -n "$AAUDIO_SINK" ]; then
    pactl set-default-sink "$AAUDIO_SINK"
    echo "✅ 默认音频设备：$AAUDIO_SINK"
else
    echo "⚠️ 未检测到 AAudio 音频设备"
fi

# 4. 启动 Termux-X11
if pgrep -f "termux-x11.*" > /dev/null; then
    echo "ℹ️ termux-x11 (${DISPLAY_NUMBER}) 已经在运行，重新启动。"
    pkill termux-x11 > /dev/null
    sleep 0.5
    termux-x11 "${DISPLAY_NUMBER}" -dpi "${DPI}" &
    sleep 0.5
else
    echo "🖥️ 正在启动 termux-x11..."
    termux-x11 "${DISPLAY_NUMBER}" -dpi "${DPI}" &
    sleep 0.5
fi

# 5. 启动 Droidspaces + KDE Plasma
if su -c "/data/local/Droidspaces/bin/droidspaces --name=\"${CONTAINER_NAME}\" info" | grep -q "${CONTAINER_NAME}"; then
    echo "🚀 容器 ${CONTAINER_NAME} 已就绪，启动 KDE 桌面..."
    su -c "/data/local/Droidspaces/bin/droidspaces --name=${CONTAINER_NAME} --user=${USERNAME} run env DISPLAY=${DISPLAY_NUMBER} startplasma-x11" &
    echo "✅ KDE 桌面启动成功，拉起 Termux-X11 窗口"
    su -c "am start -n com.termux.x11/.MainActivity"
else
    echo "❌ 容器 ${CONTAINER_NAME} 未运行，请先启动容器！"
    exit 1
fi