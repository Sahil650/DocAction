from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from flask_mail import Mail, Message
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from database import db
from models import User
import os
import secrets
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)
CORS(app)

# Database Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///local_fallback.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# SMTP Configuration (Using Gmail)
app.config['MAIL_SERVER'] = os.environ.get('MAIL_SERVER', 'smtp.gmail.com')
app.config['MAIL_PORT'] = int(os.environ.get('MAIL_PORT', 587))
app.config['MAIL_USE_TLS'] = os.environ.get('MAIL_USE_TLS', 'True').lower() == 'true'
app.config['MAIL_USE_SSL'] = os.environ.get('MAIL_USE_SSL', 'False').lower() == 'true'
app.config['MAIL_USERNAME'] = os.environ.get('MAIL_USERNAME')
app.config['MAIL_PASSWORD'] = os.environ.get('MAIL_PASSWORD')
app.config['MAIL_DEFAULT_SENDER'] = os.environ.get('MAIL_DEFAULT_SENDER', 'DocAction Support <noreply@docaction.com>')

mail = Mail(app)

# JWT Configuration
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', 'dev-secret-key-fallback')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(days=7)
jwt = JWTManager(app)

db.init_app(app)

@app.route('/', methods=['GET'])
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'online',
        'message': 'DocAction Backend is running!',
        'routes': ['/register', '/login', '/profile', '/forgot-password', '/health']
    }), 200

# Create tables before first request
with app.app_context():
    try:
        db.create_all()
    except Exception as e:
        print(f"Failed to create database tables. Ensure PostgreSQL is running and database exists. Error: {e}")

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'message': 'Email and password are required'}), 400

    existing_user = User.query.filter_by(email=email).first()
    if existing_user:
        return jsonify({'message': 'User already exists'}), 409

    hashed_password = generate_password_hash(password)
    new_user = User(email=email, password_hash=hashed_password)
    
    try:
        db.session.add(new_user)
        db.session.commit()
        return jsonify({'message': 'User registered successfully'}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({'message': 'Error registering user'}), 500

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'message': 'Email and password are required'}), 400

    user = User.query.filter_by(email=email).first()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify({'message': 'Invalid email or password'}), 401

    access_token = create_access_token(identity=str(user.id))
    return jsonify({
        'message': 'Login successful',
        'token': access_token,
        'user': user.to_dict()
    }), 200

