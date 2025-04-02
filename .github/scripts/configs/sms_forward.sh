#!/bin/bash

# WxPusher 配置
WXPUSHER_APP_TOKEN="AT_lGDjrw76OCEIidZfwxkzaDNhW2B9CQAC" # 替换为你的 WxPusher 应用 Token
WXPUSHER_UID="UID_GdWShJbobaaeG5jVRrmZvWUeDMke"          # 替换为你的 WxPusher 用户 UID
API_URL="https://wxpusher.zjiecode.com/api/send/message"

# 日志文件路径
LOG_FILE="/var/log/sms_forward.log"

# 设置短信最大长度
MAX_LENGTH=500

# 检查电量 是否低于 10%, cat /sys/class/power_supply/pm8916-bms-vm/capacity ,低于 10% 则发送通知
BATTERY_LEVEL=$(cat /sys/class/power_supply/pm8916-bms-vm/capacity)
if [ "$BATTERY_LEVEL" -lt 10 ]; then
    if [ ! -f "/tmp/low_battery_notified" ]; then
        echo "[WARNING] [$(date)] 电量过低：$BATTERY_LEVEL%" >>"$LOG_FILE"
        # 发送电量过低通知
        JSON_DATA=$(printf '{ 
                "appToken": "%s",
                "content": "电量过低",
                "summary": "电量警告：电量%s%%",
                "contentType": 1,
                "uids": ["%s"]
            }' "$WXPUSHER_APP_TOKEN" "$BATTERY_LEVEL" "$WXPUSHER_UID")
        RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$API_URL")
        echo "[INFO] [$(date)] 电量过低通知发送结果：$RESPONSE" >>"$LOG_FILE"
        touch /tmp/low_battery_notified
    fi
else
    # 如果电量恢复到 10% 以上，清除通知标志
    [ -f "/tmp/low_battery_notified" ] && rm /tmp/low_battery_notified
fi

# 定期删除日志文件，避免过大
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -c%s "$LOG_FILE")
    if [ $LOG_SIZE -gt 1048576 ]; then # 如果日志文件大于 1MB
        echo "[INFO] [$(date)] 日志文件过大，删除旧日志..." >>"$LOG_FILE"
        >"$LOG_FILE" # 清空日志文件
    fi
fi

# 列出当前所有短信，过滤未读 "received" 状态
NEW_SMS=$(mmcli -m 0 --messaging-list-sms | grep "(received)")

