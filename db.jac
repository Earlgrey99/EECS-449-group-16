"""Database access layer and schema management for Turso (libSQL / SQLite)."""

import hashlib;
import hmac;
import os;
import secrets;
import sqlite3;

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
    import libsql;
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
            city TEXT,
            linkedin TEXT,
            github TEXT,
            portfolio TEXT,
            auth_provider TEXT DEFAULT 'local',
            oauth_id TEXT,
            first_name TEXT,
            last_name TEXT,
            location TEXT,
            sector TEXT,
            job_titles TEXT,
            salary_min INTEGER,
            contract_type TEXT,
            cached_job_query TEXT,
            onboarding_completed INTEGER DEFAULT 0,
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
    has_auth_provider = any(column[1] == "auth_provider" for column in user_columns);
    if not has_auth_provider {
        db_conn.execute("ALTER TABLE users ADD COLUMN auth_provider TEXT DEFAULT 'local';");
    }
    has_oauth_id = any(column[1] == "oauth_id" for column in user_columns);
    if not has_oauth_id {
        db_conn.execute("ALTER TABLE users ADD COLUMN oauth_id TEXT;");
    }
    has_first_name = any(column[1] == "first_name" for column in user_columns);
    if not has_first_name {
        db_conn.execute("ALTER TABLE users ADD COLUMN first_name TEXT;");
    }
    has_last_name = any(column[1] == "last_name" for column in user_columns);
    if not has_last_name {
        db_conn.execute("ALTER TABLE users ADD COLUMN last_name TEXT;");
    }
    has_location = any(column[1] == "location" for column in user_columns);
    if not has_location {
        db_conn.execute("ALTER TABLE users ADD COLUMN location TEXT;");
    }
    has_sector = any(column[1] == "sector" for column in user_columns);
    if not has_sector {
        db_conn.execute("ALTER TABLE users ADD COLUMN sector TEXT;");
    }
    has_job_titles = any(column[1] == "job_titles" for column in user_columns);
    if not has_job_titles {
        db_conn.execute("ALTER TABLE users ADD COLUMN job_titles TEXT;");
    }
    has_salary_min = any(column[1] == "salary_min" for column in user_columns);
    if not has_salary_min {
        db_conn.execute("ALTER TABLE users ADD COLUMN salary_min INTEGER;");
    }
    has_contract_type = any(column[1] == "contract_type" for column in user_columns);
    if not has_contract_type {
        db_conn.execute("ALTER TABLE users ADD COLUMN contract_type TEXT;");
    }
    has_cached_job_query = any(column[1] == "cached_job_query" for column in user_columns);
    if not has_cached_job_query {
        db_conn.execute("ALTER TABLE users ADD COLUMN cached_job_query TEXT;");
    }
    for contact_column in ["city", "linkedin", "github", "portfolio"] {
        if not any(column[1] == contact_column for column in user_columns) {
            db_conn.execute(f"ALTER TABLE users ADD COLUMN {contact_column} TEXT;");
        }
    }
    has_onboarding_completed = any(column[1] == "onboarding_completed" for column in user_columns);
    if not has_onboarding_completed {
        db_conn.execute("ALTER TABLE users ADD COLUMN onboarding_completed INTEGER DEFAULT 0;");
    }
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_users_oauth ON users(auth_provider, oauth_id);");

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
            pay INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (resume_id) REFERENCES resumes(id) ON DELETE SET NULL
        );
    """);
    application_columns = db_conn.execute("PRAGMA table_info(applications);").fetchall();
    if not any(column[1] == "pay" for column in application_columns) {
        db_conn.execute("ALTER TABLE applications ADD COLUMN pay INTEGER;");
    }
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
    clean_name = name.strip();
    fn_val = None;
    ln_val = None;
    if " " in clean_name {
        parts = clean_name.split(" ", 1);
        fn_val = parts[0].strip();
        ln_val = parts[1].strip();
    } else {
        fn_val = clean_name;
    }
    user = create_user(
        name=clean_name,
        email=normalized_email,
        phone=phone.strip() if phone else None,
        password_hash=pwd_hash,
        auth_provider="local",
        oauth_id=None,
        first_name=fn_val,
        last_name=ln_val,
        onboarding_completed=0,
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
    auth_provider: str = "local",
    oauth_id: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
    location: str | None = None,
    sector: str | None = None,
    job_titles: str | None = None,
    salary_min: int | None = None,
    contract_type: str | None = None,
    cached_job_query: str | None = None,
    onboarding_completed: int = 0,
    conn: any = None
) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cols = ["name", "email", "phone", "password_hash", "auth_provider", "oauth_id"];
    vals: list[any] = [name, email, phone, password_hash, auth_provider, oauth_id];

    if first_name is not None {
        cols.append("first_name");
        vals.append(first_name);
    }
    if last_name is not None {
        cols.append("last_name");
        vals.append(last_name);
    }
    if location is not None {
        cols.append("location");
        vals.append(location);
    }
    if sector is not None {
        cols.append("sector");
        vals.append(sector);
    }
    if job_titles is not None {
        cols.append("job_titles");
        vals.append(job_titles);
    }
    if salary_min is not None {
        cols.append("salary_min");
        vals.append(salary_min);
    }
    if contract_type is not None {
        cols.append("contract_type");
        vals.append(contract_type);
    }
    if cached_job_query is not None {
        cols.append("cached_job_query");
        vals.append(cached_job_query);
    }
    if onboarding_completed is not None {
        cols.append("onboarding_completed");
        vals.append(onboarding_completed);
    }

    placeholders = ", ".join(["?" for _ in cols]);
    cur.execute(
        f"INSERT INTO users ({', '.join(cols)}) VALUES ({placeholders})",
        tuple(vals)
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

def get_user_by_oauth_id(
    oauth_id: str,
    auth_provider: str = "google",
    conn: any = None
) -> dict[str, any] | None {
    if not oauth_id {
        return None;
    }
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute(
        "SELECT * FROM users WHERE oauth_id = ? AND auth_provider = ?",
        (oauth_id, auth_provider)
    );
    row = cur.fetchone();
    return row_to_dict(cur, row);
}

def sync_oauth_user(
    email: str,
    name: str | None = None,
    oauth_id: str | None = None,
    auth_provider: str = "google",
    conn: any = None
) -> dict[str, any] {
    if not email or not email.strip() {
        raise ValueError("Email cannot be empty.");
    }
    clean_email = email.strip().lower();
    clean_name = name.strip() if name and name.strip() else clean_email.split("@")[0];
    db_conn = conn if conn is not None else get_db_connection();

    first_name_val = None;
    last_name_val = None;
    if clean_name and " " in clean_name {
        parts = clean_name.split(" ", 1);
        first_name_val = parts[0].strip();
        last_name_val = parts[1].strip();
    } else {
        first_name_val = clean_name;
    }

    existing_user: any = None;
    if oauth_id {
        existing_user = get_user_by_oauth_id(oauth_id, auth_provider=auth_provider, conn=db_conn);
    }
    if existing_user is None {
        existing_user = get_user_by_email(clean_email, conn=db_conn);
    }

    if existing_user is not None {
        user_id = existing_user["id"];
        updates = [];
        params = [];
        if (not existing_user.get("name") or existing_user.get("name") == clean_email.split("@")[0]) and clean_name {
            updates.append("name = ?");
            params.append(clean_name);
        }
        if oauth_id and not existing_user.get("oauth_id") {
            updates.append("oauth_id = ?");
            params.append(oauth_id);
        }
        if auth_provider and (not existing_user.get("auth_provider") or existing_user.get("auth_provider") == "local") {
            updates.append("auth_provider = ?");
            params.append(auth_provider);
        }
        if not existing_user.get("first_name") and first_name_val {
            updates.append("first_name = ?");
            params.append(first_name_val);
        }
        if not existing_user.get("last_name") and last_name_val {
            updates.append("last_name = ?");
            params.append(last_name_val);
        }
        if updates {
            params.append(user_id);
            cur = db_conn.cursor();
            cur.execute(f"UPDATE users SET {', '.join(updates)}, updated_at = CURRENT_TIMESTAMP WHERE id = ?", tuple(params));
            db_conn.commit();
            existing_user = get_user_by_id(user_id, conn=db_conn);
        }
        res = dict(existing_user);
        res.pop("password_hash", None);
        return res;
    }

    user = create_user(
        name=clean_name,
        email=clean_email,
        auth_provider=auth_provider,
        oauth_id=oauth_id,
        password_hash=None,
        first_name=first_name_val,
        last_name=last_name_val,
        onboarding_completed=0,
        conn=db_conn
    );
    res = dict(user);
    res.pop("password_hash", None);
    return res;
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
    auth_provider: str | None = None,
    oauth_id: str | None = None,
    first_name: str | None = None,
    last_name: str | None = None,
    location: str | None = None,
    sector: str | None = None,
    job_titles: str | None = None,
    salary_min: int | None = None,
    contract_type: str | None = None,
    cached_job_query: str | None = None,
    onboarding_completed: int | None = None,
    conn: any = None
) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    fields = [];
    vals: list[any] = [];
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
    if auth_provider is not None {
        fields.append("auth_provider = ?");
        vals.append(auth_provider);
    }
    if oauth_id is not None {
        fields.append("oauth_id = ?");
        vals.append(oauth_id);
    }
    if first_name is not None {
        fields.append("first_name = ?");
        vals.append(first_name);
    }
    if last_name is not None {
        fields.append("last_name = ?");
        vals.append(last_name);
    }
    if location is not None {
        fields.append("location = ?");
        vals.append(location);
    }
    if sector is not None {
        fields.append("sector = ?");
        vals.append(sector);
    }
    if job_titles is not None {
        fields.append("job_titles = ?");
        vals.append(job_titles);
    }
    if salary_min is not None {
        fields.append("salary_min = ?");
        vals.append(salary_min);
    }
    if contract_type is not None {
        fields.append("contract_type = ?");
        vals.append(contract_type);
    }
    if cached_job_query is not None {
        fields.append("cached_job_query = ?");
        vals.append(cached_job_query);
    }
    if onboarding_completed is not None {
        fields.append("onboarding_completed = ?");
        vals.append(onboarding_completed);
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

"""Save the details used to fill job applications. A blank value clears that detail."""
def save_contact_details(
    user_id: int,
    phone: str,
    city: str,
    linkedin: str,
    github: str,
    portfolio: str,
    conn: any = None
) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    db_conn.execute(
        "UPDATE users SET phone = ?, city = ?, linkedin = ?, github = ?, portfolio = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (phone, city, linkedin, github, portfolio, user_id)
    );
    db_conn.commit();
    return get_user_by_id(user_id, conn=db_conn);
}

def save_user_profile(
    user_id: int,
    first_name: str | None = None,
    last_name: str | None = None,
    location: str | None = None,
    sector: str | None = None,
    job_titles: str | None = None,
    salary_min: int | None = None,
    contract_type: str | None = None,
    cached_job_query: str | None = None,
    onboarding_completed: int = 1,
    conn: any = None
) -> dict[str, any] | None {
    full_name: str | None = None;
    if first_name or last_name {
        fn = (first_name or "").strip();
        ln = (last_name or "").strip();
        full_name = f"{fn} {ln}".strip() if (fn and ln) else (fn or ln);
    }
    user = update_user(
        user_id=user_id,
        name=full_name,
        first_name=first_name,
        last_name=last_name,
        location=location,
        sector=sector,
        job_titles=job_titles,
        salary_min=salary_min,
        contract_type=contract_type,
        cached_job_query=cached_job_query,
        onboarding_completed=onboarding_completed,
        conn=conn
    );
    if user is not None {
        res = dict(user);
        res.pop("password_hash", None);
        return res;
    }
    return None;
}

def get_user_profile(user_id: int, conn: any = None) -> dict[str, any] | None {
    user = get_user_by_id(user_id, conn=conn);
    if user is None {
        return None;
    }
    res = dict(user);
    res.pop("password_hash", None);
    return res;
}

def get_user_profile_by_email(email: str, conn: any = None) -> dict[str, any] | None {
    user = get_user_by_email(email, conn=conn);
    if user is None {
        return None;
    }
    res = dict(user);
    res.pop("password_hash", None);
    return res;
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
    cur.execute("SELECT * FROM resumes WHERE user_id = ? ORDER BY id DESC", (user_id,));
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
    vals: list[any] = [];
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
    pay: int | None = None,
    conn: any = None
) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("""
        INSERT INTO applications (
            user_id, job_title, company, resume_id, job_url, status, applied_date, notes, pay
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (user_id, job_title, company, resume_id, job_url, status, applied_date, notes, pay));
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
    vals: list[any] = [];
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

# --- Development Test User Helper ---

def ensure_test_user(conn: any = None) -> dict[str, any] {
    db_conn = conn if (conn is not None and not isinstance(conn, str)) else get_db_connection();
    init_db(conn=db_conn);
    test_email = "testuser@example.com";
    user = get_user_by_email(test_email, conn=db_conn);
    if user is not None {
        res = dict(user);
        res.pop("password_hash", None);
        return res;
    }
    user = create_user(
        name="Test User",
        email=test_email,
        phone=None,
        password_hash=hash_password("testpassword123"),
        auth_provider="local",
        oauth_id="testuser_dev",
        first_name="Test",
        last_name="User",
        location="Remote",
        sector="Technology",
        job_titles="Software Engineer",
        salary_min=100000,
        contract_type="Full-time",
        onboarding_completed=1,
        conn=db_conn
    );
    res = dict(user);
    res.pop("password_hash", None);
    return res;
}
