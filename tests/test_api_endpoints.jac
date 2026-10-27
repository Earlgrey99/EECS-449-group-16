"""Unit and integration tests for multi-provider API endpoints and unified format."""

import json;
import os;
import urllib.request;
import from unittest.mock { MagicMock, patch }
import from main { build_parser, main }
import from services.jobs {
    build_jooble_url,
    build_usajobs_url,
    build_himalayas_url,
    build_themuse_url,
    normalize_jooble_job,
    normalize_usajobs_job,
    normalize_himalayas_job,
    normalize_themuse_job,
    fetch_jooble,
    fetch_usajobs,
    fetch_himalayas,
    fetch_themuse,
    fetch
}

# --- URL Construction Tests ---

test "build_jooble_url constructs default US and regional URLs" {
    # Default US domain
    assert build_jooble_url("test-key") == "https://jooble.org/api/test-key";

    # Regional domain without protocol
    assert build_jooble_url("test-key", domain="uk.jooble.org") == "https://uk.jooble.org/api/test-key";
    assert build_jooble_url("test-key", domain="ca.jooble.org") == "https://ca.jooble.org/api/test-key";

    # Regional domain with protocol and trailing slash
    assert build_jooble_url("test-key", domain="https://de.jooble.org/") == "https://de.jooble.org/api/test-key";
    assert build_jooble_url("test-key", domain="http://fr.jooble.org") == "https://fr.jooble.org/api/test-key";

    # Regional domain via JOOBLE_API_DOMAIN environment variable
    old_domain = os.environ.get("JOOBLE_API_DOMAIN");
    try {
        os.environ["JOOBLE_API_DOMAIN"] = "pl.jooble.org";
        assert build_jooble_url("test-key") == "https://pl.jooble.org/api/test-key";

        # Explicit domain parameter overrides environment variable
        assert build_jooble_url("test-key", domain="it.jooble.org") == "https://it.jooble.org/api/test-key";
    } finally {
        if old_domain is not None {
            os.environ["JOOBLE_API_DOMAIN"] = old_domain;
        } elif "JOOBLE_API_DOMAIN" in os.environ {
            del os.environ["JOOBLE_API_DOMAIN"];
        }
    }
}

test "build_jooble_url supports custom endpoint URLs" {
    # Custom endpoint with {key} placeholder
    assert build_jooble_url("test-key", endpoint="https://custom.jooble.com/v1/{key}") == "https://custom.jooble.com/v1/test-key";

    # Custom endpoint with base /api
    assert build_jooble_url("test-key", endpoint="https://custom.jooble.com/api") == "https://custom.jooble.com/api/test-key";

    # Custom static endpoint
    assert build_jooble_url("test-key", endpoint="https://custom.jooble.com/static-jobs") == "https://custom.jooble.com/static-jobs";
}

test "build endpoint URLs for USAJobs, Himalayas, and The Muse" {
    # USAJobs
    assert build_usajobs_url() == "https://data.usajobs.gov/api/search";
    assert build_usajobs_url(domain="custom.usajobs.gov") == "https://custom.usajobs.gov/api/search";
    assert build_usajobs_url(domain="https://custom.usajobs.gov/") == "https://custom.usajobs.gov/api/search";
    assert build_usajobs_url(endpoint="https://custom.gov/api") == "https://custom.gov/api";

    # Himalayas
    assert build_himalayas_url() == "https://himalayas.app/jobs/api/search";
    assert build_himalayas_url(domain="api.himalayas.app") == "https://api.himalayas.app/jobs/api/search";
    assert build_himalayas_url(endpoint="https://custom.himalayas.app/feed") == "https://custom.himalayas.app/feed";

    # The Muse
    assert build_themuse_url() == "https://www.themuse.com/api/public/jobs";
    assert build_themuse_url(domain="api.themuse.com") == "https://api.themuse.com/api/public/jobs";
    assert build_themuse_url(endpoint="https://custom.themuse.com/jobs") == "https://custom.themuse.com/jobs";
}

# --- Unified Normalizer Tests ---

