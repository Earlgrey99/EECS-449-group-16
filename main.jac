"""EECS-449-group-16 - a command-line Jac app.

Subcommands are declared with `argparse` and dispatched from the entry block.
Add one by registering a parser in `build_parser` and a branch in `main`.

    jac run main.jac -- greet Ada --shout
    jac run main.jac -- fetch "software engineer" -n 5
    jac run main.jac -- fetch "software engineer" -n 5 -l "New York"
    jac run main.jac -- fetch "software engineer" --salary 100000 -t "full-time" -c "Google"
    jac run main.jac -- db-init
    jac run main.jac -- signup --name "Ada Lovelace" --email "ada@example.com"
    jac run main.jac -- login --email "ada@example.com"
"""

import argparse;
import csv;
import datetime;
import getpass;
import io;
import json;
import os;
import re;
import sys;
import tempfile;
import applicant_cli;
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

def _extract_salary_values(salary_val: any) -> list[float] {
    if salary_val is None {
        return [];
    }
    if isinstance(salary_val, (int, float)) {
        return [float(salary_val)];
    }
    text = str(salary_val).strip();
    if not text {
        return [];
    }
    cleaned = text.replace(",", "");
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*([kK])?", cleaned);
    values: list[float] = [];
    for (num_str, k_suffix) in matches {
        try {
            val = float(num_str);
            if k_suffix.lower() == "k" {
                val = val * 1000.0;
            }
            values.append(val);
        } except ValueError {
            continue;
        }
    }
    return values;
}

def _matches_contract_type(job_type: any, target_type: str) -> bool {
    if not job_type or not target_type {
        return False;
    }
    jt = str(job_type).strip().lower();
    tt = str(target_type).strip().lower();
    if tt == jt or tt in jt {
        return True;
    }
    jt_norm = jt.replace("-", " ");
    tt_norm = tt.replace("-", " ");
    if tt_norm == jt_norm or tt_norm in jt_norm {
        return True;
    }
    return False;
}

def _matches_company(job_company: any, target_company: str) -> bool {
    if not job_company or not target_company {
        return False;
    }
    jc = str(job_company).strip().lower();
    tc = str(target_company).strip().lower();
    return tc in jc;
}

