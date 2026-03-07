{
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "{{SUBJECT}}"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Host:* {{HOSTNAME}}\n*Time:* {{TIMESTAMP}}"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "{{EVENT_SUMMARY}}"
      }
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "Source: {{SRC_IP}} | Failures: {{FAIL_COUNT}}"
        }
      ]
    },
    {
      "type": "divider"
    }
  ]
}