test "normalizers output unified schema across all providers" {
    required_keys = ["id", "title", "company", "location", "salary", "type", "link", "snippet", "desc", "source", "tags"];

    # 1. Jooble
    raw_jooble = {
        "id": "1001",
        "title": "Full Stack Developer",
        "company": "Jooble Inc",
        "location": "Remote, US",
        "salary": "$125,000",
        "type": "Full-time",
        "link": "https://jooble.org/desc/1001",
        "snippet": "Develop full stack solutions."
    };
    norm_jooble = normalize_jooble_job(raw_jooble);
    for k in required_keys {
        assert k in norm_jooble, f"Jooble normalizer missing key: {k}";
    }
    assert norm_jooble["source"] == "jooble";
    assert norm_jooble["title"] == "Full Stack Developer";
    assert norm_jooble["company"] == "Jooble Inc";

    # 2. USAJobs
    raw_usajobs = {
        "MatchedObjectId": "USA999",
        "MatchedObjectDescriptor": {
            "PositionID": "USA999-ID",
            "PositionTitle": "IT Specialist (Software)",
            "OrganizationName": "Department of Commerce",
            "PositionLocationDisplay": "Washington, DC",
            "PositionURI": "https://data.usajobs.gov/jobs/999",
            "PositionSchedule": [{"Name": "Full Time"}],
            "PositionRemuneration": [{"MinimumRange": "110000", "MaximumRange": "145000"}],
            "QualificationSummary": "Experience in software design.",
            "JobCategory": [{"Name": "Information Technology"}]
        }
    };
    norm_usajobs = normalize_usajobs_job(raw_usajobs);
    for k in required_keys {
        assert k in norm_usajobs, f"USAJobs normalizer missing key: {k}";
    }
    assert norm_usajobs["source"] == "usajobs";
    assert norm_usajobs["id"] == "USA999";
    assert norm_usajobs["title"] == "IT Specialist (Software)";
    assert norm_usajobs["company"] == "Department of Commerce";
    assert norm_usajobs["location"] == "Washington, DC";
    assert "$110,000" in norm_usajobs["salary"];
    assert norm_usajobs["type"] == "Full Time";
    assert norm_usajobs["tags"] == "Information Technology";

    # 3. Himalayas
    raw_himalayas = {
        "guid": "him-1234",
        "title": "Lead Backend Engineer",
        "companyName": "Distributed Cloud Corp",
        "locationRestrictions": [{"name": "Worldwide"}, {"name": "United States"}],
        "employmentType": "Contractor",
        "minSalary": 140000,
        "maxSalary": 180000,
        "applicationLink": "https://himalayas.app/jobs/him-1234",
        "excerpt": "Architect backend microservices.",
        "description": "<p>Architect backend microservices.</p>",
        "categories": ["Engineering", "Python"]
    };
    norm_himalayas = normalize_himalayas_job(raw_himalayas);
    for k in required_keys {
        assert k in norm_himalayas, f"Himalayas normalizer missing key: {k}";
    }
    assert norm_himalayas["source"] == "himalayas";
    assert norm_himalayas["id"] == "him-1234";
    assert norm_himalayas["title"] == "Lead Backend Engineer";
    assert norm_himalayas["company"] == "Distributed Cloud Corp";
    assert norm_himalayas["location"] == "Worldwide, United States";
    assert "$140,000 - $180,000" == norm_himalayas["salary"];
    assert norm_himalayas["type"] == "Contractor";
    assert norm_himalayas["link"] == "https://himalayas.app/jobs/him-1234";

    # 4. The Muse
    raw_themuse = {
        "id": 8888,
        "name": "Senior DevOps Engineer",
        "company": {"name": "Muse Technologies", "short_name": "muse-tech"},
        "locations": [{"name": "San Francisco, CA"}],
        "type": "external",
        "refs": {"landing_page": "https://www.themuse.com/jobs/8888"},
        "contents": "<p>Manage Kubernetes infrastructure and cloud deployments.</p>",
        "categories": [{"name": "Software Engineering"}]
    };
    norm_themuse = normalize_themuse_job(raw_themuse);
    for k in required_keys {
        assert k in norm_themuse, f"The Muse normalizer missing key: {k}";
    }
    assert norm_themuse["source"] == "themuse";
    assert norm_themuse["id"] == "8888";
    assert norm_themuse["title"] == "Senior DevOps Engineer";
    assert norm_themuse["company"] == "Muse Technologies";
    assert norm_themuse["location"] == "San Francisco, CA";
    assert norm_themuse["link"] == "https://www.themuse.com/jobs/8888";
    assert norm_themuse["tags"] == "Software Engineering";
}

