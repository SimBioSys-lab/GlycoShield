#!/usr/bin/env python3
"""
Email notification script for GlycoShield job submission and completion
Supports multiple email templates for different stages of the pipeline
"""

import sys
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
import argparse
from pathlib import Path

def load_env_file(env_path='.env'):
    """Load environment variables from .env file"""
    env_vars = {}
    env_candidates = [
        Path('.env'),
        Path(__file__).parent / '.env',
        Path(os.environ.get('SCRIPT_DIR', '.')) / '.env'
    ]
    
    env_file = None
    for candidate in env_candidates:
        if candidate.exists():
            env_file = candidate
            break
    
    if env_file and env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    env_vars[key] = value
    
    return env_vars

def send_submission_email(to_email, user_id, job_name, user_name):
    """
    Send job submission acknowledgment email
    
    Args:
        to_email: Recipient email address
        user_id: User ID who submitted the job
        job_name: Name/ID of the job
        user_name: Name of the user
    """
    
    # Load environment variables
    env_vars = load_env_file()
    
    # Email configuration
    smtp_host = env_vars.get('SMTP_HOST', 'smtp.gmail.com')
    smtp_port = int(env_vars.get('SMTP_PORT', '587'))
    smtp_user = env_vars.get('SMTP_USER', 'glycomap.simbiosys@gmail.com')
    smtp_password = env_vars.get('SMTP_PASSWORD', '')
    from_email = env_vars.get('FROM_EMAIL', smtp_user)
    
    # Get submission time
    submission_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Create message
    msg = MIMEMultipart('alternative')
    msg['Subject'] = f'GlycoShield Job Submitted Successfully - {job_name}'
    msg['From'] = f'GlycoShield Pipeline <{from_email}>'
    msg['To'] = to_email
    
    # Plain text version
    text_content = f"""
Dear {user_name},

Your GlycoShield analysis job has been successfully submitted to the HPC cluster.

Job Details:
------------
Job Name: {job_name}
User ID: {user_id}
Submission Time: {submission_time}

What's Next?
------------
1. Your job is now queued for processing on the HPC cluster
2. The analysis includes:
   - Ensemble modeling with AllosMod
   - GEF (Geometric Exposure Factor) analysis
   - Glycan chain processing
3. Processing time depends on protein size and queue status
4. You will receive an email with a download link once the analysis is complete

If you have any questions or concerns, please contact the SimBioSys Lab support team.

Best regards,
GlycoShield Pipeline
SimBioSys Lab
Northeastern University
"""

    # HTML version
    html_content = f"""
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
                   color: white; padding: 20px; border-radius: 10px 10px 0 0; }}
        .content {{ background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }}
        .details {{ background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .detail-item {{ margin: 10px 0; }}
        .label {{ font-weight: bold; color: #667eea; }}
        .value {{ color: #555; }}
        .steps {{ background: #e8f4fd; padding: 15px; border-left: 4px solid #667eea; 
                  margin: 15px 0; border-radius: 4px; }}
        .footer {{ text-align: center; padding-top: 20px; color: #888; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>🧬 GlycoShield Job Submitted Successfully</h2>
        </div>
        <div class="content">
            <p>Dear {user_name},</p>
            <p>Your GlycoShield analysis job has been successfully submitted to the HPC cluster.</p>
            
            <div class="details">
                <h3>📋 Job Details</h3>
                <div class="detail-item">
                    <span class="label">Job Name:</span> 
                    <span class="value">{job_name}</span>
                </div>
                <div class="detail-item">
                    <span class="label">User ID:</span> 
                    <span class="value">{user_id}</span>
                </div>
                <div class="detail-item">
                    <span class="label">Submission Time:</span> 
                    <span class="value">{submission_time}</span>
                </div>
            </div>
            
            <div class="steps">
                <h3>🔄 What's Next?</h3>
                <ol>
                    <li>Your job is now queued for processing on the HPC cluster</li>
                    <li>The analysis includes:
                        <ul>
                            <li>Ensemble modeling with AllosMod</li>
                            <li>GEF (Geometric Exposure Factor) analysis</li>
                            <li>Glycan chain processing</li>
                        </ul>
                    </li>
                    <li>Processing time depends on protein size and queue status</li>
                    <li><strong>You will receive an email with a download link once the analysis is complete</strong></li>
                </ol>
            </div>
            
            <p>If you have any questions or concerns, please contact the SimBioSys Lab support team.</p>
            
            <p>Best regards,<br>
            <strong>GlycoShield Pipeline</strong><br>
            SimBioSys Lab<br>
            Northeastern University</p>
        </div>
        <div class="footer">
            <p>This is an automated message from the GlycoShield Pipeline system.</p>
        </div>
    </div>
</body>
</html>
"""
    
    return send_email(msg, text_content, html_content, smtp_host, smtp_port, 
                     smtp_user, smtp_password, to_email)

