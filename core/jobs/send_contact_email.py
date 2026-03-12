import os
import boto3
from core.log import create_log

log = create_log(__name__)

# SES config from environment
SES_FROM = os.getenv('SES_FROM_EMAIL', 'noreply@districtsolutions.ai')
SES_NOTIFY_TO = os.getenv('CONTACT_NOTIFY_EMAIL', 'contact@districtsolutions.ai')
SES_CONFIG_SET = os.getenv('SES_CONFIG_SET', 'biz-tool-prod')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')


def send_contact_email(tk) -> None:
    """Send a contact form notification email via AWS SES.

    Uses the EC2 instance's IAM role (no credentials needed).
    Falls back to logging the submission if SES send fails.

    Args:
        tk: Task instance with in_args containing name, email, company,
            service, and message fields.
    """
    args = tk.in_args or {}
    name = args.get('name', '')
    email = args.get('email', '')
    company = args.get('company', 'N/A')
    service = args.get('service', 'N/A')
    message = args.get('message', '')

    subject = f'[District Solutions] New inquiry from {name}'
    body_text = f"""New contact form submission:

Name: {name}
Email: {email}
Company: {company or 'N/A'}
Service Interest: {service or 'N/A'}

Message:
{message}

---
Task ID: {tk.id}
Reply directly to this email to respond to {name} at {email}.
"""

    body_html = f"""<html><body>
<h2>New Contact Form Submission</h2>
<table style="border-collapse:collapse;">
<tr><td style="padding:4px 12px 4px 0;font-weight:bold;">Name</td><td>{name}</td></tr>
<tr><td style="padding:4px 12px 4px 0;font-weight:bold;">Email</td><td><a href="mailto:{email}">{email}</a></td></tr>
<tr><td style="padding:4px 12px 4px 0;font-weight:bold;">Company</td><td>{company or 'N/A'}</td></tr>
<tr><td style="padding:4px 12px 4px 0;font-weight:bold;">Service</td><td>{service or 'N/A'}</td></tr>
</table>
<h3>Message</h3>
<p style="white-space:pre-wrap;">{message}</p>
<hr>
<p style="font-size:12px;color:#888;">Task ID: {tk.id}</p>
</body></html>"""

    client = boto3.client('ses', region_name=AWS_REGION)

    client.send_email(
        Source=SES_FROM,
        Destination={
            'ToAddresses': [SES_NOTIFY_TO],
        },
        Message={
            'Subject': {'Data': subject, 'Charset': 'UTF-8'},
            'Body': {
                'Text': {'Data': body_text, 'Charset': 'UTF-8'},
                'Html': {'Data': body_html, 'Charset': 'UTF-8'},
            },
        },
        ReplyToAddresses=[email],
        ConfigurationSetName=SES_CONFIG_SET,
    )

    log.info(f'contact email sent via SES tk.id={tk.id} from={name} <{email}>')
