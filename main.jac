"""EECS-449-group-16 - a command-line Jac app.

Subcommands are declared with `argparse` and dispatched from the entry block.
Add one by registering a parser in `build_parser` and a branch in `main`.

    jac run main.jac -- greet Ada --shout
    jac run main.jac -- fetch "software engineer" -n 5
    jac run main.jac -- fetch "software engineer" -n 5 -l "New York"
    jac run main.jac -- db-init
    jac run main.jac -- signup --name "Ada Lovelace" --email "ada@example.com"
    jac run main.jac -- login --email "ada@example.com"
"""

import argparse;
import csv;
import datetime;
import getpass;
import json;
import os;
import sys;
import tempfile;
import urllib.error;
import urllib.request;
import from unittest.mock { MagicMock, patch }
import from db {
    get_db_connection,
    load_env_file,
    init_db,
    hash_password,
    verify_password,
    register_user,
    authenticate_user,
    create_user,
    get_user_by_id,
    get_user_by_email,
    list_users,
    update_user,
    delete_user,
    create_resume,
    get_resume_by_id,
    list_resumes_by_user,
    update_resume,
    delete_resume,
    create_application,
    get_application_by_id,
    list_applications_by_user,
    update_application,
    delete_application
}

glob APPLICATION_COLUMNS: list[str] = [
    "Company name",
    "Job title",
    "Date Applied",
    "Description",
    "Pay available",
    "Resume PDF used",
    "Cover letter",
];
glob application_table: list[dict[str, str | int]] = [];

def greet(name: str, shout: bool = False) -> str {
    message = f"Hello, {name}! This is EECS-449-group-16.";
    return message.upper() if shout else message;
}

def _application_text(application: dict[str, str | int | None], key: str) -> str {
    value = application.get(key);
    if value is None {
        return "None found";
    }
    if not isinstance(value, str) {
        raise TypeError(f"{key} must be text.");
    }
    return value.strip() if value.strip() else "None found";
}

def _applied_date(application: dict[str, str | int | None]) -> str {
    value = application.get("date_applied");
    if value is None {
        return "";
    }
    if not isinstance(value, str) {
        raise TypeError("Date Applied must be text in MM-DD-YYYY format.");
    }
    value = value.strip();
    if not value {
        return "";
    }
    try {
        parsed_date = datetime.datetime.strptime(value, "%m-%d-%Y");
    } except ValueError {
        raise ValueError("Date Applied must be a valid date in MM-DD-YYYY format.");
    }
    if parsed_date.strftime("%m-%d-%Y") != value {
        raise ValueError("Date Applied must be in MM-DD-YYYY format.");
    }
    return value;
}

def _pdf_path(application: dict[str, str | int | None], key: str) -> str {
    value = application.get(key);
    if value is None or value == "" {
        return "None found";
    }
    if not isinstance(value, str) {
        raise TypeError(f"{key} must be a path to a PDF file.");
    }
    path = str(value).strip();
    if not path {
        return "None found";
    }
    if not path.lower().endswith(".pdf") or not os.path.isfile(path) {
        raise ValueError(f"{key} must be an existing PDF file: {path}");
    }
    with open(path, "rb") as pdf_file {
        if pdf_file.read(5) != b"%PDF-" {
            raise ValueError(f"{key} does not point to a valid PDF file: {path}");
        }
    }
    return path;
}

def table_Sheet(
    application: dict[str, str | int | None],
    export_csv: str | None = None,
) -> list[dict[str, str | int]] {
    row: dict[str, str | int] = {
        "Company name": _application_text(application, "company_name"),
        "Job title": _application_text(application, "job_title"),
        "Date Applied": _applied_date(application),
        "Description": _application_text(application, "description"),
        "Resume PDF used": _pdf_path(application, "resume_pdf"),
        "Cover letter": _pdf_path(application, "cover_letter"),
    };
    pay_available = application.get("pay_available");
    if pay_available is None or pay_available == "" {
        row["Pay available"] = 0;
    } elif isinstance(pay_available, int) {
        row["Pay available"] = pay_available;
    } else {
        raise TypeError("Pay available must be an integer.");
    }
    application_table.append(row);

    if export_csv {
        with open(export_csv, "w", newline="", encoding="utf-8") as output_file {
            writer = csv.writer(output_file);
            writer.writerow(APPLICATION_COLUMNS);
            for application in application_table {
                writer.writerow([application[column] for column in APPLICATION_COLUMNS]);
            }
        }
    }
    return application_table;
}

