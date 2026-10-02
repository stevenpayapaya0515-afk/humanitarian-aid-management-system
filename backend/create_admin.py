from getpass import getpass

from core.security import hash_password
from database import get_connection


def create_admin():
    full_name = input("Full name: ").strip()
    email = input("Admin email: ").strip().lower()
    password = getpass("Admin password: ")
    confirm_password = getpass("Confirm password: ")

    # Check required details
    if not full_name or not email:
        print("Full name and email are required.")
        return

    if len(full_name) > 100 or len(email) > 254:
        print("Full name or email is too long.")
        return

    # Basic email format check; this does not verify ownership
    if email.count("@") != 1 or any(char.isspace() for char in email):
        print("Enter a valid email address.")
        return

    email_name, email_domain = email.split("@")

    if not email_name or "." not in email_domain or email_domain.startswith(".") or email_domain.endswith("."):
        print("Enter a valid email address.")
        return

    if len(password) < 12:
        print("Use a password with at least 12 characters.")
        return

    if password != confirm_password:
        print("Passwords do not match.")
        return

    with get_connection() as connection:
        with connection.cursor() as cursor:
            # Check if the email already exists
            cursor.execute(
                "SELECT user_id FROM public.users WHERE email = %s;",
                (email,),
            )

            if cursor.fetchone() is not None:
                print("Email already exists. No account was changed.")
                return

            # Save the account with a hashed password
            cursor.execute(
                """
                INSERT INTO public.users
                    (full_name, email, password_hash, role)
                VALUES (%s, %s, %s, %s);
                """,
                (full_name, email, hash_password(password), "Admin"),
            )

    print("Admin account created successfully!")


if __name__ == "__main__":
    create_admin()