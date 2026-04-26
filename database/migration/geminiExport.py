import pyodbc
import csv
import os

# --- CONFIGURATION ---
# Replace with your actual credentials and driver name
CONN_STR = (
    "DRIVER={SQL Anywhere 12};"  # Check your exact driver name in ODBC Admin
    "ServerName=your_server_name;"
    "DatabaseName=your_db_name;"
    "UID=your_username;"
    "PWD=your_password;"
    "CommLinks=tcpip(host=localhost)" # Or your server IP
)

TABLES = [
    "customer", "item", "item_price", "citem", "ordr", 
    "ordr_detail", "ordr_returns", "pmt_detail", "ar", 
    "route", "route_stop", "code", "box", "box_shipped", 
    "sordr", "truck"
]

OUTPUT_DIR = "exported_csvs"

def clean_value(val):
    """
    Removes commas from string data to prevent CSV corruption.
    Also handles None/Null values and trailing spaces common in legacy DBs.
    """
    if val is None:
        return ""
    if isinstance(val, str):
        # Remove commas and strip whitespace
        return val.replace(",", "").strip()
    return val

def export_tables():
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    try:
        conn = pyodbc.connect(CONN_STR)
        cursor = conn.cursor()
        print("Connected to SQL Anywhere successfully.")

        for table in TABLES:
            file_path = os.path.join(OUTPUT_DIR, f"{table}.csv")
            print(f"Exporting {table}...")

            # Use a basic SELECT * for the export
            cursor.execute(f"SELECT * FROM {table}")
            
            # Fetch column names from cursor description
            headers = [column[0] for column in cursor.description]

            with open(file_path, 'w', newline='', encoding='utf-8') as f:
                # We use quoting=csv.QUOTE_MINIMAL but our clean_value 
                # function provides the primary protection.
                writer = csv.writer(f, delimiter=',', quoting=csv.QUOTE_MINIMAL)
                
                # Write Header row
                writer.writerow(headers)

                # Fetch and write rows one by one to save memory
                while True:
                    row = cursor.fetchone()
                    if not row:
                        break
                    
                    # Clean every field in the row
                    cleaned_row = [clean_value(field) for field in row]
                    writer.writerow(cleaned_row)

        print("\nAll exports completed successfully.")
        
    except pyodbc.Error as e:
        print(f"Database Error: {e}")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    export_tables()