@app.route('/forgot-password', methods=['POST'])
def forgot_password():
    data = request.get_json()
    email = data.get('email')

    if not email:
        return jsonify({'message': 'Email is required'}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        return jsonify({'message': 'No account found with this email'}), 404

    # Create a unique reset token
    reset_token = secrets.token_urlsafe(32)
    user.reset_token = reset_token
    user.reset_token_expiry = datetime.utcnow() + timedelta(hours=1)
    
    try:
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return jsonify({'message': 'Error generating reset token'}), 500
    
    # Use environment variable for base URL so it works on real devices
    base_url = os.environ.get('BASE_URL', 'http://127.0.0.1:5000')
    reset_url = f"{base_url}/reset-password/{reset_token}"

    try:
        print(f"Attempting to send email to: {email}")
        msg = Message("Action Required: Reset your DocAction password",
                      recipients=[email])
        
        msg.body = f"Hello,\n\nWe received a request to reset the password for your DocAction account. You can reset it by visiting the link below:\n\n{reset_url}\n\nThis link will expire in 60 minutes for your security.\n\nBest regards,\nThe DocAction Team"
        
        msg.html = f"""
        <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px; color: #333; line-height: 1.6;">
            <div style="text-align: center; margin-bottom: 30px;">
                <h1 style="color: #1A10A8; margin: 0; font-size: 28px;">DocAction</h1>
                <p style="color: #666; margin-top: 5px; font-size: 14px;">Smart • Secure • Fast</p>
            </div>
            
            <div style="background-color: #ffffff; padding: 30px; border-radius: 12px; border: 1px solid #f0f0f0; box-shadow: 0 4px 10px rgba(0,0,0,0.03);">
                <p style="font-size: 16px; margin-top: 0;">Hello,</p>
                <p style="font-size: 16px;">We received a request to reset your <strong>DocAction</strong> account password. Click the button below to choose a new one:</p>
                
                <div style="text-align: center; margin: 35px 0;">
                    <a href="{reset_url}" style="background-color: #1A10A8; color: #ffffff; padding: 14px 30px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block; font-size: 16px; box-shadow: 0 4px 6px rgba(26, 16, 168, 0.2);">Reset My Password</a>
                </div>
                
                <p style="font-size: 14px; color: #777; margin-bottom: 0;">If you didn't request this change, you can safely ignore this email. Your password will remain unchanged.</p>
            </div>
            
            <div style="text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee;">
                <p style="color: #999; font-size: 12px; margin-bottom: 5px;">&copy; 2026 DocAction AI. All rights reserved.</p>
                <p style="color: #bbb; font-size: 11px;">This is an automated security notification. Please do not reply to this email.</p>
            </div>
        </div>
        """
        
        mail.send(msg)
        print("Email sent successfully!")
        return jsonify({
            'message': f'A password reset link has been sent to {email}'
        }), 200
    except Exception as e:
        import traceback
        print(f"CRITICAL ERROR sending email: {str(e)}")
        print(traceback.format_exc())
        return jsonify({'message': f'Failed to send email: {str(e)}'}), 500

@app.route('/reset-password/<token>', methods=['GET'])
def reset_password_page(token):
    # This serves a simple HTML page to the user's browser
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Reset Password - DocAction</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {{ font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background-color: #f5f5f5; }}
            .card {{ background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); width: 100%; max-width: 400px; }}
            h2 {{ color: #1A10A8; margin-top: 0; text-align: center; }}
            input {{ width: 100%; padding: 12px; margin: 10px 0; border: 1px solid #ddd; border-radius: 5px; box-sizing: border-box; }}
            button {{ width: 100%; padding: 12px; background-color: #1A10A8; color: white; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; }}
            .message {{ margin-top: 15px; text-align: center; font-size: 14px; }}
        </style>
    </head>
    <body>
        <div class="card">
            <h2>Reset Your Password</h2>
            <p style="text-align: center; color: #666; font-size: 14px;">Enter a new password for your account.</p>
            <form action="/reset-password/{token}" method="POST">
                <input type="password" name="password" placeholder="New Password" required minlength="6">
                <button type="submit">Update Password</button>
            </form>
        </div>
    </body>
    </html>
    """

@app.route('/reset-password/<token>', methods=['POST'])
def handle_reset_password(token):
    try:
        # Find user by reset token
        user = User.query.filter_by(reset_token=token).first()
        
        if not user:
            raise Exception("Invalid token")
            
        # Check expiry
        if user.reset_token_expiry < datetime.utcnow():
            raise Exception("Token expired")
        
        # Get password from form data or JSON
        if request.is_json:
            password = request.get_json().get('password')
        else:
            password = request.form.get('password')
 
        if not password:
            return jsonify({'message': 'Password is required'}), 400
 
        user.password_hash = generate_password_hash(password)
        # Clear token after use (Single-use security)
        user.reset_token = None
        user.reset_token_expiry = None
        
        db.session.commit()
 
        return """
        <div style="text-align: center; font-family: sans-serif; padding: 50px;">
            <h2 style="color: #1A10A8;">Success!</h2>
            <p>Your password has been updated successfully.</p>
            <p>You can now log in to the DocAction app with your new password.</p>
        </div>
        """, 200
    except Exception as e:
        return f"""
        <div style="text-align: center; font-family: sans-serif; padding: 50px;">
            <h2 style="color: #d32f2f;">Link Expired</h2>
            <p>This password reset link is invalid or has expired.</p>
            <p>Please request a new reset link from the app.</p>
        </div>
        """, 400

@app.route('/profile', methods=['GET'])
@jwt_required()
def profile():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return jsonify({'message': 'User not found'}), 404
        
    return jsonify(user.to_dict()), 200

@app.route('/profile', methods=['PUT'])
@jwt_required()
def update_profile():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return jsonify({'message': 'User not found'}), 404
        
    data = request.get_json()
    if 'name' in data:
        user.name = data['name']
        
    try:
        db.session.commit()
        return jsonify({
            'message': 'Profile updated successfully',
            'user': user.to_dict()
        }), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'message': f'Error updating profile: {str(e)}'}), 500

@app.route('/profile-picture', methods=['POST'])
@jwt_required()
def upload_profile_picture():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if not user:
        return jsonify({'message': 'User not found'}), 404
        
    if 'image' not in request.files:
        return jsonify({'message': 'No image file provided'}), 400
        
    file = request.files['image']
    if file.filename == '':
        return jsonify({'message': 'No image selected'}), 400
        
    if file:
        filename = secure_filename(f"user_{user_id}_{file.filename}")
        upload_folder = os.path.join(app.root_path, 'uploads', 'profiles')
        os.makedirs(upload_folder, exist_ok=True)
        file_path = os.path.join(upload_folder, filename)
        file.save(file_path)
        
        # Store as relative path so clients can append their own base URL (fixes localhost vs 10.0.2.2 issues)
        picture_url = f"/uploads/profiles/{filename}"
        
        user.profile_picture_url = picture_url
        try:
            db.session.commit()
            return jsonify({
                'message': 'Profile picture updated successfully',
                'profile_picture_url': picture_url,
                'user': user.to_dict()
            }), 200
        except Exception as e:
            db.session.rollback()
            return jsonify({'message': f'Error saving picture to database: {str(e)}'}), 500

@app.route('/uploads/profiles/<filename>')
def uploaded_profile_file(filename):
    return send_from_directory(os.path.join(app.root_path, 'uploads', 'profiles'), filename)

if __name__ == '__main__':
    # Disable debug mode for production safety
    app.run(debug=False, host='0.0.0.0', port=5000)
