"""Launchpad web entry point. Run the command-line tools with: jac run main.jac -- <command>

The server exposes every public function named in this module as an HTTP endpoint,
so import only functions that are meant to be endpoints. Database helpers and CLI
code belong in other modules. See tests/identity_http_check.py.
"""

import sys;
import cli;
import from services.applicant_demo { review_resume_text }
import from services.auth_sync { sync_user_session, get_test_user_session }
import from services.compatibility { get_resume_match_scores }
import from services.jobs { list_jobs, get_user_tailored_jobs, search_jobs }
import from services.locations { search_cities }
import from services.profile_llm { submit_profile_and_generate_query, get_user_profile_data }

with entry:__main__ {
    sys.`exit(cli.main());
}

def:pub app(children: any) -> JsxElement {
    return <>{children}</>;
}
