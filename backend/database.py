import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

# Read settings from the .env beside this file
load_dotenv(Path(__file__).parent / ".env")


# Open a connection to PostgreSQL
def get_connection():
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )


# Run this check only when database.py is executed directly
if __name__ == "__main__":
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM public.users;")
            total_users = cursor.fetchone()[0]

            print("Database connected successfully!")
            print(f"Total users: {total_users}")