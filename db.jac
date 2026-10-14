"""Database access layer and schema management for Turso (libSQL / SQLite)."""

import os;
import sqlite3;
import libsql;

def load_env_file(filepath: str = ".env") {
    if os.path.exists(filepath) {
        try {
            with open(filepath, "r") as f {
                for raw_line in f {
                    line = raw_line.strip();
                    if line and not line.startswith("#") and "=" in line {
                        (k, v) = line.split("=", 1);
                        key_name = k.strip();
                        val = v.strip().strip("'").strip("\"");
                        if key_name and key_name not in os.environ {
                            os.environ[key_name] = val;
                        }
                    }
                }
            }
        } except Exception {
            # Silently ignore .env read issues
        }
    }
}

def get_db_connection(database_url: str | None = None, auth_token: str | None = None) -> any {
    load_env_file();
    url = database_url or os.environ.get("TURSO_DATABASE_URL") or os.environ.get("TURSO_URL");
    token = auth_token or os.environ.get("TURSO_AUTH_TOKEN") or os.environ.get("TURSO_TOKEN");

    if not url {
        raise ValueError("Database URL must be provided via TURSO_DATABASE_URL/TURSO_URL env var, .env file, or --url argument.");
    }

    if url.startswith("libsql://") or url.startswith("http://") or url.startswith("https://") {
        conn = libsql.connect(url, auth_token=token);
    } else {
        try {
            conn = libsql.connect(url);
        } except Exception {
            conn = sqlite3.connect(url);
        }
    }
    conn.execute("PRAGMA foreign_keys = ON;");
    return conn;
}

def init_db(conn: any = None) {
    db_conn = conn if conn is not None else get_db_connection();

    db_conn.execute("PRAGMA foreign_keys = ON;");

    # Users table
    db_conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            phone TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """);
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);");

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
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_resumes_user_id ON resumes(user_id);");

    # Applications table
    db_conn.execute("""
        CREATE TABLE IF NOT EXISTS applications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            resume_id INTEGER,
            job_title TEXT NOT NULL,
            company TEXT NOT NULL,
            job_url TEXT,
            status TEXT DEFAULT 'applied',
            applied_date TEXT,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (resume_id) REFERENCES resumes(id) ON DELETE SET NULL
        );
    """);
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_applications_user_id ON applications(user_id);");
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_applications_resume_id ON applications(resume_id);");
    db_conn.execute("CREATE INDEX IF NOT EXISTS idx_applications_status ON applications(status);");

    db_conn.commit();
}

def row_to_dict(cur: any, row: any) -> dict[str, any] | None {
    if row is None {
        return None;
    }
    cols = [col[0] for col in cur.description];
    return dict(zip(cols, row));
}

# --- Users CRUD ---

def create_user(name: str, email: str, phone: str | None = None, conn: any = None) -> dict[str, any] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute(
        "INSERT INTO users (name, email, phone) VALUES (?, ?, ?)",
        (name, email, phone)
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
    return row_to_dict(cur, cur.fetchone());
}

def get_user_by_email(email: str, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM users WHERE email = ?", (email,));
    return row_to_dict(cur, cur.fetchone());
}

def list_users(conn: any = None) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM users ORDER BY id ASC");
    rows = cur.fetchall();
    if not rows {
        return [];
    }
    cols = [col[0] for col in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_user(user_id: int, name: str | None = None, email: str | None = None, phone: str | None = None, conn: any = None) -> dict[str, any] | None {
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
    if not fields {
        return get_user_by_id(user_id, conn=db_conn);
    }
    fields.append("updated_at = CURRENT_TIMESTAMP");
    vals.append(user_id);
    cur.execute(f"UPDATE users SET {', '.join(fields)} WHERE id = ?", tuple(vals));
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

def create_resume(user_id: int, title: str, content: str | None = None, file_path: str | None = None, conn: any = None) -> dict[str, any] {
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
    return row_to_dict(cur, cur.fetchone());
}

def list_resumes_by_user(user_id: int, conn: any = None) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM resumes WHERE user_id = ? ORDER BY id ASC", (user_id,));
    rows = cur.fetchall();
    if not rows {
        return [];
    }
    cols = [col[0] for col in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_resume(resume_id: int, title: str | None = None, content: str | None = None, file_path: str | None = None, conn: any = None) -> dict[str, any] | None {
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
    cur.execute(f"UPDATE resumes SET {', '.join(fields)} WHERE id = ?", tuple(vals));
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
    cur.execute(
        """
        INSERT INTO applications (user_id, resume_id, job_title, company, job_url, status, applied_date, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (user_id, resume_id, job_title, company, job_url, status, applied_date, notes)
    );
    db_conn.commit();
    app_id = cur.lastrowid;
    app = get_application_by_id(app_id, conn=db_conn);
    if app is None {
        raise RuntimeError("Failed to retrieve created application.");
    }
    return app;
}

def get_application_by_id(application_id: int, conn: any = None) -> dict[str, any] | None {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("SELECT * FROM applications WHERE id = ?", (application_id,));
    return row_to_dict(cur, cur.fetchone());
}

def list_applications_by_user(user_id: int, status: str | None = None, conn: any = None) -> list[dict[str, any]] {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    if status is not None {
        cur.execute("SELECT * FROM applications WHERE user_id = ? AND status = ? ORDER BY id ASC", (user_id, status));
    } else {
        cur.execute("SELECT * FROM applications WHERE user_id = ? ORDER BY id ASC", (user_id,));
    }
    rows = cur.fetchall();
    if not rows {
        return [];
    }
    cols = [col[0] for col in cur.description];
    return [dict(zip(cols, r)) for r in rows];
}

def update_application(
    application_id: int,
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
        return get_application_by_id(application_id, conn=db_conn);
    }
    vals.append(application_id);
    cur.execute(f"UPDATE applications SET {', '.join(fields)} WHERE id = ?", tuple(vals));
    db_conn.commit();
    return get_application_by_id(application_id, conn=db_conn);
}

def delete_application(application_id: int, conn: any = None) -> bool {
    db_conn = conn if conn is not None else get_db_connection();
    cur = db_conn.cursor();
    cur.execute("DELETE FROM applications WHERE id = ?", (application_id,));
    db_conn.commit();
    return cur.rowcount > 0;
}