# --- Provider Fetch Tests with Mocked Responses ---

test "fetch queries USAJobs with correct headers and normalizes results" {
    mock_payload = {
        "SearchResult": {
            "SearchResultCount": 1,
            "SearchResultItems": [
                {
                    "MatchedObjectId": "USA-501",
                    "MatchedObjectDescriptor": {
                        "PositionTitle": "Data Scientist (AI/ML)",
                        "OrganizationName": "Department of Energy",
                        "PositionLocationDisplay": "Oak Ridge, TN",
                        "PositionURI": "https://usajobs.gov/job/501",
                        "PositionSchedule": [{"Name": "Full-time"}],
                        "PositionRemuneration": [{"MinimumRange": "125000", "MaximumRange": "160000"}],
                        "QualificationSummary": "Develop ML pipelines."
                    }
                }
            ]
        }
    };
    mock_resp = MagicMock();
    mock_resp.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_resp;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        jobs = fetch(
            5,
            "data scientist",
            source="usajobs",
            api_key="test-usajobs-key",
            location="Oak Ridge, TN"
        );
        assert mock_urlopen.called;
        sent_req = mock_urlopen.call_args[0][0];
        assert "data.usajobs.gov" in sent_req.full_url;
        assert "Keyword=data+scientist" in sent_req.full_url;
        assert "LocationName=Oak+Ridge%2C+TN" in sent_req.full_url;
        assert sent_req.headers.get("Authorization-key") == "test-usajobs-key";

        assert len(jobs) == 1;
        assert jobs[0]["source"] == "usajobs";
        assert jobs[0]["title"] == "Data Scientist (AI/ML)";
        assert jobs[0]["company"] == "Department of Energy";
        assert "$125,000" in jobs[0]["salary"];
    }
}

test "fetch queries Himalayas without requiring API key" {
    mock_payload = {
        "jobs": [
            {
                "guid": "him-77",
                "title": "Site Reliability Engineer",
                "companyName": "CloudScale Systems",
                "locationRestrictions": [{"name": "Remote"}],
                "employmentType": "Full Time",
                "minSalary": 130000,
                "maxSalary": 170000,
                "applicationLink": "https://himalayas.app/jobs/him-77",
                "excerpt": "Maintain distributed high-availability systems."
            }
        ]
    };
    mock_resp = MagicMock();
    mock_resp.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_resp;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        # Works without api_key
        jobs = fetch(3, "reliability", source="himalayas");
        assert mock_urlopen.called;
        sent_req = mock_urlopen.call_args[0][0];
        assert "himalayas.app/jobs/api/search" in sent_req.full_url;
        assert "q=reliability" in sent_req.full_url;

        assert len(jobs) == 1;
        assert jobs[0]["source"] == "himalayas";
        assert jobs[0]["title"] == "Site Reliability Engineer";
        assert jobs[0]["company"] == "CloudScale Systems";
    }
}

test "fetch queries The Muse and normalizes results" {
    mock_payload = {
        "page": 1,
        "results": [
            {
                "id": 901,
                "name": "Frontend Software Engineer",
                "company": {"name": "Pixel Labs"},
                "locations": [{"name": "New York, NY"}],
                "type": "Full-time",
                "refs": {"landing_page": "https://themuse.com/jobs/901"},
                "contents": "<p>Build delightful modern web applications with React.</p>",
                "categories": [{"name": "Software Engineering"}]
            }
        ]
    };
    mock_resp = MagicMock();
    mock_resp.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_resp;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        jobs = fetch(5, "Software Engineering", source="themuse");
        assert mock_urlopen.called;
        sent_req = mock_urlopen.call_args[0][0];
        assert "themuse.com/api/public/jobs" in sent_req.full_url;

        assert len(jobs) == 1;
        assert jobs[0]["source"] == "themuse";
        assert jobs[0]["title"] == "Frontend Software Engineer";
        assert jobs[0]["company"] == "Pixel Labs";
    }
}