# 如果有新的短信
if [ ! -z "$NEW_SMS" ]; then
    echo "[INFO] [$(date)] 检测到新短信：$NEW_SMS" >>"$LOG_FILE"

    # 提取短信路径 (例如 /org/freedesktop/ModemManager1/SMS/8)
    SMS_PATH=$(echo "$NEW_SMS" | head -n 1 | awk '{print $1}')
    
    # 获取短信的具体详细信息
    SMS_INFO=$(mmcli -s "$SMS_PATH")
    echo "[INFO] [$(date)] 短信详情：$SMS_INFO" >>"$LOG_FILE"

    # 提取短信发送者号码、内容和时间戳
    NUMBER=$(echo "$SMS_INFO" | grep -E "number:" | awk -F": " '{print $2}' | tr -d '\r')
    CONTENT=$(echo "$SMS_INFO" | grep -A 1 "number:" | tail -n 1 | sed 's/^text: //g' | sed 's/[[:space:]]\+/ /g' | tr -d '\r')
    TIMESTAMP=$(echo "$SMS_INFO" | grep "timestamp:" | sed 's/.*timestamp:\s*//g' | tr -d '\r')

    # 如果号码或内容为空，则跳过处理
    if [[ -z "$NUMBER" || -z "$CONTENT" ]]; then
        echo "[ERROR] [$(date)] 短信号码或内容提取失败，跳过短信：$SMS_PATH" >>"$LOG_FILE"
        exit 1
    fi

    # 如果短信内容过长，截断至规定长度
    CONTENT_CLEAN=$(echo "$CONTENT" | cut -c 1-$MAX_LENGTH)

    SUMMARY="短信转发通知"

    # 检测短信内容$CONTENT_CLEAN 是否包含验证码（假设验证码是 4-8 位数字），否则跳过
    # 过滤掉包含大于8位数字的短信
    if echo "$CONTENT_CLEAN" | grep -qE '[0-9]{9,}'; then
        echo "[INFO] [$(date)] 短信内容包含大于8位的数字，跳过短信：$SMS_PATH" >>"$LOG_FILE"
        exit 1
    fi

    # 过滤掉运营商短信（假设运营商短信包含特定关键词，如 "中国移动", "中国联通", "中国电信"）
    if echo "$CONTENT_CLEAN" | grep -qE '中国移动|中国联通|中国电信'; then
        echo "[INFO] [$(date)] 检测到运营商短信，跳过短信：$SMS_PATH" >>"$LOG_FILE"
        exit 1
    fi
    CODE=$(echo "$CONTENT_CLEAN" | grep -oE '(\u9a8c\u8bc1\u7801|auth|code)[^0-9]{0,20}[0-9]{4,8}' | grep -oE '[0-9]{4,8}' | head -n 1)
    if [[ -z "$CODE" ]]; then
        CODE=$(echo "$CONTENT_CLEAN" | grep -oE '[0-9]{4,8}' | head -n 1)
        SUMMARY="验证码：$CODE"
        echo "[INFO] [$(date)] 提取到验证码：$CODE" >>"$LOG_FILE"
    else
        echo "[INFO] [$(date)] 短信内容不包含验证码，跳过短信：$SMS_PATH" >>"$LOG_FILE"
        exit 1
    fi

    # 检查是否已经发送过相同的验证码
    if [ -f "/tmp/sms_code" ]; then
        OLD_CODE=$(cat /tmp/sms_code)
        if [ "$CODE" == "$OLD_CODE" ]; then
            echo "[INFO] [$(date)] 短信验证码已发送，跳过短信：$SMS_PATH" >>"$LOG_FILE"
            # 循环删除短信
            for i in {1..6}; do
                DELETE_RESPONSE=$(mmcli -m 0 --messaging-delete-sms="$SMS_PATH")
                DELETE_RESPONSE=echo "$DELETE_RESPONSE" | grep "success"
                if [[ "x$DELETE_RESPONSE" == "x" ]]; then
                    echo "[WARNING] [$(date)] 短信删除失败，重试中：$SMS_PATH (尝试 $i/6)" >>"$LOG_FILE"
                    sleep 1
                else
                    echo "[INFO] [$(date)] 重复短信删除成功：$SMS_PATH" >>"$LOG_FILE"
                    break
                fi
            done
            exit 0
        fi
    fi

    # 保存当前短信验证码到临时文件 
    echo "$CODE" >"/tmp/sms_code"
    echo "[INFO] [$(date)] 保存短信验证码到临时文件：$CODE" >>"$LOG_FILE"

    # 使用 printf 构建 JSON 数据，确保换行符被正确处理
    JSON_DATA=$(printf '{ 
            "appToken": "%s",
            "content": "短信转发\\n发送者: %s\\n时间: %s\\n内容: %s",
            "summary": "%s",
            "contentType": 1,
            "uids": ["%s"]
        }' "$WXPUSHER_APP_TOKEN" "$NUMBER" "$TIMESTAMP" "$CONTENT_CLEAN" "$SUMMARY" "$WXPUSHER_UID")

    echo "[INFO] [$(date)] 构建的 JSON 数据：$JSON_DATA" >>"$LOG_FILE"

    # 调用 WxPusher API 进行发送
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$API_URL")
    echo "[INFO] [$(date)] WxPusher 转发结果：$RESPONSE" >>"$LOG_FILE"

    # 解析结果，判断是否发送成功
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [[ "$SUCCESS" == "true" ]] && [[ -n "$RESPONSE" ]]; then
        echo "[INFO] [$(date)] 短信转发成功，尝试删除短信：$SMS_PATH" >>"$LOG_FILE"
        # 循环尝试删除短信，直到成功
        for i in {1..6}; do
            DELETE_RESPONSE=$(mmcli -m 0 --messaging-delete-sms="$SMS_PATH")
            DELETE_RESPONSE=echo "$DELETE_RESPONSE" | grep "success"
            if [[ "x$DELETE_RESPONSE" == "x" ]]; then
                echo "[WARNING] [$(date)] 短信删除失败，重试中：$SMS_PATH (尝试 $i/6)" >>"$LOG_FILE"
                sleep 1
            else
                echo "[INFO] [$(date)] 短信删除成功：$SMS_PATH" >>"$LOG_FILE"
                break
            fi
        done
    else
        echo "[ERROR] [$(date)] 短信转发失败，保留短信：$SMS_PATH" >>"$LOG_FILE"
    fi
fi
