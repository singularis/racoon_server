from flask import Flask, render_template, redirect, url_for, flash, session, request
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField
from wtforms.validators import InputRequired
from werkzeug.security import check_password_hash
from chater import chater_request
import os
import logging
import json
from datetime import datetime, timedelta

logging.basicConfig()

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY')
LAST_FAILED_ATTEMPT_TIME = None

# Load environment variables
USERNAME = os.getenv('USERNAME')
PASSWORD_HASH = os.getenv('PASSWORD_HASH')


class LoginForm(FlaskForm):
    username = StringField('Username', validators=[InputRequired()])
    password = PasswordField('Password', validators=[InputRequired()])


@app.before_request
def before_request():
    session.permanent = True
    app.permanent_session_lifetime = timedelta(hours=1)

    session.modified = True
    if 'logged_in' in session:
        last_activity_str = session.get('last_activity', None)

        if last_activity_str:
            # Check if last_activity_str is a string, if not, convert it
            if isinstance(last_activity_str, datetime):
                last_activity_str = last_activity_str.strftime('%Y-%m-%d %H:%M:%S')

            last_activity = datetime.strptime(last_activity_str, '%Y-%m-%d %H:%M:%S')
            if datetime.now() - last_activity > timedelta(hours=1):
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
                # if form.username.data == USERNAME and "test" == form.password.data:
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
            json_response = chater_request(question)

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
                script_content = None
                for key in possible_keys:
                    if key in response_data:
                        script_content = response_data[key]
                        break
                if script_content is None:
                    script_content = response_data
                formatted_script = "\n".join(script_content) if isinstance(script_content, list) else script_content
            except json.JSONDecodeError:
                formatted_script = json_response

            # Store the formatted script
            if 'responses' not in session:
                session['responses'] = []
            session['responses'].insert(0, {'question': question, 'response': formatted_script, 'full': json_response})
            session['responses'] = session['responses'][:10]

            return render_template('chater.html', responses=session['responses'])
        return render_template('chater.html', responses=session.get('responses', []))
    else:
        logging.warning('Unauthorized chater access attempt')
        flash('You need to log in to view this page')
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
