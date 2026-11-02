"""US Cities search service based on data/uscities.csv."""

import csv;
import os;

glob _CITIES_CACHE: list[dict[str, any]] = [];
glob _CITIES_LOADED: bool = False;

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