def fetch(n: int, search: str, location: str | None = None, api_key: str | None = None) -> list[dict[str, any]] {
    if n <= 0 {
        return [];
    }
    load_env_file();
    key = api_key or os.environ.get("JOOBLE_API_KEY", "");
    if not key {
        raise ValueError("Jooble API key must be provided via JOOBLE_API_KEY env var, .env file, or --api-key argument.");
    }
    url = f"https://jooble.org/api/{key}";
    req_payload = {"keywords": search, "ResultOnPage": n};
    if location {
        req_payload["location"] = location;
    }
    body = json.dumps(req_payload).encode("utf-8");
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"}
    );
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Jooble API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Jooble API network error: {e.reason}");
    }

    raw_jobs = resp_payload.get("jobs", []) if isinstance(resp_payload, dict) else [];
    return raw_jobs[:n];
}

def parse_fetch_args(args: argparse.Namespace, location: str | None = None) -> tuple[int, str, str | None] {
    n = 5;
    search = "";
    loc = location if location is not None else args?.location;
    if args.count is not None {
        n = args.count;
    }
    if args.search is not None {
        search = args.search;
    }

    arg1 = args.arg1;
    arg2 = args.arg2;

    if arg1 is not None and arg2 is not None {
        if arg1.isdigit() {
            n = int(arg1);
            search = arg2;
        } elif arg2.isdigit() {
            search = arg1;
            n = int(arg2);
        } else {
            search = f"{arg1} {arg2}";
        }
    } elif arg1 is not None {
        if arg1.isdigit() {
            n = int(arg1);
        } else {
            search = arg1;
        }
    }
    return (n, search, loc);
}

def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog="EECS-449-group-16", description="EECS-449-group-16 command-line tool"
    );
    commands = parser.add_subparsers(dest="command", required=True);

    greet_cmd = commands.add_parser("greet", help="Print a greeting");
    greet_cmd.add_argument("name", nargs="?", `default="world", help="Who to greet");
    greet_cmd.add_argument("--shout", action="store_true", help="Greet loudly");

    fetch_cmd = commands.add_parser("fetch", help="Fetch job listings from Jooble");
    fetch_cmd.add_argument("arg1", nargs="?", `default=None, help="Search keyword or number of listings");
    fetch_cmd.add_argument("arg2", nargs="?", `default=None, help="Search keyword or number of listings");
    fetch_cmd.add_argument("-n", "--count", type=int, `default=None, help="Number of job listings to return (default: 5)");
    fetch_cmd.add_argument("-s", "--search", type=str, `default=None, help="Search keyword");
    fetch_cmd.add_argument("-l", "--location", type=str, `default=None, help="Job location");
    fetch_cmd.add_argument("--api-key", type=str, `default=None, help="Jooble API key");
    fetch_cmd.add_argument("--json", action="store_true", help="Output results as JSON");

    table_cmd = commands.add_parser("table-sheet", help="Track and export a job application");
    table_cmd.add_argument("--company-name", type=str, `default=None, help="Company name");
    table_cmd.add_argument("--job-title", type=str, `default=None, help="Job title");
    table_cmd.add_argument("--date-applied", type=str, `default=None, help="Date applied (MM-DD-YYYY)");
    table_cmd.add_argument("--description", type=str, `default=None, help="Job description");
    table_cmd.add_argument("--pay-available", type=int, `default=None, help="Pay available as an integer amount");
    table_cmd.add_argument("--resume-pdf", type=str, `default=None, help="Resume PDF used");
    table_cmd.add_argument("--cover-letter", type=str, `default=None, help="Cover letter");
    table_cmd.add_argument("--export-csv", type=str, `default=None, help="Write the table to a CSV file");

    db_init_cmd = commands.add_parser("db-init", help="Initialize Turso database schema");
    db_init_cmd.add_argument("--url", type=str, `default=None, help="Database URL");
    db_init_cmd.add_argument("--token", type=str, `default=None, help="Auth token");

    signup_cmd = commands.add_parser("signup", help="Register a new user account");
    signup_cmd.add_argument("--name", type=str, required=True, help="User's full name");
    signup_cmd.add_argument("--email", type=str, required=True, help="User's email address");
    signup_cmd.add_argument("-p", "--password", type=str, `default=None, help="User password (prompted securely if omitted)");
    signup_cmd.add_argument("--phone", type=str, `default=None, help="User phone number");
    signup_cmd.add_argument("--url", type=str, `default=None, help="Database URL");
    signup_cmd.add_argument("--token", type=str, `default=None, help="Auth token");

    login_cmd = commands.add_parser("login", help="Authenticate with email and password");
    login_cmd.add_argument("--email", type=str, required=True, help="User's email address");
    login_cmd.add_argument("-p", "--password", type=str, `default=None, help="User password (prompted securely if omitted)");
    login_cmd.add_argument("--url", type=str, `default=None, help="Database URL");
    login_cmd.add_argument("--token", type=str, `default=None, help="Auth token");

    return parser;
}

