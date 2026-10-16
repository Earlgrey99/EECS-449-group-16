"""Database access layer and schema management for Turso (libSQL / SQLite)."""

import hashlib;
import hmac;
import os;
import secrets;
import sqlite3;
import libsql;

def load_env_file(filepath: str = ".env") -> None {
    if not os.path.exists(filepath) {
        return;
    }
    with open(filepath, "r", encoding="utf-8") as f {
        for line in f {
            clean_line = line.strip();
            if not clean_line or clean_line.startswith("#") {
                continue;
            }
            if "=" in clean_line {
                parts = clean_line.split("=", 1);
                key = parts[0].strip();
                value = parts[1].strip().strip("\"").strip("'");
                if key not in os.environ {
                    os.environ[key] = value;
                }
            }
        }
    }
}

def get_db_connection(
    database_url: str | None = None,
    auth_token: str | None = None
) -> any {
    load_env_file();
    url = database_url or os.environ.get("TURSO_DATABASE_URL") or os.environ.get("TURSO_URL");
    token = auth_token or os.environ.get("TURSO_AUTH_TOKEN") or os.environ.get("TURSO_TOKEN");

    if not url {
        raise ValueError(
            "Database URL must be provided via argument, TURSO_DATABASE_URL or TURSO_URL env var."
        );
    }

    if url == ":memory:" or url.startswith("file:") or url.endswith(".db") {
        conn = sqlite3.connect(url);
        conn.execute("PRAGMA foreign_keys = ON;");
        return conn;
    }

    conn = libsql.connect(database=url, auth_token=token);
    return conn;
}

