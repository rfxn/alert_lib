<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
  body { font-family: Arial, Helvetica, sans-serif; margin: 0; padding: 0; background: #f4f4f4; }
  .container { max-width: 600px; margin: 20px auto; background: #ffffff; border: 1px solid #dddddd; }
  .header { background: #cc0000; color: #ffffff; padding: 15px 20px; }
  .header h2 { margin: 0; font-size: 18px; }
  .body { padding: 20px; color: #333333; line-height: 1.5; }
  .field { margin-bottom: 8px; }
  .label { font-weight: bold; color: #555555; }
  .summary { background: #fff3f3; border-left: 4px solid #cc0000; padding: 12px 15px; margin: 15px 0; }
  .footer { padding: 15px 20px; font-size: 12px; color: #999999; border-top: 1px solid #eeeeee; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h2>Alert: {{SUBJECT}}</h2>
  </div>
  <div class="body">
    <div class="field"><span class="label">Host:</span> {{HOSTNAME}}</div>
    <div class="field"><span class="label">Time:</span> {{TIMESTAMP}}</div>
    <div class="summary">{{EVENT_SUMMARY}}</div>
    <div class="field"><span class="label">Source IP:</span> {{SRC_IP}}</div>
    <div class="field"><span class="label">Failures:</span> {{FAIL_COUNT}}</div>
    <div class="field"><span class="label">Action:</span> {{ACTION}}</div>
  </div>
  <div class="footer">
    Generated on {{HOSTNAME}}. Do not reply to this message.
  </div>
</div>
</body>
</html>