def send_completion_email(to_email, user_id, job_name, user_name, download_link):
    """
    Send job completion email with download link
    
    Args:
        to_email: Recipient email address
        user_id: User ID who submitted the job
        job_name: Name/ID of the job
        user_name: Name of the user
        download_link: Link to download the results
    """
    
    # Load environment variables
    env_vars = load_env_file()
    
    # Email configuration
    smtp_host = env_vars.get('SMTP_HOST', 'smtp.gmail.com')
    smtp_port = int(env_vars.get('SMTP_PORT', '587'))
    smtp_user = env_vars.get('SMTP_USER', 'glycomap.simbiosys@gmail.com')
    smtp_password = env_vars.get('SMTP_PASSWORD', '')
    from_email = env_vars.get('FROM_EMAIL', smtp_user)
    
    # Calculate expiry date
    completion_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    expiry_date = (datetime.now() + timedelta(days=10)).strftime("%Y-%m-%d")
    
    # Create message
    msg = MIMEMultipart('alternative')
    msg['Subject'] = f'GlycoShield Analysis Complete - {job_name}'
    msg['From'] = f'GlycoShield Pipeline <{from_email}>'
    msg['To'] = to_email
    
    # Plain text version
    text_content = f"""
Dear {user_name},

Thank you for using the GlycoShield Web Server!

Your analysis job has been completed successfully, and the results are now available for download.

Job Information:
----------------
Job Name: {job_name}
User ID: {user_id}
Completion Time: {completion_time}

Download Your Results:
----------------------
Please click the following link to download your results:
{download_link}

⚠️ IMPORTANT: This download link will expire on {expiry_date} (10 days from now).
Please ensure you download your results before this date.

Results Include:
----------------
• Ensemble modeling output from AllosMod
• GEF (Geometric Exposure Factor) analysis results
• Processed glycan chain data
• Complete analysis reports and visualization files

Thank you for choosing GlycoShield Web Server for your glycoprotein analysis needs.
We hope our platform has been helpful for your research.

If you have any questions about your results or need assistance, please don't hesitate to contact the SimBioSys Lab support team.

Best regards,
GlycoShield Pipeline
SimBioSys Lab
Northeastern University

---
Citation: If you use GlycoShield in your research, please cite our publication.
"""

    # HTML version
    html_content = f"""
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #48c774 0%, #3ec46d 100%); 
                   color: white; padding: 20px; border-radius: 10px 10px 0 0; }}
        .content {{ background: #f9f9f9; padding: 20px; border-radius: 0 0 10px 10px; }}
        .details {{ background: white; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .detail-item {{ margin: 10px 0; }}
        .label {{ font-weight: bold; color: #48c774; }}
        .value {{ color: #555; }}
        .download-box {{ background: #e8f9f0; border: 2px solid #48c774; padding: 20px; 
                        border-radius: 8px; margin: 20px 0; text-align: center; }}
        .download-button {{ display: inline-block; background: #48c774; color: white; 
                           padding: 12px 30px; text-decoration: none; border-radius: 5px; 
                           font-weight: bold; font-size: 16px; }}
        .download-button:hover {{ background: #3ec46d; }}
        .warning {{ background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; 
                   margin: 15px 0; border-radius: 4px; }}
        .results-list {{ background: #f0f7ff; padding: 15px; border-radius: 8px; margin: 15px 0; }}
        .thank-you {{ background: #f0f9ff; padding: 15px; border-radius: 8px; 
                     text-align: center; margin: 20px 0; }}
        .footer {{ text-align: center; padding-top: 20px; color: #888; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>✅ GlycoShield Analysis Complete!</h2>
        </div>
        <div class="content">
            <p>Dear {user_name},</p>
            
            <div class="thank-you">
                <h3>🙏 Thank you for using the GlycoShield Web Server!</h3>
                <p>Your analysis job has been completed successfully.</p>
            </div>
            
            <div class="details">
                <h3>📊 Job Information</h3>
                <div class="detail-item">
                    <span class="label">Job Name:</span> 
                    <span class="value">{job_name}</span>
                </div>
                <div class="detail-item">
                    <span class="label">User ID:</span> 
                    <span class="value">{user_id}</span>
                </div>
                <div class="detail-item">
                    <span class="label">Completion Time:</span> 
                    <span class="value">{completion_time}</span>
                </div>
            </div>
            
            <div class="download-box">
                <h3>📥 Download Your Results</h3>
                <p>Your analysis results are ready for download:</p>
                <a href="{download_link}" class="download-button">Download Results</a>
            </div>
            
            <div class="warning">
                <strong>⚠️ Important Notice:</strong><br>
                This download link will expire on <strong>{expiry_date}</strong> (10 days from now).<br>
                Please ensure you download your results before this date.
            </div>
            
            <div class="results-list">
                <h3>📁 Your Results Include:</h3>
                <ul>
                    <li>Ensemble modeling output from AllosMod</li>
                    <li>GEF (Geometric Exposure Factor) analysis results</li>
                    <li>Processed glycan chain data</li>
                    <li>Complete analysis reports and visualization files</li>
                </ul>
            </div>
            
            <p>We hope our platform has been helpful for your research. If you have any questions 
            about your results or need assistance, please don't hesitate to contact the 
            SimBioSys Lab support team.</p>
            
            <p>Best regards,<br>
            <strong>GlycoShield Pipeline</strong><br>
            SimBioSys Lab<br>
            Northeastern University</p>
            
            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd;">
                <p style="font-size: 12px; color: #666;">
                    <strong>Citation:</strong> If you use GlycoShield in your research, please cite our publication.
                </p>
            </div>
        </div>
        <div class="footer">
            <p>This is an automated message from the GlycoShield Pipeline system.</p>
        </div>
    </div>
</body>
</html>
"""
    
    return send_email(msg, text_content, html_content, smtp_host, smtp_port, 
                     smtp_user, smtp_password, to_email)