def init_db(conn: any = None) {
    db_conn = conn if conn is not None else get_db_connection();

    # Users table
    db_conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT,
            phone TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """);
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);");
    user_columns = db_conn.execute("PRAGMA table_info(users);").fetchall();
    has_password_hash = any(column[1] == "password_hash" for column in user_columns);
    if not has_password_hash {
        db_conn.execute("ALTER TABLE users ADD COLUMN password_hash TEXT;");
    }

    # Resumes table
    db_conn.execute("""
        CREATE TABLE IF NOT EXISTS resumes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            content TEXT,
            file_path TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    """);
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_resumes_user ON resumes(user_id);");

    # Applications table
    db_conn.execute("""
        CREATE TABLE IF NOT EXISTS applications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            job_title TEXT NOT NULL,
            company TEXT NOT NULL,
            resume_id INTEGER,
            job_url TEXT,
            status TEXT DEFAULT 'applied',
            applied_date TEXT,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (resume_id) REFERENCES resumes(id) ON DELETE SET NULL
        );
    """);
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_apps_user ON applications(user_id);");
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_apps_status ON applications(status);");

    db_conn.commit();
}

def row_to_dict(cur: any, row: any) -> dict[str, any] | None {
    if row is None {
        return None;
    }
    cols = [desc[0] for desc in cur.description];
    return dict(zip(cols, row));
}

# --- Password & Authentication Helpers ---

def hash_password(password: str) -> str {
    salt = secrets.token_hex(16);
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000);
    return f"{salt}${dk.hex()}";
}

def verify_password(password: str, password_hash: str) -> bool {
    if not password_hash or "$" not in password_hash {
        return False;
    }
    parts = password_hash.split("$", 1);
    salt = parts[0];
    stored_hash = parts[1];
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000);
    return hmac.compare_digest(dk.hex(), stored_hash);
}

def generate_session_token -> str {
    return secrets.token_hex(24);
}

def register_user(
    name: str,
    email: str,
    password: str,
    phone: str | None = None,
    conn: any = None
) -> dict[str, any] {
    if not name or not name.strip() {
        raise ValueError("Name cannot be empty.");
    }
    if not email or not email.strip() {
        raise ValueError("Email cannot be empty.");
    }
    if not password or not password.strip() {
        raise ValueError("Password cannot be empty.");
    }
    normalized_email = email.strip().lower();
    db_conn = conn if conn is not None else get_db_connection();
    existing = get_user_by_email(normalized_email, conn=db_conn);
    if existing is not None {
        raise ValueError(f"User with email '{normalized_email}' already exists.");
    }
    pwd_hash = hash_password(password);
    user = create_user(
        name=name.strip(),
        email=normalized_email,
        phone=phone.strip() if phone else None,
        password_hash=pwd_hash,
        conn=db_conn
    );
    res = dict(user);
    res.pop("password_hash", None);
    return res;
}

def authenticate_user(email: str, password: str, conn: any = None) -> dict[str, any] | None {
    if not email or not password {
        return None;
    }
    normalized_email = email.strip().lower();
    db_conn = conn if conn is not None else get_db_connection();
    user = get_user_by_email(normalized_email, conn=db_conn);
    if user is None {
        return None;
    }
    pwd_hash = user.get("password_hash");
    if not pwd_hash {
        return None;
    }
    if not verify_password(password, pwd_hash) {
        return None;
    }
    res = dict(user);
    res.pop("password_hash", None);
    res["session_token"] = generate_session_token();
    return res;
}

# --- Users CRUD ---

def create_user(
    name: str,
    email: str,
    phone: str | None = None,
    password_hash: str | None = None,
    conn: any = None
) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute(
        "INSERT INTO users (name, email, phone, password_hash) VALUES (?, ?, ?, ?)",
        (name, email, phone, password_hash)
    );
    db_conn.commit();
    user_id = cur.lastrowid;
    user = get_user_by_id(user_id, conn=db_conn);
    if user is None {
        raise RuntimeError("Failed to retrieve created user.");
    }
    return user;
}

def get_user_by_id(user_id: int, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM users WHERE id = ?", (user_id,));
    row = cur.fetchone();
    return row_to_dict(cur, row);
}

def get_user_by_email(email: str, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM users WHERE email = ?", (email,));
    row = cur.fetchone();
    return row_to_dict(cur, row);
}

def list_users(conn: any = None) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM users ORDER BY id ASC");
    rows = cur.fetchall();
    cols = [desc[0] for desc in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_user(
    user_id: int,
    name: str | None = None,
    email: str | None = None,
    phone: str | None = None,
    password_hash: str | None = None,
    conn: any = None
) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    fields = [];
    vals = [];
    if name is not None {
        fields.append("name = ?");
        vals.append(name);
    }
    if email is not None {
        fields.append("email = ?");
        vals.append(email);
    }
    if phone is not None {
        fields.append("phone = ?");
        vals.append(phone);
    }
    if password_hash is not None {
        fields.append("password_hash = ?");
        vals.append(password_hash);
    }
    if not fields {
        return get_user_by_id(user_id, conn=db_conn);
    }
    fields.append("updated_at = CURRENT_TIMESTAMP");
    vals.append(user_id);
    sql = f"UPDATE users SET {', '.join(fields)} WHERE id = ?";
    cur.execute(sql, tuple(vals));
    db_conn.commit();
    return get_user_by_id(user_id, conn=db_conn);
}

def delete_user(user_id: int, conn: any = None) -> bool {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("DELETE FROM users WHERE id = ?", (user_id,));
    db_conn.commit();
    return cur.rowcount > 0;
}

# --- Resumes CRUD ---

def create_resume(
    user_id: int,
    title: str,
    content: str | None = None,
    file_path: str | None = None,
    conn: any = None
) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute(
        "INSERT INTO resumes (user_id, title, content, file_path) VALUES (?, ?, ?, ?)",
        (user_id, title, content, file_path)
    );
    db_conn.commit();
    resume_id = cur.lastrowid;
    resume = get_resume_by_id(resume_id, conn=db_conn);
    if resume is None {
        raise RuntimeError("Failed to retrieve created resume.");
    }
    return resume;
}

def get_resume_by_id(resume_id: int, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM resumes WHERE id = ?", (resume_id,));
    row = cur.fetchone();
    return row_to_dict(cur, row);
}

def list_resumes_by_user(user_id: int, conn: any = None) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM resumes WHERE user_id = ? ORDER BY id ASC", (user_id,));
    rows = cur.fetchall();
    cols = [desc[0] for desc in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_resume(
    resume_id: int,
    title: str | None = None,
    content: str | None = None,
    file_path: str | None = None,
    conn: any = None
) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    fields = [];
    vals = [];
    if title is not None {
        fields.append("title = ?");
        vals.append(title);
    }
    if content is not None {
        fields.append("content = ?");
        vals.append(content);
    }
    if file_path is not None {
        fields.append("file_path = ?");
        vals.append(file_path);
    }
    if not fields {
        return get_resume_by_id(resume_id, conn=db_conn);
    }
    fields.append("updated_at = CURRENT_TIMESTAMP");
    vals.append(resume_id);
    sql = f"UPDATE resumes SET {', '.join(fields)} WHERE id = ?";
    cur.execute(sql, tuple(vals));
    db_conn.commit();
    return get_resume_by_id(resume_id, conn=db_conn);
}

def delete_resume(resume_id: int, conn: any = None) -> bool {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("DELETE FROM resumes WHERE id = ?", (resume_id,));
    db_conn.commit();
    return cur.rowcount > 0;
}

# --- Applications CRUD ---

def create_application(
    user_id: int,
    job_title: str,
    company: str,
    resume_id: int | None = None,
    job_url: str | None = None,
    status: str = "applied",
    applied_date: str | None = None,
    notes: str | None = None,
    conn: any = None
) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("""
        INSERT INTO applications (
            user_id, job_title, company, resume_id, job_url, status, applied_date, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (user_id, job_title, company, resume_id, job_url, status, applied_date, notes));
    db_conn.commit();
    app_id = cur.lastrowid;
    app = get_application_by_id(app_id, conn=db_conn);
    if app is None {
        raise RuntimeError("Failed to retrieve created application.");
    }
    return app;
}

