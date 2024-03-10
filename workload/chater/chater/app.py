from flask import Flask, render_template, redirect, url_for, flash, session, request, logging
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField
from wtforms.validators import InputRequired
from werkzeug.security import check_password_hash
from chater import chater_request
import os
import logging
import json
import sys
from datetime import datetime, timedelta

logging.basicConfig()

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY')
LAST_FAILED_ATTEMPT_TIME = None

# Load environment variables
USERNAME = os.getenv('USERNAME')
PASSWORD_HASH = os.getenv('PASSWORD_HASH')
SESSION_LIFETIME = int(os.getenv('SESSION_LIFETIME'))


class LoginForm(FlaskForm):
    username = StringField('Username', validators=[InputRequired()])
    password = PasswordField('Password', validators=[InputRequired()])


@app.before_request
def before_request():
    session.permanent = True
    app.permanent_session_lifetime = timedelta(hours=SESSION_LIFETIME)

    session.modified = True
    if 'logged_in' in session:
        last_activity_str = session.get('last_activity', None)

        if last_activity_str:
            # Check if last_activity_str is a string, if not, convert it
            if isinstance(last_activity_str, datetime):
                last_activity_str = last_activity_str.strftime('%Y-%m-%d %H:%M:%S')

            last_activity = datetime.strptime(last_activity_str, '%Y-%m-%d %H:%M:%S')
            if datetime.now() - last_activity > timedelta(hours=SESSION_LIFETIME):
                session.pop('logged_in', None)
                logging.info('logged out due to inactivity: %s', last_activity_str)
                flash('You have been logged out due to inactivity.')
                return redirect(url_for('login'))

        session['last_activity'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')


@app.route('/login', methods=['GET', 'POST'])
def login():
    global LAST_FAILED_ATTEMPT_TIME

    if LAST_FAILED_ATTEMPT_TIME and (datetime.now() - LAST_FAILED_ATTEMPT_TIME) < timedelta(seconds=30):
        logging.warning('Too many failed attempts')
        flash('Too many failed attempts. Please try again later.')
        return redirect(url_for('wait'))
    else:
        form = LoginForm()
        if form.validate_on_submit():
            if form.username.data == USERNAME and check_password_hash(PASSWORD_HASH, form.password.data):
                logging.info('Successful login by user: %s', form.username.data)
                session.permanent = True
                session['logged_in'] = True
                return redirect(url_for('chater'))
            else:
                LAST_FAILED_ATTEMPT_TIME = datetime.now()
                logging.warning('Failed login attempt for user: %s', form.username.data)
            flash('Wrong password', 'error')
        return render_template('login.html', form=form)


@app.route('/chater', methods=['GET', 'POST'])
def chater():
    if 'logged_in' in session:
        if request.method == 'POST':
            question = request.form['question']
            chater_response = chater_request(question)
            json_response = chater_response["response_content"]

            try:
                response_data = json.loads(json_response)
                possible_keys = [
                    'script', 'code', 'bash_script', 'python_code', 'javascript_code',
                    'java_code', 'csharp_code', 'php_code', 'ruby_code', 'swift_code',
                    'perl_code', 'sql_code', 'html_code', 'css_code', 'python_script',
                    'javascript_script', 'java_script', 'csharp_script', 'php_script',
                    'ruby_script', 'swift_script', 'perl_script', 'sql_script',
                    'html_script', 'css_script', 'Python_Script'
                ]
                script_content = next((response_data[key] for key in possible_keys if key in response_data), response_data)
                formatted_script = "\n".join(script_content) if isinstance(script_content, list) else script_content
            except json.JSONDecodeError:
                formatted_script = json_response

            new_response = {'question': chater_response["safe_question"], 'response': formatted_script, 'full': json_response}

            # Initialize 'responses' if not in session
            if 'responses' not in session:
                session['responses'] = []

            # Attempt to add new response, checking size constraint
            temp_responses = [new_response] + session['responses']
            while sys.getsizeof(temp_responses) > 3000:  # Roughly 4KB limit, adjust as needed
                temp_responses.pop()  # Remove oldest responses until within size limit

            session['responses'] = temp_responses[:3]  # Keep only the latest 10 responses

            return redirect(url_for('chater'))

        return render_template('chater.html', responses=session.get('responses', []))
    else:
        logging.warning('Unauthorized chater access attempt')
        flash('You need to log in to view this page')
        return redirect(url_for('login'))

@app.route('/clear_responses', methods=['GET'])
def clear_responses():
    if 'logged_in' in session:
        session['responses'] = []  # Clear the cached responses
        flash('Responses cleared successfully')
        return redirect(url_for('chater'))
    else:
        logging.warning('Unauthorized clear attempt')
        flash('You need to log in to perform this action')
        return redirect(url_for('login'))


@app.route('/logout')
def logout():
    logging.info('Logged out')
    session.pop('logged_in', None)
    return redirect(url_for('login'))


@app.route('/wait')
def wait():
    logging.warning('Waiting for next login attempt')
    return render_template('wait.html')


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    logger = logging.getLogger('werkzeug')
    logger.setLevel(logging.INFO)
app.run(host="0.0.0.0")
