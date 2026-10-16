"""EECS-449-group-16 - a command-line Jac app.

Subcommands are declared with `argparse` and dispatched from the entry block.
Add one by registering a parser in `build_parser` and a branch in `main`.

    jac run main.jac -- greet Ada --shout
    jac run main.jac -- fetch "software engineer" -n 5
"""

import argparse;
import csv;
import datetime;
import io;
import json;
import os;
import sys;
import tempfile;
import urllib.error;
import urllib.request;
import from unittest.mock { MagicMock, patch }

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

def fetch(n: int, search: str, api_key: str | None = None) -> list[dict[str, any]] {
    if n <= 0 {
        return [];
    }
    load_env_file();
    key = api_key or os.environ.get("JOOBLE_API_KEY", "");
    if not key {
        raise ValueError("Jooble API key must be provided via JOOBLE_API_KEY env var, .env file, or --api-key argument.");
    }
    url = f"https://jooble.org/api/{key}";
    body = json.dumps({"keywords": search, "ResultOnPage": n}).encode("utf-8");
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"}
    );
    try {
        with urllib.request.urlopen(req) as resp {
            payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Jooble API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Jooble API network error: {e.reason}");
    }

    raw_jobs = payload.get("jobs", []) if isinstance(payload, dict) else [];
    return raw_jobs[:n];
}

def parse_fetch_args(args: argparse.Namespace) -> tuple[int, str] {
    n = 10;
    search = "";
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
    return (n, search);
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
    fetch_cmd.add_argument("-n", "--count", type=int, `default=None, help="Number of job listings to return");
    fetch_cmd.add_argument("-s", "--search", type=str, `default=None, help="Search keyword");
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
        (n, search) = parse_fetch_args(args);
        if not search {
            print("Error: 'search' argument is required.", file=sys.stderr);
            return 1;
        }
        try {
            jobs = fetch(n, search, api_key=args.api_key);
            if args.json {
                print(json.dumps(jobs, indent=2));
            } else {
                print(f"Found {len(jobs)} jobs for '{search}':\n");
                for (idx, job) in enumerate(jobs, 1) {
                    title = job.get("title", "No title");
                    company = job.get("company", "Unknown company");
                    location = job.get("location", "Unknown location");
                    salary = job.get("salary", "");
                    link = job.get("link", "");
                    print(f"{idx}. {title} - {company} ({location})");
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

    args1 = parser.parse_args(["fetch", "software", "-n", "5"]);
    (n1, s1) = parse_fetch_args(args1);
    assert n1 == 5;
    assert s1 == "software";

    args2 = parser.parse_args(["fetch", "5", "python"]);
    (n2, s2) = parse_fetch_args(args2);
    assert n2 == 5;
    assert s2 == "python";

    args3 = parser.parse_args(["fetch", "python", "5"]);
    (n3, s3) = parse_fetch_args(args3);
    assert n3 == 5;
    assert s3 == "python";

    args4 = parser.parse_args(["fetch", "developer"]);
    (n4, s4) = parse_fetch_args(args4);
    assert n4 == 10;
    assert s4 == "developer";
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

with entry:__main__ {
    sys.`exit(main());
}