def send_email(msg, text_content, html_content, smtp_host, smtp_port, 
               smtp_user, smtp_password, to_email):
    """Common email sending function"""
    
    # Attach parts
    part1 = MIMEText(text_content, 'plain')
    part2 = MIMEText(html_content, 'html')
    msg.attach(part1)
    msg.attach(part2)
    
    # Send email
    try:
        if not smtp_password:
            print("Warning: SMTP_PASSWORD not set in .env file. Email sending may fail.")
            print("Please add SMTP_PASSWORD to your .env file for email functionality.")
            return False
            
        with smtplib.SMTP(smtp_host, smtp_port) as server:
            server.starttls()
            server.login(smtp_user, smtp_password)
            server.send_message(msg)
            print(f"✓ Email sent successfully to {to_email}")
            return True
            
    except Exception as e:
        print(f"✗ Failed to send email to {to_email}: {str(e)}")
        print(f"  SMTP Configuration: {smtp_host}:{smtp_port}, User: {smtp_user}")
        return False

def main():
    """Main function to handle command line arguments"""
    parser = argparse.ArgumentParser(description='Send GlycoShield notification emails')
    parser.add_argument('template', choices=['submission', 'completion'], 
                       help='Email template type to use')
    parser.add_argument('email', help='Recipient email address')
    parser.add_argument('user_id', help='User ID who submitted the job')
    parser.add_argument('job_name', help='Name/ID of the job')
    parser.add_argument('user_name', help='Name of the user')
    parser.add_argument('--download-link', help='Download link for completion email', 
                       default='')
    
    args = parser.parse_args()
    
    # Validate email
    if '@' not in args.email:
        print(f"Error: Invalid email address: {args.email}")
        sys.exit(1)
    
    # Send appropriate email based on template
    if args.template == 'submission':
        success = send_submission_email(
            to_email=args.email,
            user_id=args.user_id,
            job_name=args.job_name,
            user_name=args.user_name
        )
    elif args.template == 'completion':
        if not args.download_link:
            print("Error: Download link is required for completion email")
            sys.exit(1)
        success = send_completion_email(
            to_email=args.email,
            user_id=args.user_id,
            job_name=args.job_name,
            user_name=args.user_name,
            download_link=args.download_link
        )
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
