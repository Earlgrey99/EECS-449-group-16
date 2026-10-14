"""EECS-449-group-16 - a command-line Jac app.

Subcommands are declared with `argparse` and dispatched from the entry block.
Add one by registering a parser in `build_parser` and a branch in `main`.

    jac run main.jac -- greet Ada --shout
    jac run main.jac -- fetch "software engineer" -n 5
    jac run main.jac -- fetch "software engineer" -n 5 -l "New York"
"""

import argparse;
import io;
import json;
import os;
import sys;
import urllib.error;
import urllib.request;
import from unittest.mock { MagicMock, patch }

def greet(name: str, shout: bool = False) -> str {
    message = f"Hello, {name}! This is EECS-449-group-16.";
    return message.upper() if shout else message;
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

def fetch(n: int, search: str, location: str | None = None, api_key: str | None = None) -> list[dict] {
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

    return parser;
}

def main(argv: list[str] | None = None) -> int {
    args = build_parser().parse_args(argv);
    if args.command == "greet" {
        print(greet(args.name, args.shout));
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
    }
    return 2;
}

test "greet returns default greeting" {
    assert greet("world") == "Hello, world! This is EECS-449-group-16.";
    assert greet("world", shout=True) == "HELLO, WORLD! THIS IS EECS-449-GROUP-16.";
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

with entry:__main__ {
    sys.`exit(main());
}
