{
  "embeds": [
    {
      "title": "{{SUBJECT}}",
      "color": 13369344,
      "fields": [
        {
          "name": "Host",
          "value": "{{HOSTNAME}}",
          "inline": true
        },
        {
          "name": "Time",
          "value": "{{TIMESTAMP}}",
          "inline": true
        },
        {
          "name": "Summary",
          "value": "{{EVENT_SUMMARY}}",
          "inline": false
        },
        {
          "name": "Source IP",
          "value": "{{SRC_IP}}",
          "inline": true
        },
        {
          "name": "Failures",
          "value": "{{FAIL_COUNT}}",
          "inline": true
        }
      ],
      "footer": {
        "text": "Generated on {{HOSTNAME}}"
      }
    }
  ]
}
