"""
CloudWatch Alarm → SNS → Lambda → Slack Webhook

SNS 메시지를 파싱하여 Slack Block Kit 포맷으로 변환 후 전송합니다.

환경 변수:
  SLACK_WEBHOOK_URL: Slack Incoming Webhook URL
  ENVIRONMENT: 배포 환경 (dev / staging / prod)
"""

import json
import os
import urllib.request
import urllib.error


def handler(event, context):
    webhook_url = os.environ["SLACK_WEBHOOK_URL"]
    environment = os.environ.get("ENVIRONMENT", "unknown")

    for record in event["Records"]:
        message = json.loads(record["Sns"]["Message"])

        alarm_name = message.get("AlarmName", "Unknown Alarm")
        new_state = message.get("NewStateValue", "UNKNOWN")
        reason = message.get("NewStateReason", "")
        description = message.get("AlarmDescription", "")
        region = message.get("Region", "ap-northeast-2")
        timestamp = record["Sns"].get("Timestamp", "")

        # 상태별 이모지 및 색상
        state_config = {
            "ALARM": {"emoji": ":rotating_light:", "color": "#E74C3C"},
            "OK": {"emoji": ":white_check_mark:", "color": "#2ECC71"},
            "INSUFFICIENT_DATA": {"emoji": ":warning:", "color": "#F39C12"},
        }
        config = state_config.get(new_state, {"emoji": ":question:", "color": "#95A5A6"})

        # CloudWatch 콘솔 링크
        alarm_url = (
            f"https://{region}.console.aws.amazon.com/cloudwatch/home"
            f"?region={region}#alarmsV2:alarm/{alarm_name}"
        )

        blocks = [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{config['emoji']} [{environment.upper()}] CloudWatch Alarm",
                },
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Alarm:*\n{alarm_name}"},
                    {"type": "mrkdwn", "text": f"*State:*\n{new_state}"},
                    {"type": "mrkdwn", "text": f"*Environment:*\n{environment}"},
                    {"type": "mrkdwn", "text": f"*Time:*\n{timestamp}"},
                ],
            },
        ]

        if description:
            blocks.append(
                {
                    "type": "section",
                    "text": {"type": "mrkdwn", "text": f"*Description:*\n{description}"},
                }
            )

        # 원인 (최대 300자)
        truncated_reason = reason[:300] + "..." if len(reason) > 300 else reason
        blocks.append(
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*Reason:*\n{truncated_reason}"},
            }
        )

        blocks.append(
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "View in CloudWatch"},
                        "url": alarm_url,
                    }
                ],
            }
        )

        payload = json.dumps({"blocks": blocks}).encode("utf-8")

        req = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                print(f"Slack notification sent: {resp.status} for alarm={alarm_name}")
        except urllib.error.URLError as e:
            print(f"Failed to send Slack notification: {e}")
            raise

    return {"statusCode": 200}