def main(argv: list[str] | None = None) -> int {
    args = build_parser().parse_args(argv);
    if args.command == "greet" {
        print(greet(args.name, args.shout));
        return 0;
    } elif args.command == "table-sheet" {
        application: dict[str, str | None] = {
            "company_name": args.company_name,
            "job_title": args.job_title,
            "date_applied": args.date_applied,
            "description": args.description,
            "pay_available": args.pay_available,
            "resume_pdf": args.resume_pdf,
            "cover_letter": args.cover_letter,
        };
        table = table_Sheet(
            application=application,
            export_csv=args.export_csv,
        );
        if args.export_csv {
            print(f"Application table exported to {args.export_csv}");
        }
        print(" | ".join(APPLICATION_COLUMNS));
        for application in table {
            print(" | ".join([str(application[column]) for column in APPLICATION_COLUMNS]));
        }
        return 0;
    } elif args.command == "fetch" {
        (n, search, location) = parse_fetch_args(args);
        if not search {
            print("Error: 'search' argument is required.", file=sys.stderr);
            return 1;
        }
        try {
            jobs = fetch(n, search, location=location, api_key=args.api_key);
            if args.json {
                print(json.dumps(jobs, indent=2));
            } else {
                if location {
                    print(f"Found {len(jobs)} jobs for '{search}' in '{location}':\n");
                } else {
                    print(f"Found {len(jobs)} jobs for '{search}':\n");
                }
                for (idx, job) in enumerate(jobs, 1) {
                    title = job.get("title", "No title");
                    company = job.get("company", "Unknown company");
                    job_location = job.get("location", "Unknown location");
                    salary = job.get("salary", "");
                    link = job.get("link", "");
                    print(f"{idx}. {title} - {company} ({job_location})");
                    if salary {
                        print(f"   Salary: {salary}");
                    }
                    if link {
                        print(f"   Link: {link}");
                    }
                    print();
                }
            }
            return 0;
        } except Exception as e {
            print(f"Error fetching jobs: {str(e)}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "db-init" {
        try {
            conn = get_db_connection(database_url=args.url, auth_token=args.token);
            init_db(conn=conn);
            print("Database schema initialized successfully.");
            return 0;
        } except Exception as e {
            print(f"Error initializing database: {str(e)}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "signup" {
        password = args.password;
        if not password {
            password = getpass.getpass("Password: ");
        }
        try {
            conn = get_db_connection(database_url=args.url, auth_token=args.token);
            user = register_user(
                name=args.name,
                email=args.email,
                password=password,
                phone=args.phone,
                conn=conn
            );
            print(f"User '{user['name']}' ({user['email']}) registered successfully with ID {user['id']}.");
            return 0;
        } except ValueError as e {
            print(f"Registration failed: {str(e)}", file=sys.stderr);
            return 1;
        } except Exception as e {
            print(f"Error registering user: {str(e)}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "login" {
        password = args.password;
        if not password {
            password = getpass.getpass("Password: ");
        }
        try {
            conn = get_db_connection(database_url=args.url, auth_token=args.token);
            auth_res = authenticate_user(email=args.email, password=password, conn=conn);
            if auth_res is None {
                print("Authentication failed: Invalid email or password.", file=sys.stderr);
                return 1;
            }
            print(f"Login successful. Welcome {auth_res['name']}! (Session token: {auth_res['session_token']})");
            return 0;
        } except Exception as e {
            print(f"Error during login: {str(e)}", file=sys.stderr);
            return 1;
        }
    }
    return 2;
}

test "greet returns default greeting" {
    assert greet("world") == "Hello, world! This is EECS-449-group-16.";
    assert greet("world", shout=True) == "HELLO, WORLD! THIS IS EECS-449-GROUP-16.";
}

test "table_Sheet stores application fields and exports CSV" {
    application_table = [];
    with tempfile.TemporaryDirectory() as temp_dir {
        resume_path = os.path.join(temp_dir, "resume.pdf");
        cover_letter_path = os.path.join(temp_dir, "cover.pdf");
        export_path = os.path.join(temp_dir, "applications.csv");
        with open(resume_path, "wb") as resume_file {
            resume_file.write(b"%PDF-1.4\n");
        }
        with open(cover_letter_path, "wb") as cover_letter_file {
            cover_letter_file.write(b"%PDF-1.4\n");
        }
        rows = table_Sheet(
            {
                "company_name": " Acme ",
                "job_title": "Engineer",
                "date_applied": "10-16-2026",
                "description": "Platform engineering",
                "pay_available": 120000,
                "resume_pdf": resume_path,
                "cover_letter": cover_letter_path,
            },
            export_csv=export_path,
        );
        assert len(rows) == 1;
        assert rows[0]["Company name"] == "Acme";
        assert rows[0]["Date Applied"] == "10-16-2026";
        assert rows[0]["Description"] == "Platform engineering";
        assert rows[0]["Pay available"] == 120000;
        assert rows[0]["Resume PDF used"] == resume_path;
        with open(export_path, "r", newline="", encoding="utf-8") as exported_file {
            exported_content = exported_file.read();
        }
        assert "Company name,Job title,Date Applied,Description,Pay available,Resume PDF used,Cover letter" in exported_content;
        assert f"Acme,Engineer,10-16-2026,Platform engineering,120000,{resume_path},{cover_letter_path}" in exported_content;
    }
}

test "table_Sheet uses date and pay defaults when values are missing" {
    application_table = [];
    rows = table_Sheet({"pay_available": None});
    assert rows[0]["Date Applied"] == "";
    assert rows[0]["Pay available"] == 0;
    rows = table_Sheet({"date_applied": "", "pay_available": ""});
    assert rows[1]["Date Applied"] == "";
    assert rows[1]["Pay available"] == 0;
}

test "table_Sheet validates date format and PDF files" {
    application_table = [];
    with tempfile.TemporaryDirectory() as temp_dir {
        invalid_pdf_path = os.path.join(temp_dir, "not-a-pdf.pdf");
        with open(invalid_pdf_path, "w", encoding="utf-8") as invalid_pdf {
            invalid_pdf.write("not a PDF");
        }
        with testraises(ValueError) {
            table_Sheet({
                "date_applied": "2026-10-16",
                "resume_pdf": invalid_pdf_path,
            });
        }
        with testraises(ValueError) {
            table_Sheet({"date_applied": "02-30-2026"});
        }
        with testraises(TypeError) {
            table_Sheet({"pay_available": "120000"});
        }
    }
}

test "parse_fetch_args resolves arguments accurately" {
    parser = build_parser();

    args1 = parser.parse_args(["fetch", "software", "-n", "3"]);
    (n1, s1, loc1) = parse_fetch_args(args1);
    assert n1 == 3;
    assert s1 == "software";
    assert loc1 is None;

    args2 = parser.parse_args(["fetch", "3", "python"]);
    (n2, s2, loc2) = parse_fetch_args(args2);
    assert n2 == 3;
    assert s2 == "python";
    assert loc2 is None;

    args3 = parser.parse_args(["fetch", "python", "3"]);
    (n3, s3, loc3) = parse_fetch_args(args3);
    assert n3 == 3;
    assert s3 == "python";
    assert loc3 is None;

    args4 = parser.parse_args(["fetch", "developer"]);
    (n4, s4, loc4) = parse_fetch_args(args4);
    assert n4 == 5;
    assert s4 == "developer";
    assert loc4 is None;
}

test "parse_fetch_args parses location argument" {
    parser = build_parser();

    args1 = parser.parse_args(["fetch", "software", "-l", "New York"]);
    (n1, s1, loc1) = parse_fetch_args(args1);
    assert n1 == 5;
    assert s1 == "software";
    assert loc1 == "New York";

    args2 = parser.parse_args(["fetch", "engineer", "--location", "San Francisco, CA"]);
    (n2, s2, loc2) = parse_fetch_args(args2);
    assert n2 == 5;
    assert s2 == "engineer";
    assert loc2 == "San Francisco, CA";

    args3 = parser.parse_args(["fetch", "designer", "-n", "2", "-l", "Remote"]);
    (n3, s3, loc3) = parse_fetch_args(args3);
    assert n3 == 2;
    assert s3 == "designer";
    assert loc3 == "Remote";

    args4 = parser.parse_args(["fetch", "developer"]);
    (n4, s4, loc4) = parse_fetch_args(args4, location="Chicago");
    assert n4 == 5;
    assert s4 == "developer";
    assert loc4 == "Chicago";
}

test "fetch default count is 5" {
    parser = build_parser();
    args = parser.parse_args(["fetch", "designer"]);
    (n, s, l) = parse_fetch_args(args);
    assert n == 5;
    assert s == "designer";
    assert l is None;
}

test "fetch with n <= 0 returns empty list" {
    assert fetch(0, "software", api_key="dummy") == [];
    assert fetch(-1, "software", api_key="dummy") == [];
}

test "fetch without api key raises ValueError" {
    old_key = os.environ.get("JOOBLE_API_KEY");
    if old_key is not None {
        del os.environ["JOOBLE_API_KEY"];
    }
    with patch("os.path.exists", return_value=False) {
        with testraises(ValueError) {
            fetch(5, "software", api_key=None);
        }
    }
    if old_key is not None {
        os.environ["JOOBLE_API_KEY"] = old_key;
    }
}

test "fetch with mocked API response" {
    mock_payload = {
        "totalCount": 2,
        "jobs": [
            {
                "id": "1",
                "title": "Software Engineer",
                "company": "Tech Corp",
                "location": "Ann Arbor, MI",
                "salary": "$120,000",
                "link": "https://jooble.org/desc/1"
            },
            {
                "id": "2",
                "title": "Data Scientist",
                "company": "Data Labs",
                "location": "Remote",
                "salary": "$110,000",
                "link": "https://jooble.org/desc/2"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        results = fetch(1, "engineer", api_key="test-api-key");
        assert len(results) == 1;
        assert results[0]["title"] == "Software Engineer";

        results_all = fetch(5, "engineer", api_key="test-api-key");
        assert len(results_all) == 2;
        assert results_all[1]["title"] == "Data Scientist";
    }
}

test "fetch includes location in payload when specified" {
    mock_payload = {
        "totalCount": 1,
        "jobs": [
            {
                "id": "1",
                "title": "Software Engineer",
                "company": "Tech Corp",
                "location": "Ann Arbor, MI"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        fetch(5, "engineer", location="Ann Arbor, MI", api_key="test-api-key");
        assert mock_urlopen.called;
        sent_req = mock_urlopen.call_args[0][0];
        sent_payload = json.loads(sent_req.data.decode("utf-8"));
        assert sent_payload["keywords"] == "engineer";
        assert sent_payload["ResultOnPage"] == 5;
        assert sent_payload["location"] == "Ann Arbor, MI";

        fetch(5, "engineer", location=None, api_key="test-api-key");
        sent_req_none = mock_urlopen.call_args[0][0];
        sent_payload_none = json.loads(sent_req_none.data.decode("utf-8"));
        assert "location" not in sent_payload_none;
    }
}

test "main CLI runs fetch successfully" {
    mock_payload = {
        "totalCount": 1,
        "jobs": [
            {
                "id": "1",
                "title": "Backend Engineer",
                "company": "Jooble Partner",
                "location": "New York, NY",
                "salary": "$130,000",
                "link": "https://jooble.org/desc/backend"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        code = main(["fetch", "backend", "-n", "1", "--api-key", "test-api-key"]);
        assert code == 0;

        code_json = main(["fetch", "backend", "-n", "1", "--api-key", "test-api-key", "--json"]);
        assert code_json == 0;
    }
}

test "main CLI runs fetch with location successfully" {
    mock_payload = {
        "totalCount": 1,
        "jobs": [
            {
                "id": "1",
                "title": "Backend Engineer",
                "company": "Jooble Partner",
                "location": "New York, NY",
                "salary": "$130,000",
                "link": "https://jooble.org/desc/backend"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        code = main(["fetch", "backend", "-n", "1", "-l", "New York", "--api-key", "test-api-key"]);
        assert code == 0;
        sent_req = mock_urlopen.call_args[0][0];
        sent_payload = json.loads(sent_req.data.decode("utf-8"));
        assert sent_payload["location"] == "New York";

        code_long = main(["fetch", "backend", "--location", "New York", "--api-key", "test-api-key"]);
        assert code_long == 0;
    }
}

# --- Database Tests ---

test "get_db_connection without url raises ValueError" {
    old_url1 = os.environ.get("TURSO_DATABASE_URL");
    old_url2 = os.environ.get("TURSO_URL");
    if old_url1 is not None {
        del os.environ["TURSO_DATABASE_URL"];
    }
    if old_url2 is not None {
        del os.environ["TURSO_URL"];
    }
    with patch("os.path.exists", return_value=False) {
        with testraises(ValueError) {
            get_db_connection(database_url=None, auth_token=None);
        }
    }
    if old_url1 is not None {
        os.environ["TURSO_DATABASE_URL"] = old_url1;
    }
    if old_url2 is not None {
        os.environ["TURSO_URL"] = old_url2;
    }
}

test "db-init initializes tables on in-memory database" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);
    cur = conn.cursor();
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC;");
    tables = [r[0] for r in cur.fetchall()];
    assert "users" in tables;
    assert "resumes" in tables;
    assert "applications" in tables;
}

test "CRUD operations on users" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    user = create_user("Alice Smith", "alice@example.com", "555-1234", conn=conn);
    assert user["id"] == 1;
    assert user["name"] == "Alice Smith";
    assert user["email"] == "alice@example.com";
    assert user["phone"] == "555-1234";

    fetched = get_user_by_id(1, conn=conn);
    assert fetched is not None;
    assert fetched["email"] == "alice@example.com";

    by_email = get_user_by_email("alice@example.com", conn=conn);
    assert by_email is not None;
    assert by_email["id"] == 1;

    users = list_users(conn=conn);
    assert len(users) == 1;

    updated = update_user(1, name="Alice Johnson", phone="555-9999", conn=conn);
    assert updated is not None;
    assert updated["name"] == "Alice Johnson";
    assert updated["phone"] == "555-9999";
    assert updated["email"] == "alice@example.com";

    deleted = delete_user(1, conn=conn);
    assert deleted;
    assert get_user_by_id(1, conn=conn) is None;
}

test "CRUD operations on resumes" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    user = create_user("Bob Jones", "bob@example.com", conn=conn);
    u_id = user["id"];

    resume = create_resume(u_id, "Software Engineer Resume", "Python, Jac, SQL", "resumes/bob.pdf", conn=conn);
    assert resume["id"] == 1;
    assert resume["user_id"] == u_id;
    assert resume["title"] == "Software Engineer Resume";
    assert resume["file_path"] == "resumes/bob.pdf";

    fetched = get_resume_by_id(1, conn=conn);
    assert fetched is not None;
    assert fetched["title"] == "Software Engineer Resume";

    resumes = list_resumes_by_user(u_id, conn=conn);
    assert len(resumes) == 1;

    updated = update_resume(1, title="Senior SWE Resume", file_path="resumes/bob_v2.pdf", conn=conn);
    assert updated is not None;
    assert updated["title"] == "Senior SWE Resume";
    assert updated["file_path"] == "resumes/bob_v2.pdf";

    deleted = delete_resume(1, conn=conn);
    assert deleted;
    assert get_resume_by_id(1, conn=conn) is None;
}

test "CRUD operations on applications" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    user = create_user("Charlie", "charlie@example.com", conn=conn);
    resume = create_resume(user["id"], "General", conn=conn);

    app = create_application(
        user["id"],
        "Backend Developer",
        "Acme Corp",
        resume_id=resume["id"],
        job_url="https://acme.com/jobs/1",
        status="applied",
        applied_date="2026-10-09",
        notes="Applied via website",
        conn=conn
    );
    assert app["id"] == 1;
    assert app["job_title"] == "Backend Developer";
    assert app["company"] == "Acme Corp";
    assert app["status"] == "applied";

    fetched = get_application_by_id(1, conn=conn);
    assert fetched is not None;
    assert fetched["company"] == "Acme Corp";

    all_apps = list_applications_by_user(user["id"], conn=conn);
    assert len(all_apps) == 1;

    applied_apps = list_applications_by_user(user["id"], status="applied", conn=conn);
    assert len(applied_apps) == 1;

    interviewing_apps = list_applications_by_user(user["id"], status="interviewing", conn=conn);
    assert len(interviewing_apps) == 0;

    updated = update_application(1, status="interviewing", notes="First round scheduled", conn=conn);
    assert updated is not None;
    assert updated["status"] == "interviewing";
    assert updated["notes"] == "First round scheduled";

    deleted = delete_application(1, conn=conn);
    assert deleted;
    assert get_application_by_id(1, conn=conn) is None;
}

test "Foreign key enforcement and cascading deletes" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    with testraises(Exception) {
        create_resume(999, "Invalid Resume", conn=conn);
    }

    with testraises(Exception) {
        create_application(999, "Engineer", "TechCorp", conn=conn);
    }

    user = create_user("Dave", "dave@example.com", conn=conn);
    resume = create_resume(user["id"], "Dave Resume", conn=conn);
    app = create_application(user["id"], "SWE", "BigCo", resume_id=resume["id"], conn=conn);

    delete_user(user["id"], conn=conn);
    assert get_resume_by_id(resume["id"], conn=conn) is None;
    assert get_application_by_id(app["id"], conn=conn) is None;

    user2 = create_user("Eve", "eve@example.com", conn=conn);
    resume2 = create_resume(user2["id"], "Eve Resume", conn=conn);
    app2 = create_application(user2["id"], "SWE", "Startup", resume_id=resume2["id"], conn=conn);

    delete_resume(resume2["id"], conn=conn);
    updated_app2 = get_application_by_id(app2["id"], conn=conn);
    assert updated_app2 is not None;
    assert updated_app2["resume_id"] is None;
}

test "main CLI runs db-init successfully" {
    code = main(["db-init", "--url", ":memory:"]);
    assert code == 0;
}

# --- Authentication Tests ---

test "hash_password generates salted hashes and verify_password verifies correctly" {
    pw = "supersecret123";
    h1 = hash_password(pw);
    h2 = hash_password(pw);
    assert h1 != h2;
    assert "$" in h1;
    assert verify_password(pw, h1);
    assert verify_password(pw, h2);
    assert not verify_password("wrongpassword", h1);
    assert not verify_password("", h1);
    assert not verify_password(pw, "");
    assert not verify_password(pw, "invalidhashwithoutdelimiter");
}

test "register_user successfully creates user and avoids storing plaintext password" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    user = register_user("Grace Hopper", "grace@example.com", "nanoseconds!", phone="555-0100", conn=conn);
    assert user["id"] == 1;
    assert user["name"] == "Grace Hopper";
    assert user["email"] == "grace@example.com";
    assert user["phone"] == "555-0100";
    assert "password_hash" not in user;

    # Verify password_hash is stored in database and not plaintext
    cur = conn.cursor();
    cur.execute("SELECT password_hash FROM users WHERE id = 1");
    row = cur.fetchone();
    assert row is not None;
    assert row[0] != "nanoseconds!";
    assert "$" in row[0];
    assert verify_password("nanoseconds!", row[0]);
}

test "register_user validation and uniqueness constraints" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    with testraises(ValueError) {
        register_user("", "test@example.com", "pass", conn=conn);
    }
    with testraises(ValueError) {
        register_user("Name", "", "pass", conn=conn);
    }
    with testraises(ValueError) {
        register_user("Name", "test@example.com", "", conn=conn);
    }

    register_user("User One", "user@example.com", "pass1", conn=conn);
    with testraises(ValueError) {
        register_user("User Two", "user@example.com", "pass2", conn=conn);
    }
    with testraises(ValueError) {
        register_user("User Two", "USER@EXAMPLE.COM", "pass2", conn=conn);
    }
}

test "authenticate_user verifies credentials and issues session token" {
    conn = get_db_connection(database_url=":memory:");
    init_db(conn=conn);

    register_user("Alan Turing", "alan@example.com", "enigma_solved", conn=conn);

    # Valid login
    auth_success = authenticate_user("alan@example.com", "enigma_solved", conn=conn);
    assert auth_success is not None;
    assert auth_success["name"] == "Alan Turing";
    assert auth_success["email"] == "alan@example.com";
    assert "password_hash" not in auth_success;
    assert "session_token" in auth_success;
    assert len(auth_success["session_token"]) == 48;

    # Case-insensitive email login
    auth_ci = authenticate_user("ALAN@EXAMPLE.COM", "enigma_solved", conn=conn);
    assert auth_ci is not None;

    # Invalid password
    auth_wrong_pw = authenticate_user("alan@example.com", "wrong_code", conn=conn);
    assert auth_wrong_pw is None;

    # Nonexistent user
    auth_no_user = authenticate_user("nobody@example.com", "password", conn=conn);
    assert auth_no_user is None;

    # Empty inputs
    assert authenticate_user("", "enigma_solved", conn=conn) is None;
    assert authenticate_user("alan@example.com", "", conn=conn) is None;
}

test "main CLI runs signup and login commands" {
    with tempfile.TemporaryDirectory() as temp_dir {
        db_path = os.path.join(temp_dir, "auth_test.db");
        init_code = main(["db-init", "--url", db_path]);
        assert init_code == 0;

        # Signup with --password
        signup_code = main([
            "signup",
            "--name", "Ada Lovelace",
            "--email", "ada@example.com",
            "-p", "analytical_engine",
            "--url", db_path
        ]);
        assert signup_code == 0;

        # Signup duplicate email fails
        signup_dup_code = main([
            "signup",
            "--name", "Ada Duplicate",
            "--email", "ada@example.com",
            "-p", "newpass",
            "--url", db_path
        ]);
        assert signup_dup_code == 1;

        # Login with --password
        login_code = main([
            "login",
            "--email", "ada@example.com",
            "-p", "analytical_engine",
            "--url", db_path
        ]);
        assert login_code == 0;

        # Login with wrong password
        login_fail_code = main([
            "login",
            "--email", "ada@example.com",
            "-p", "wrongpassword",
            "--url", db_path
        ]);
        assert login_fail_code == 1;

        # Signup and login using prompted password (getpass)
        with patch("getpass.getpass", return_value="bernoulli_numbers") {
            prompt_signup_code = main([
                "signup",
                "--name", "Charles Babbage",
                "--email", "charles@example.com",
                "--url", db_path
            ]);
            assert prompt_signup_code == 0;

            prompt_login_code = main([
                "login",
                "--email", "charles@example.com",
                "--url", db_path
            ]);
            assert prompt_login_code == 0;
        }
    }
}

with entry:__main__ {
    sys.`exit(main());
}