test "fetch with source=all combines results from all providers" {
    jooble_payload = {
        "jobs": [
            {"id": "j1", "title": "Software Engineer", "company": "Jooble Tech", "location": "Remote", "salary": "$120,000"}
        ]
    };
    usajobs_payload = {
        "SearchResult": {
            "SearchResultItems": [
                {
                    "MatchedObjectId": "u1",
                    "MatchedObjectDescriptor": {
                        "PositionTitle": "Software Developer",
                        "OrganizationName": "Gov Tech",
                        "PositionLocationDisplay": "Washington, DC",
                        "PositionRemuneration": [{"MinimumRange": "115000"}]
                    }
                }
            ]
        }
    };
    himalayas_payload = {
        "jobs": [
            {"guid": "h1", "title": "Backend Software Engineer", "companyName": "Remote Inc", "minSalary": 130000}
        ]
    };
    themuse_payload = {
        "results": [
            {"id": 301, "name": "Software Engineer Lead", "company": {"name": "Muse Inc"}, "contents": "Software engineering lead."}
        ]
    };

    def mock_urlopen_router(req: any) -> any {
        url = str(req.full_url) if req?.full_url is not None else str(req);
        mock_resp = MagicMock();
        if "jooble.org" in url {
            mock_resp.read.return_value = json.dumps(jooble_payload).encode("utf-8");
        } elif "usajobs.gov" in url {
            mock_resp.read.return_value = json.dumps(usajobs_payload).encode("utf-8");
        } elif "himalayas.app" in url {
            mock_resp.read.return_value = json.dumps(himalayas_payload).encode("utf-8");
        } elif "themuse.com" in url {
            mock_resp.read.return_value = json.dumps(themuse_payload).encode("utf-8");
        } else {
            mock_resp.read.return_value = json.dumps({}).encode("utf-8");
        }
        mock_cm = MagicMock();
        mock_cm.__enter__.return_value = mock_resp;
        return mock_cm;
    }

    with patch("urllib.request.urlopen", side_effect=mock_urlopen_router) {
        jobs = fetch(
            10,
            "software",
            source="all",
            api_key="mock-key"
        );
        sources_found = [j["source"] for j in jobs];
        assert "jooble" in sources_found;
        assert "usajobs" in sources_found;
        assert "himalayas" in sources_found;
        assert "themuse" in sources_found;
        assert len(jobs) == 4;
    }
}

# --- CLI Argument Parsing Tests ---

test "CLI parser accepts --domain, --endpoint, and --source flags" {
    parser = build_parser();

    args1 = parser.parse_args(["fetch", "engineer", "--domain", "uk.jooble.org"]);
    assert args1.domain == "uk.jooble.org";
    assert args1.source == "jooble";

    args2 = parser.parse_args(["fetch", "developer", "--endpoint", "https://custom.api/v1/{key}"]);
    assert args2.endpoint == "https://custom.api/v1/{key}";

    args3 = parser.parse_args(["fetch", "designer", "--source", "usajobs"]);
    assert args3.source == "usajobs";

    args4 = parser.parse_args(["fetch", "analyst", "--provider", "himalayas"]);
    assert args4.source == "himalayas";

    args5 = parser.parse_args(["fetch", "manager", "--source", "all", "--domain", "de.jooble.org"]);
    assert args5.source == "all";
    assert args5.domain == "de.jooble.org";
}

test "main CLI runs fetch with regional domain and custom source" {
    mock_payload = {
        "jobs": [
            {
                "id": "uk-1",
                "title": "Cloud Architect",
                "company": "London Tech",
                "location": "London, UK",
                "salary": "£90,000",
                "link": "https://uk.jooble.org/desc/uk-1"
            }
        ]
    };
    mock_resp = MagicMock();
    mock_resp.read.return_value = json.dumps(mock_payload).encode("utf-8");
    mock_cm = MagicMock();
    mock_cm.__enter__.return_value = mock_resp;

    with patch("urllib.request.urlopen", return_value=mock_cm) as mock_urlopen {
        code = main([
            "fetch", "cloud",
            "--domain", "uk.jooble.org",
            "--api-key", "test-key"
        ]);
        assert code == 0;
        sent_req = mock_urlopen.call_args[0][0];
        assert "https://uk.jooble.org/api/test-key" in sent_req.full_url;

        # Test with --json output
        code_json = main([
            "fetch", "cloud",
            "--domain", "uk.jooble.org",
            "--api-key", "test-key",
            "--json"
        ]);
        assert code_json == 0;
    }
}
