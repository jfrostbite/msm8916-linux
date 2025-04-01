#!/bin/bash

# 定义电池灯的路径
LED_PATH="/sys/class/leds"
BATTERY_PATH="/sys/class/power_supply/pm8916-bms-vm"

# 定义灯的名称
LED1="bat1"
LED2="batl2"
LED3="batl3"
LED4="batl4"

# 获取电池电量和充电状态
CAPACITY=$(cat $BATTERY_PATH/capacity)
STATUS=$(cat $BATTERY_PATH/status)

# 关闭所有灯的触发器，恢复手动控制
echo none > $LED_PATH/$LED1/trigger
echo none > $LED_PATH/$LED2/trigger
echo none > $LED_PATH/$LED3/trigger
echo none > $LED_PATH/$LED4/trigger

# 根据电量判断真实状态
if [ "$CAPACITY" -eq 100 ]; then
    STATUS="Full"
else
    STATUS="$RAW_STATUS"
fi

# 根据电池电量点亮灯
if [ "$STATUS" == "Charging" ]; then
    # 如果正在充电
    if [ "$CAPACITY" -le 25 ]; then
        echo timer > $LED_PATH/$LED1/trigger
    elif [ "$CAPACITY" -le 50 ]; then
        echo 1 > $LED_PATH/$LED1/brightness
        echo timer > $LED_PATH/$LED2/trigger
    elif [ "$CAPACITY" -le 75 ]; then
        echo 1 > $LED_PATH/$LED1/brightness
        echo 1 > $LED_PATH/$LED2/brightness
        echo timer > $LED_PATH/$LED3/trigger
    else
        echo 1 > $LED_PATH/$LED1/brightness
        echo 1 > $LED_PATH/$LED2/brightness
        echo 1 > $LED_PATH/$LED3/brightness
        echo timer > $LED_PATH/$LED4/trigger
    fi
else
    # 如果未充电
    if [ "$CAPACITY" -le 25 ]; then
        echo 1 > $LED_PATH/$LED1/brightness
        echo 0 > $LED_PATH/$LED2/brightness
        echo 0 > $LED_PATH/$LED3/brightness
        echo 0 > $LED_PATH/$LED4/brightness
    elif [ "$CAPACITY" -le 50 ]; then
        echo 1 > $LED_PATH/$LED1/brightness
        echo 1 > $LED_PATH/$LED2/brightness
        echo 0 > $LED_PATH/$LED3/brightness
        echo 0 > $LED_PATH/$LED4/brightness
    elif [ "$CAPACITY" -le 75 ]; then
        echo 1 > $LED_PATH/$LED1/brightness
        echo 1 > $LED_PATH/$LED2/brightness
        echo 1 > $LED_PATH/$LED3/brightness
        echo 0 > $LED_PATH/$LED4/brightness
    else
        echo 1 > $LED_PATH/$LED1/brightness
        echo 1 > $LED_PATH/$LED2/brightness
        echo 1 > $LED_PATH/$LED3/brightness
        echo 1 > $LED_PATH/$LED4/brightness
    fi
fi