def fetch(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    contract_type: str | None = None,
    company: str | None = None,
    api_key: str | None = None
) -> list[dict[str, any]] {
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
    if salary is not None {
        req_payload["salary"] = int(salary);
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
    filtered_jobs = [];
    for job in raw_jobs {
        if company is not None and str(company).strip() != "" {
            if not _matches_company(job.get("company"), str(company).strip()) {
                continue;
            }
        }
        if contract_type is not None and str(contract_type).strip() != "" {
            if not _matches_contract_type(job.get("type"), str(contract_type).strip()) {
                continue;
            }
        }
        if salary is not None {
            sal_vals = _extract_salary_values(job.get("salary"));
            if not sal_vals or max(sal_vals) < int(salary) {
                continue;
            }
        }
        filtered_jobs.append(job);
    }
    return filtered_jobs[:n];
}

def parse_fetch_args(
    args: argparse.Namespace,
    location: str | None = None,
    salary: int | None = None,
    contract_type: str | None = None,
    company: str | None = None
) -> tuple[int, str, str | None, int | None, str | None, str | None] {
    n = 5;
    search = "";
    loc = location if location is not None else args?.location;
    sal = salary if salary is not None else args?.salary;
    if sal is not None {
        sal = int(sal);
    }
    ctype = contract_type if contract_type is not None else args?.contract_type;
    comp = company if company is not None else args?.company;

    if args?.count is not None {
        n = args.count;
    }
    if args?.search is not None {
        search = args.search;
    }

    arg1 = args?.arg1;
    arg2 = args?.arg2;

    if arg1 is not None and arg2 is not None {
        if str(arg1).isdigit() {
            n = int(arg1);
            search = arg2;
        } elif str(arg2).isdigit() {
            search = arg1;
            n = int(arg2);
        } else {
            search = f"{arg1} {arg2}";
        }
    } elif arg1 is not None {
        if str(arg1).isdigit() {
            n = int(arg1);
        } else {
            search = arg1;
        }
    }
    return (n, search, loc, sal, ctype, comp);
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
    fetch_cmd.add_argument("-S", "--salary", "--min-salary", dest="salary", type=int, `default=None, help="Minimum desired salary threshold");
    fetch_cmd.add_argument("-t", "--contract-type", "--type", dest="contract_type", type=str, `default=None, help="Contract or employment type (e.g. full-time, part-time, contract, internship)");
    fetch_cmd.add_argument("-c", "--company", dest="company", type=str, `default=None, help="Target company name");
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


    profile_cmd = commands.add_parser("profile", help="Manage local applicant profile");
    profile_cmd.add_argument("--set", dest="set_fields", nargs=2, action="append", `default=[], help="Set field and value");
    profile_cmd.add_argument("--show", action="store_true");
    profile_cmd.add_argument("--file", type=str, `default=None);

    autofill_cmd = commands.add_parser("autofill", help="Preview or fill application fields");
    autofill_cmd.add_argument("--target", type=str, required=True);
    autofill_cmd.add_argument("--profile", type=str, `default=None);
    autofill_cmd.add_argument("--mapping", type=str, `default=None);
    autofill_cmd.add_argument("--apply", action="store_true");
    autofill_cmd.add_argument("--headless", action="store_true");
    autofill_cmd.add_argument("--hold-seconds", type=int, `default=0);

    tailor_cmd = commands.add_parser("tailor-resume", help="Prepare job-specific resume review");
    tailor_cmd.add_argument("--resume", type=str, `default=None);
    tailor_cmd.add_argument("--profile", type=str, `default=None);
    tailor_cmd.add_argument("--job-description", type=str, `default=None);
    tailor_cmd.add_argument("--job-text", type=str, `default=None);
    tailor_cmd.add_argument("--role", type=str, `default="Target position");
    tailor_cmd.add_argument("--output", type=str, `default="tailored-review.md");

    return parser;
}

def main(argv: list[str] | None = None) -> int {
    args = build_parser().parse_args(argv);
    if args.command == "profile" {
        try {
            return applicant_cli.profile_command(args);
        } except Exception as e {
            print(f"Profile error: {e}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "autofill" {
        try {
            return applicant_cli.autofill_command(args);
        } except Exception as e {
            print(f"Autofill error: {e}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "tailor-resume" {
        try {
            return applicant_cli.tailor_command(args);
        } except Exception as e {
            print(f"Tailoring error: {e}", file=sys.stderr);
            return 1;
        }
    } elif args.command == "greet" {
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
        (n, search, location, salary, contract_type, company) = parse_fetch_args(args);
        if not search {
            print("Error: 'search' argument is required.", file=sys.stderr);
            return 1;
        }
        try {
            jobs = fetch(
                n,
                search,
                location=location,
                salary=salary,
                contract_type=contract_type,
                company=company,
                api_key=args.api_key
            );
            if args.json {
                print(json.dumps(jobs, indent=2));
            } else {
                header = f"Found {len(jobs)} jobs for '{search}'";
                if location {
                    header = f"{header} in '{location}'";
                }
                filters_desc = [];
                if company {
                    filters_desc.append(f"company: '{company}'");
                }
                if contract_type {
                    filters_desc.append(f"contract type: '{contract_type}'");
                }
                if salary is not None {
                    filters_desc.append(f"salary >= {salary}");
                }
                if filters_desc {
                    header = f"{header} (filters: {', '.join(filters_desc)})";
                }
                print(f"{header}:\n");
                for (idx, job) in enumerate(jobs, 1) {
                    title = job.get("title", "No title");
                    job_company = job.get("company", "Unknown company");
                    job_location = job.get("location", "Unknown location");
                    salary_str = job.get("salary", "");
                    job_type = job.get("type", "");
                    link = job.get("link", "");
                    print(f"{idx}. {title} - {job_company} ({job_location})");
                    if job_type {
                        print(f"   Contract Type: {job_type}");
                    }
                    if salary_str {
                        print(f"   Salary: {salary_str}");
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
    (n1, s1, loc1, sal1, ctype1, comp1) = parse_fetch_args(args1);
    assert n1 == 3;
    assert s1 == "software";
    assert loc1 is None;
    assert sal1 is None;
    assert ctype1 is None;
    assert comp1 is None;

    args2 = parser.parse_args(["fetch", "3", "python"]);
    (n2, s2, loc2, sal2, ctype2, comp2) = parse_fetch_args(args2);
    assert n2 == 3;
    assert s2 == "python";
    assert loc2 is None;
    assert sal2 is None;
    assert ctype2 is None;
    assert comp2 is None;

    args3 = parser.parse_args(["fetch", "python", "3"]);
    (n3, s3, loc3, sal3, ctype3, comp3) = parse_fetch_args(args3);
    assert n3 == 3;
    assert s3 == "python";
    assert loc3 is None;
    assert sal3 is None;
    assert ctype3 is None;
    assert comp3 is None;

    args4 = parser.parse_args(["fetch", "developer"]);
    (n4, s4, loc4, sal4, ctype4, comp4) = parse_fetch_args(args4);
    assert n4 == 5;
    assert s4 == "developer";
    assert loc4 is None;
    assert sal4 is None;
    assert ctype4 is None;
    assert comp4 is None;
}

test "parse_fetch_args parses location argument" {
    parser = build_parser();

    args1 = parser.parse_args(["fetch", "software", "-l", "New York"]);
    (n1, s1, loc1, sal1, ctype1, comp1) = parse_fetch_args(args1);
    assert n1 == 5;
    assert s1 == "software";
    assert loc1 == "New York";
    assert sal1 is None;
    assert ctype1 is None;
    assert comp1 is None;

    args2 = parser.parse_args(["fetch", "engineer", "--location", "San Francisco, CA"]);
    (n2, s2, loc2, sal2, ctype2, comp2) = parse_fetch_args(args2);
    assert n2 == 5;
    assert s2 == "engineer";
    assert loc2 == "San Francisco, CA";

    args3 = parser.parse_args(["fetch", "designer", "-n", "2", "-l", "Remote"]);
    (n3, s3, loc3, sal3, ctype3, comp3) = parse_fetch_args(args3);
    assert n3 == 2;
    assert s3 == "designer";
    assert loc3 == "Remote";

    args4 = parser.parse_args(["fetch", "developer"]);
    (n4, s4, loc4, sal4, ctype4, comp4) = parse_fetch_args(args4, location="Chicago");
    assert n4 == 5;
    assert s4 == "developer";
    assert loc4 == "Chicago";
}

test "fetch default count is 5" {
    parser = build_parser();
    args = parser.parse_args(["fetch", "designer"]);
    (n, s, l, sal, ctype, comp) = parse_fetch_args(args);
    assert n == 5;
    assert s == "designer";
    assert l is None;
    assert sal is None;
    assert ctype is None;
    assert comp is None;
}

test "parse_fetch_args parses salary, contract type, and company arguments" {
    parser = build_parser();

    # Salary flags
    args_sal1 = parser.parse_args(["fetch", "engineer", "--salary", "100000"]);
    (n1, s1, loc1, sal1, ctype1, comp1) = parse_fetch_args(args_sal1);
    assert sal1 == 100000;

    args_sal2 = parser.parse_args(["fetch", "engineer", "-S", "85000"]);
    (n2, s2, loc2, sal2, ctype2, comp2) = parse_fetch_args(args_sal2);
    assert sal2 == 85000;

    args_sal3 = parser.parse_args(["fetch", "engineer", "--min-salary", "95000"]);
    (n3, s3, loc3, sal3, ctype3, comp3) = parse_fetch_args(args_sal3);
    assert sal3 == 95000;

    # Contract type flags
    args_type1 = parser.parse_args(["fetch", "developer", "-t", "full-time"]);
    (n4, s4, loc4, sal4, ctype4, comp4) = parse_fetch_args(args_type1);
    assert ctype4 == "full-time";

    args_type2 = parser.parse_args(["fetch", "developer", "--contract-type", "contract"]);
    (n5, s5, loc5, sal5, ctype5, comp5) = parse_fetch_args(args_type2);
    assert ctype5 == "contract";

    args_type3 = parser.parse_args(["fetch", "developer", "--type", "part-time"]);
    (n6, s6, loc6, sal6, ctype6, comp6) = parse_fetch_args(args_type3);
    assert ctype6 == "part-time";

    # Company flags
    args_comp1 = parser.parse_args(["fetch", "manager", "-c", "Google"]);
    (n7, s7, loc7, sal7, ctype7, comp7) = parse_fetch_args(args_comp1);
    assert comp7 == "Google";

    args_comp2 = parser.parse_args(["fetch", "manager", "--company", "Amazon"]);
    (n8, s8, loc8, sal8, ctype8, comp8) = parse_fetch_args(args_comp2);
    assert comp8 == "Amazon";

    # Explicit keyword argument overrides
    args_base = parser.parse_args(["fetch", "tester"]);
    (n9, s9, loc9, sal9, ctype9, comp9) = parse_fetch_args(
        args_base,
        location="Austin, TX",
        salary=120000,
        contract_type="internship",
        company="Apple"
    );
    assert loc9 == "Austin, TX";
    assert sal9 == 120000;
    assert ctype9 == "internship";
    assert comp9 == "Apple";
}

test "parse_fetch_args parses combined filter arguments" {
    parser = build_parser();
    args = parser.parse_args([
        "fetch", "data scientist",
        "-l", "New York",
        "--salary", "120000",
        "-t", "full-time",
        "-c", "Amazon",
        "-n", "5"
    ]);
    (n, search, loc, sal, ctype, comp) = parse_fetch_args(args);
    assert n == 5;
    assert search == "data scientist";
    assert loc == "New York";
    assert sal == 120000;
    assert ctype == "full-time";
    assert comp == "Amazon";
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

test "fetch includes salary in payload when specified" {
    mock_payload = {
        "totalCount": 1,
        "jobs": [
            {
                "id": "1",
                "title": "Software Engineer",
                "company": "Tech Corp",
                "location": "Ann Arbor, MI",
                "salary": "$125,000"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        fetch(5, "engineer", salary=100000, api_key="test-api-key");
        assert mock_urlopen.called;
        sent_req = mock_urlopen.call_args[0][0];
        sent_payload = json.loads(sent_req.data.decode("utf-8"));
        assert sent_payload["keywords"] == "engineer";
        assert sent_payload["ResultOnPage"] == 5;
        assert sent_payload["salary"] == 100000;

        fetch(5, "engineer", salary=None, api_key="test-api-key");
        sent_req_none = mock_urlopen.call_args[0][0];
        sent_payload_none = json.loads(sent_req_none.data.decode("utf-8"));
        assert "salary" not in sent_payload_none;
    }
}

test "fetch filters listings by company name" {
    mock_payload = {
        "totalCount": 3,
        "jobs": [
            {
                "id": "1",
                "title": "Backend Engineer",
                "company": "Google LLC",
                "location": "Mountain View, CA"
            },
            {
                "id": "2",
                "title": "Frontend Engineer",
                "company": "Amazon AWS",
                "location": "Seattle, WA"
            },
            {
                "id": "3",
                "title": "Site Reliability Engineer",
                "company": "Google Cloud",
                "location": "Sunnyvale, CA"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        # Case-insensitive substring match
        res_google = fetch(5, "engineer", company="Google", api_key="test-api-key");
        assert len(res_google) == 2;
        assert res_google[0]["company"] == "Google LLC";
        assert res_google[1]["company"] == "Google Cloud";

        res_amazon = fetch(5, "engineer", company="amazon", api_key="test-api-key");
        assert len(res_amazon) == 1;
        assert res_amazon[0]["company"] == "Amazon AWS";

        res_none = fetch(5, "engineer", company="Microsoft", api_key="test-api-key");
        assert len(res_none) == 0;
    }
}

test "fetch filters listings by contract type" {
    mock_payload = {
        "totalCount": 4,
        "jobs": [
            {
                "id": "1",
                "title": "Full Stack Dev",
                "company": "Alpha",
                "type": "Full-time"
            },
            {
                "id": "2",
                "title": "Junior Dev",
                "company": "Beta",
                "type": "Part-time"
            },
            {
                "id": "3",
                "title": "Contractor",
                "company": "Gamma",
                "type": "Contract"
            },
            {
                "id": "4",
                "title": "Intern",
                "company": "Delta"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        # Case-insensitive match & hyphen normalization
        res_ft = fetch(5, "dev", contract_type="full-time", api_key="test-api-key");
        assert len(res_ft) == 1;
        assert res_ft[0]["title"] == "Full Stack Dev";

        res_ft_space = fetch(5, "dev", contract_type="full time", api_key="test-api-key");
        assert len(res_ft_space) == 1;
        assert res_ft_space[0]["title"] == "Full Stack Dev";

        res_contract = fetch(5, "dev", contract_type="contract", api_key="test-api-key");
        assert len(res_contract) == 1;
        assert res_contract[0]["title"] == "Contractor";

        res_missing = fetch(5, "dev", contract_type="internship", api_key="test-api-key");
        assert len(res_missing) == 0;
    }
}

test "fetch filters listings by salary threshold" {
    mock_payload = {
        "totalCount": 5,
        "jobs": [
            {
                "id": "1",
                "title": "Principal Engineer",
                "salary": "$150,000"
            },
            {
                "id": "2",
                "title": "Junior Engineer",
                "salary": "$75,000"
            },
            {
                "id": "3",
                "title": "Staff Engineer",
                "salary": "$110,000 - $140,000"
            },
            {
                "id": "4",
                "title": "Lead Engineer",
                "salary": "$120k"
            },
            {
                "id": "5",
                "title": "Undisclosed Engineer",
                "salary": ""
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        # Threshold: 100000
        # Expected: id 1 ($150k), id 3 ($110-140k), id 4 ($120k)
        # Excluded: id 2 ($75k), id 5 (empty)
        res_100k = fetch(5, "engineer", salary=100000, api_key="test-api-key");
        assert len(res_100k) == 3;
        ids_100k = [j["id"] for j in res_100k];
        assert "1" in ids_100k;
        assert "3" in ids_100k;
        assert "4" in ids_100k;
        assert "2" not in ids_100k;
        assert "5" not in ids_100k;

        # Higher threshold: 130000
        # Expected: id 1 ($150k), id 3 ($140k max)
        res_130k = fetch(5, "engineer", salary=130000, api_key="test-api-key");
        assert len(res_130k) == 2;
        ids_130k = [j["id"] for j in res_130k];
        assert "1" in ids_130k;
        assert "3" in ids_130k;
    }
}

test "fetch filters listings by combined filters" {
    mock_payload = {
        "totalCount": 4,
        "jobs": [
            {
                "id": "1",
                "title": "Senior Data Scientist",
                "company": "Amazon Web Services",
                "location": "New York, NY",
                "salary": "$135,000",
                "type": "Full-time"
            },
            {
                "id": "2",
                "title": "Data Scientist",
                "company": "Amazon",
                "location": "New York, NY",
                "salary": "$90,000",
                "type": "Full-time"
            },
            {
                "id": "3",
                "title": "Data Scientist",
                "company": "Amazon",
                "location": "New York, NY",
                "salary": "$140,000",
                "type": "Contract"
            },
            {
                "id": "4",
                "title": "Data Scientist",
                "company": "Google",
                "location": "New York, NY",
                "salary": "$150,000",
                "type": "Full-time"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    with patch("urllib.request.urlopen", return_value=mock_cm) {
        # Only job 1 matches: company contains Amazon, salary >= 120000, type is full-time
        res = fetch(
            5,
            "data scientist",
            location="New York",
            salary=120000,
            contract_type="full-time",
            company="Amazon",
            api_key="test-api-key"
        );
        assert len(res) == 1;
        assert res[0]["id"] == "1";
        assert res[0]["company"] == "Amazon Web Services";
        assert res[0]["type"] == "Full-time";
    }
}

test "main CLI runs fetch with combined filters and outputs criteria and contract type" {
    mock_payload = {
        "totalCount": 2,
        "jobs": [
            {
                "id": "1",
                "title": "Staff ML Engineer",
                "company": "Amazon AI",
                "location": "New York, NY",
                "salary": "$160,000",
                "type": "Full-time",
                "link": "https://jooble.org/desc/1"
            },
            {
                "id": "2",
                "title": "Junior ML Engineer",
                "company": "Amazon AI",
                "location": "New York, NY",
                "salary": "$80,000",
                "type": "Part-time",
                "link": "https://jooble.org/desc/2"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    buf: io.StringIO = io.StringIO();
    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen, patch("sys.stdout", buf) {
        # Test standard output
        code = main([
            "fetch", "machine learning",
            "-l", "New York",
            "--salary", "120000",
            "-t", "full-time",
            "-c", "Amazon",
            "--api-key", "test-api-key"
        ]);
        assert code == 0;
        sent_req = mock_urlopen.call_args[0][0];
        sent_payload = json.loads(sent_req.data.decode("utf-8"));
        assert sent_payload["salary"] == 120000;
        assert sent_payload["location"] == "New York";

        out = buf.getvalue();
        assert "Found 1 jobs for 'machine learning' in 'New York'" in out;
        assert "salary >= 120000" in out;
        assert "contract type: 'full-time'" in out;
        assert "company: 'Amazon'" in out;
        assert "Staff ML Engineer - Amazon AI (New York, NY)" in out;
        assert "Contract Type: Full-time" in out;
        assert "Salary: $160,000" in out;
    }

    buf_json: io.StringIO = io.StringIO();
    with patch("urllib.request.urlopen", return_value=mock_cm), patch("sys.stdout", buf_json) {
        # Test --json output
        code_json = main([
            "fetch", "machine learning",
            "-l", "New York",
            "-S", "120000",
            "--contract-type", "full-time",
            "--company", "Amazon",
            "--api-key", "test-api-key",
            "--json"
        ]);
        assert code_json == 0;
        json_out = json.loads(buf_json.getvalue());
        assert len(json_out) == 1;
        assert json_out[0]["id"] == "1";
        assert json_out[0]["company"] == "Amazon AI";
    }
}

test "main CLI runs fetch with individual filters and displays criteria accurately" {
    mock_payload = {
        "totalCount": 2,
        "jobs": [
            {
                "id": "1",
                "title": "Software Engineer",
                "company": "Google",
                "location": "Mountain View, CA",
                "salary": "$150,000",
                "type": "Full-time"
            },
            {
                "id": "2",
                "title": "Software Engineer",
                "company": "Amazon",
                "location": "Seattle, WA",
                "salary": "$90,000"
            }
        ]
    };
    mock_response = MagicMock();
    mock_response.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_response;

    # Individual salary filter
    buf_sal: io.StringIO = io.StringIO();
    with patch("urllib.request.urlopen", return_value=mock_cm), patch("sys.stdout", buf_sal) {
        code = main(["fetch", "software", "--salary", "120000", "--api-key", "test-api-key"]);
        assert code == 0;
        out = buf_sal.getvalue();
        assert "Found 1 jobs for 'software' (filters: salary >= 120000):" in out;
        assert "Google" in out;
        assert "Amazon" not in out;
    }

    # Individual contract-type filter
    buf_type: io.StringIO = io.StringIO();
    with patch("urllib.request.urlopen", return_value=mock_cm), patch("sys.stdout", buf_type) {
        code = main(["fetch", "software", "-t", "full-time", "--api-key", "test-api-key"]);
        assert code == 0;
        out = buf_type.getvalue();
        assert "Found 1 jobs for 'software' (filters: contract type: 'full-time'):" in out;
        assert "Contract Type: Full-time" in out;
        assert "Amazon" not in out;
    }

    # Individual company filter
    buf_comp: io.StringIO = io.StringIO();
    with patch("urllib.request.urlopen", return_value=mock_cm), patch("sys.stdout", buf_comp) {
        code = main(["fetch", "software", "-c", "Amazon", "--api-key", "test-api-key"]);
        assert code == 0;
        out = buf_comp.getvalue();
        assert "Found 1 jobs for 'software' (filters: company: 'Amazon'):" in out;
        assert "Amazon" in out;
        assert "Google" not in out;
        assert "Contract Type:" not in out;
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

# --- Web UI (Jaccit job application platform) ---

import from services.jobs { list_jobs }
import ".styles.global.css";
import ".components.LandingPage.css";

def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
