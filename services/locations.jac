"""US city and state search based on data/uscities.csv.

Typing part of a state name (or its two-letter code) also suggests the whole
state, e.g. "Mich" or "MI" suggests "Michigan".
"""

import csv;
import os;
import re;

glob _CITIES_CACHE: list[dict[str, any]] = [];
glob _CITIES_LOADED: bool = False;

# Every US state plus DC, by two-letter code, so people can pick a whole state.
glob US_STATES: dict[str, str] = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
    "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
    "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
    "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
    "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
    "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
    "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
};
glob MAX_STATE_MATCHES: int = 4;

"""States whose name starts with the search, or whose code is the search.
"mi" gives Michigan first (its code), then Minnesota, Mississippi, Missouri."""
def search_states(query: str) -> list[str] {
    q = (query or "").strip().lower();
    if len(q) < 2 {
        return [];
    }
    matches: list[str] = [];
    for (state_code, full_name) in US_STATES.items() {
        if state_code.lower() == q {
            matches.append(full_name);
        }
    }
    for full_name in US_STATES.values() {
        if full_name.lower().startswith(q) and full_name not in matches {
            matches.append(full_name);
        }
    }
    return matches[:MAX_STATE_MATCHES];
}


"""True when a job's location is inside a place someone picked.

    "Columbus, OH" matches "Columbus, OH, USA"
    "Michigan"     matches "Detroit, MI" and "Ann Arbor, Michigan"
    "Remote"       matches any job whose location says remote
"""
def location_matches(target: str, job_location: str) -> bool {
    place = (target or "").strip().lower();
    job_loc = (job_location or "").strip().lower();
    if not place or not job_loc {
        return False;
    }
    if "remote" in place {
        return "remote" in job_loc;
    }
    if place in job_loc or job_loc in place {
        return True;
    }
    # A whole state: look for its two-letter code after a comma, like ", MI".
    for (state_code, full_name) in US_STATES.items() {
        if full_name.lower() == place {
            return re.search(r",\s*" + state_code.lower() + r"\b", job_loc) is not None;
        }
    }
    return False;
}


def _pop_key(item: dict[str, any]) -> int {
    val = item.get("pop", 0);
    return int(val) if isinstance(val, (int, float)) else 0;
}

def _load_cities -> list[dict[str, any]] {
    if _CITIES_LOADED {
        return _CITIES_CACHE;
    }
    filepath = os.path.join(os.path.dirname(__file__), "..", "data", "uscities.csv");
    if not os.path.exists(filepath) {
        alt = os.path.join(os.path.dirname(__file__), "..", "uscities.csv");
        if os.path.exists(alt) {
            filepath = alt;
        } else {
            return [];
        }
    }
    loaded: list[dict[str, any]] = [];
    try {
        with open(filepath, "r", encoding="utf-8") as f {
            reader = csv.DictReader(f);
            for row in reader {
                city = row.get("city", "").strip();
                state_id = row.get("state_id", "").strip();
                if not city or not state_id {
                    continue;
                }
                pop_raw = row.get("population", "0") or "0";
                try {
                    pop = int(float(pop_raw));
                } except ValueError {
                    pop = 0;
                }
                label = f"{city}, {state_id}";
                loaded.append({
                    "label": label,
                    "city": city,
                    "state": state_id,
                    "pop": pop
                });
            }
        }
    } except Exception {
        return [];
    }
    # Sort primarily by population descending so major cities rank highest
    loaded.sort(key=_pop_key, reverse=True);
    _CITIES_CACHE.extend(loaded);
    _CITIES_LOADED = True;
    return _CITIES_CACHE;
}

def:pub search_cities(query: str = "", limit: int = 15) -> list[str] {
    cities = _load_cities();
    q = (query or "").strip().lower();

    if not q {
        top_cities = ["Remote"];
        seen = set(["remote"]);
        for item in cities {
            lbl = str(item.get("label", ""));
            if lbl.lower() not in seen {
                seen.add(lbl.lower());
                top_cities.append(lbl);
            }
            if len(top_cities) >= limit {
                break;
            }
        }
        return top_cities;
    }

    results: list[str] = [];
    seen_res: set[str] = set();

    if "remote".startswith(q) or q in "remote" {
        results.append("Remote");
        seen_res.add("remote");
    }

    # Whole states come right after Remote, before cities.
    for state_name in search_states(q) {
        results.append(state_name);
        seen_res.add(state_name.lower());
    }

    prefix_matches: list[str] = [];
    contain_matches: list[str] = [];

    for item in cities {
        lbl = str(item.get("label", ""));
        lbl_low = lbl.lower();
        city_low = str(item.get("city", "")).lower();

        if lbl_low in seen_res {
            continue;
        }

        if city_low.startswith(q) or lbl_low.startswith(q) {
            prefix_matches.append(lbl);
            seen_res.add(lbl_low);
        } elif q in lbl_low {
            contain_matches.append(lbl);
            seen_res.add(lbl_low);
        }

        if len(prefix_matches) >= limit {
            break;
        }
    }

    results.extend(prefix_matches);
    for c in contain_matches {
        if len(results) >= limit {
            break;
        }
        results.append(c);
    }
    return results[:limit];
}