def get_application_by_id(app_id: int, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM applications WHERE id = ?", (app_id,));
    row = cur.fetchone();
    return row_to_dict(cur, row);
}

def list_applications_by_user(
    user_id: int,
    status: str | None = None,
    conn: any = None
) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    if status {
        cur.execute(
            "SELECT * FROM applications WHERE user_id = ? AND status = ? ORDER BY id ASC",
            (user_id, status)
        );
    } else {
        cur.execute(
            "SELECT * FROM applications WHERE user_id = ? ORDER BY id ASC",
            (user_id,)
        );
    }
    rows = cur.fetchall();
    cols = [desc[0] for desc in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_application(
    app_id: int,
    job_title: str | None = None,
    company: str | None = None,
    resume_id: int | None = None,
    job_url: str | None = None,
    status: str | None = None,
    applied_date: str | None = None,
    notes: str | None = None,
    conn: any = None
) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    fields = [];
    vals = [];
    if job_title is not None {
        fields.append("job_title = ?");
        vals.append(job_title);
    }
    if company is not None {
        fields.append("company = ?");
        vals.append(company);
    }
    if resume_id is not None {
        fields.append("resume_id = ?");
        vals.append(resume_id);
    }
    if job_url is not None {
        fields.append("job_url = ?");
        vals.append(job_url);
    }
    if status is not None {
        fields.append("status = ?");
        vals.append(status);
    }
    if applied_date is not None {
        fields.append("applied_date = ?");
        vals.append(applied_date);
    }
    if notes is not None {
        fields.append("notes = ?");
        vals.append(notes);
    }
    if not fields {
        return get_application_by_id(app_id, conn=db_conn);
    }
    fields.append("updated_at = CURRENT_TIMESTAMP");
    vals.append(app_id);
    sql = f"UPDATE applications SET {', '.join(fields)} WHERE id = ?";
    cur.execute(sql, tuple(vals));
    db_conn.commit();
    return get_application_by_id(app_id, conn=db_conn);
}

def delete_application(app_id: int, conn: any = None) -> bool {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("DELETE FROM applications WHERE id = ?", (app_id,));
    db_conn.commit();
    return cur.rowcount > 0;
}
