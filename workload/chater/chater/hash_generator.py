from werkzeug.security import generate_password_hash

# Prompt the user for a password
password_to_hash = input("Enter your password: ")

# Generate the hash of the entered password
hashed_password = generate_password_hash(password_to_hash, method='pbkdf2:sha256')

# Print the hashed password
print("Hashed Password:", hashed_password)
