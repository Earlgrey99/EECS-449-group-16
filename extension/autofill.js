/*
 * Finds and fills job application fields. Injected only when the user clicks a
 * button in the popup.
 *
 * Rules:
 *  - It never clicks or submits anything.
 *  - It never fills sensitive fields (see SENSITIVE).
 *  - A wrong answer is worse than a blank field, so unclear fields are left alone.
 */
(function (root) {
  "use strict";

  // Applicants must answer these themselves, even if we have a matching value.
  const SENSITIVE = new RegExp(
    "\\b(" +
      [
        "password", "passcode", "ssn", "social security", "passport", "credit card",
        "card number", "cvv", "bank", "routing", "tax id", "national id", "drivers? license",
        "date of birth", "birth date", "birthday", "dob", "age",
        "gender", "sex", "sexual orientation", "race", "racial", "ethnicity", "ethnic", "hispanic",
        "disability", "disabled", "veteran", "religion", "pronouns?",
        "salary", "compensation", "pay expectations?",
        "work authorization", "authorized to work", "authorised to work", "sponsorship",
        "visa", "citizenship", "citizen", "immigration",
        "criminal", "conviction", "felony",
      ].join("|") +
      ")\\b"
  );

  // More specific keys come first.
  const ALIASES = {
    first_name: ["first name", "firstname", "given name", "fname", "forename"],
    last_name: ["last name", "lastname", "surname", "family name", "lname"],
    name: ["name", "full name", "fullname", "applicant name", "candidate name"],
    email: ["email", "email address"],
    phone: [
      "phone", "phone number", "phone no", "mobile", "mobile number", "mobile phone",
      "cell", "cell phone", "telephone", "telephone number",
    ],
    location: [
      "location", "city", "current city", "current location", "city state", "location city",
      "city location",
    ],
    linkedin: ["linkedin", "linkedin url", "linkedin profile", "linkedin profile url"],
    github: ["github", "github url", "github profile", "github profile url"],
    portfolio: [
      "portfolio", "portfolio url", "website", "website url", "personal website", "personal site",
    ],
    resume: [
      "resume", "cv", "resume cv", "cv resume", "resume file", "upload resume",
      "attach resume", "upload your resume", "attach your resume",
    ],
  };

  const AUTOCOMPLETE = {
    "given-name": "first_name",
    "family-name": "last_name",
    name: "name",
    email: "email",
    tel: "phone",
    "tel-national": "phone",
    "address-level2": "location",
  };

  // Words allowed before an alias. Without this limit, "first name" would match
  // inside "emergency contact first name" and "name" inside "company name".
  const SAFE_PREFIX_WORDS = new Set([
    "job", "application", "applicant", "candidate", "your", "my", "the", "legal", "primary",
    "personal", "contact", "info", "information", "profile", "input", "field", "form",
    "section", "basic", "name", "urls", "url",
  ]);
  const UNSAFE_CONTEXT = /\b(emergency|reference|referr\w*|manager|supervisor|recruiter|company|employer|school|university|parent|spouse)\b/;

  const OTHER_DOCUMENT = /\b(cover|transcript|writing|portfolio|sample)\b/;

  const SKIPPED_TYPES = new Set([
    "hidden", "submit", "button", "reset", "image", "checkbox", "radio", "range", "color", "search",
  ]);

  const ATS_HOSTS = /(greenhouse\.io|lever\.co|ashbyhq\.com|myworkdayjobs\.com|icims\.com|smartrecruiters\.com|jobvite\.com|bamboohr\.com|workable\.com)$/;

  function normalize(value) {
    return String(value || "")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .replace(/\blinked in\b/g, "linkedin")
      .replace(/\bgit hub\b/g, "github")
      .replace(/\be mail\b/g, "email")
      .replace(/\b(required|optional)\b/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function matchKey(text) {
    const value = normalize(text);
    if (!value || UNSAFE_CONTEXT.test(value)) return null;
    for (const [key, aliases] of Object.entries(ALIASES)) {
      if (aliases.includes(value)) return key;
    }
    for (const [key, aliases] of Object.entries(ALIASES)) {
      for (const alias of aliases) {
        if (!value.endsWith(" " + alias)) continue;
        const prefix = value.slice(0, -alias.length).trim().split(" ");
        if (prefix.every((word) => SAFE_PREFIX_WORDS.has(word))) return key;
      }
    }
    return null;
  }

  /*
   * attrs: { type, autocomplete, label, placeholder, ariaLabel, name, id, automationId }
   * Returns { key, sensitive }. A visible label decides the match, because a field
   * labelled "Company" with name="name" is about the company.
   */
  function classify(attrs) {
    const type = String(attrs.type || "text").toLowerCase();
    const texts = [attrs.label, attrs.ariaLabel, attrs.placeholder, attrs.name, attrs.id, attrs.automationId];
    if (type === "password" || texts.some((text) => SENSITIVE.test(normalize(text)))) {
      return { key: null, sensitive: true };
    }

    let key = null;
    const auto = String(attrs.autocomplete || "").trim().toLowerCase().split(/\s+/).pop();
    const hasLabel = Boolean(normalize(attrs.label) || normalize(attrs.ariaLabel));
    if (hasLabel) {
      key = matchKey(attrs.label) || matchKey(attrs.ariaLabel);
    } else if (texts.some((text) => UNSAFE_CONTEXT.test(normalize(text)))) {
      return { key: null, sensitive: false };
    } else {
      for (const text of [attrs.placeholder, attrs.name, attrs.id, attrs.automationId]) {
        key = matchKey(text);
        if (key) break;
      }
      if (!key && type === "email") key = "email";
      if (!key && type === "tel") key = "phone";
    }
    if (!key && !hasLabel && AUTOCOMPLETE[auto]) key = AUTOCOMPLETE[auto];

    // Upload buttons often say only "Attach", so the field's name identifies a resume.
    if (!key && type === "file" && !OTHER_DOCUMENT.test(normalize(attrs.label))) {
      for (const text of [attrs.name, attrs.id, attrs.automationId]) {
        if (matchKey(text) === "resume") key = "resume";
      }
    }

    // A resume goes only into a file input, and a file input takes only a resume.
    if ((type === "file") !== (key === "resume")) key = null;
    return { key, sensitive: false };
  }

  // Reads only what the user can see, so a label's hidden error text doesn't count.
  function visibleText(node) {
    let text = "";
    node.childNodes.forEach((child) => {
      if (child.nodeType === 3) {
        text += child.textContent;
      } else if (child.nodeType === 1 && !child.matches("input, select, textarea, button") && child.getClientRects().length) {
        text += " " + visibleText(child);
      }
    });
    return text;
  }

  function textOfLabel(label) {
    return visibleText(label).replace(/\s+/g, " ").trim();
  }

  function labelFor(el, doc) {
    if (el.id) {
      const match = doc.querySelector('label[for="' + CSS.escape(el.id) + '"]');
      if (match) return textOfLabel(match);
    }
    const wrapping = el.closest("label");
    if (wrapping) return textOfLabel(wrapping);
    const labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy) {
      return labelledBy
        .split(/\s+/)
        .map((id) => doc.getElementById(id)?.textContent || "")
        .join(" ")
        .trim();
    }
    return "";
  }

  function describe(el, doc) {
    return {
      type: el.tagName === "INPUT" ? el.getAttribute("type") || "text" : el.tagName.toLowerCase(),
      autocomplete: el.getAttribute("autocomplete"),
      label: labelFor(el, doc),
      ariaLabel: el.getAttribute("aria-label"),
      placeholder: el.getAttribute("placeholder"),
      name: el.getAttribute("name"),
      id: el.id,
      automationId: el.getAttribute("data-automation-id"),
    };
  }

  function isUsable(el, type) {
    if (el.disabled || el.readOnly) return false;
    if (type === "file") return true; // Sites often hide the real file input behind a button.
    if (!el.getClientRects().length) return false;
    return el.ownerDocument.defaultView.getComputedStyle(el).visibility !== "hidden";
  }

  // Frameworks like React track the instance's value property, so the prototype's
  // setter is needed for the following input event to register as a change.
  function setNativeValue(el, value) {
    const proto = Object.getPrototypeOf(el);
    Object.getOwnPropertyDescriptor(proto, "value").set.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur"));
  }

  function selectOption(el, value) {
    const wanted = normalize(value);
    const option = Array.from(el.options).find(
      (opt) => wanted && (normalize(opt.textContent) === wanted || normalize(opt.value) === wanted)
    );
    if (!option) return false;
    setNativeValue(el, option.value);
    return true;
  }

  function resumeToFile(resume, win) {
    const content = String(resume.content || "");
    const match = content.match(/^data:([^;,]*)(;base64)?,(.*)$/s);
    if (!match) {
      return new win.File([content], "resume.txt", { type: "text/plain" });
    }
    const raw = match[2] ? win.atob(match[3]) : decodeURIComponent(match[3]);
    const bytes = Uint8Array.from(raw, (ch) => ch.charCodeAt(0));
    return new win.File([bytes], resume.title || "resume", {
      type: match[1] || "application/octet-stream",
    });
  }

  function attachResume(el, resume, win) {
    const accept = (el.getAttribute("accept") || "").toLowerCase();
    const file = resumeToFile(resume, win);
    const extension = "." + file.name.split(".").pop().toLowerCase();
    if (accept && !accept.split(",").some((part) => {
      const rule = part.trim();
      return rule === extension || rule === file.type || (rule.endsWith("/*") && file.type.startsWith(rule.slice(0, -1)));
    })) {
      return false;
    }
    const transfer = new win.DataTransfer();
    transfer.items.add(file);
    el.files = transfer.files;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  function hasValue(el, type) {
    if (type === "file") return el.files && el.files.length > 0;
    return String(el.value || "").trim() !== "";
  }

  function blockedApplicationFrames(doc) {
    const here = doc.location.origin;
    const links = [];
    doc.querySelectorAll("iframe[src]").forEach((frame) => {
      try {
        const url = new URL(frame.src, doc.baseURI);
        if (url.origin !== here && ATS_HOSTS.test(url.hostname)) links.push(url.href);
      } catch (_) {
        // A malformed src is not useful to report.
      }
    });
    return links;
  }

  /*
   * profile: flat values, plus optional resume { title, content }
   * options: { apply: boolean }
   * The report holds field labels and outcomes, never the values.
   */
  function run(profile, options, doc) {
    const win = doc.defaultView;
    const apply = Boolean(options && options.apply);
    const fields = [];
    let unmatched = 0;

    doc.querySelectorAll("input, textarea, select").forEach((el) => {
      const attrs = describe(el, doc);
      const type = String(attrs.type).toLowerCase();
      if (SKIPPED_TYPES.has(type)) return;

      const { key, sensitive } = classify(attrs);
      let label = (attrs.label || attrs.ariaLabel || attrs.placeholder || attrs.name || attrs.id || "Unnamed field").slice(0, 80);
      if (sensitive) {
        if (type !== "password") fields.push({ label, key: null, status: "sensitive" });
        return;
      }
      if (!key) {
        // Sites keep extra hidden file inputs, which aren't fields the user sees.
        if (type !== "file" && isUsable(el, type)) unmatched += 1;
        return;
      }
      if (!isUsable(el, type)) return;
      // Sites label upload buttons "Attach" and the like, which means nothing in a list.
      if (key === "resume") label = "Resume";

      const value = key === "resume" ? profile.resume : profile[key];
      if (!value) {
        fields.push({ label, key, status: "no_value" });
      } else if (hasValue(el, type)) {
        fields.push({ label, key, status: "kept" });
      } else if (!apply) {
        fields.push({ label, key, status: "ready" });
      } else {
        let done = true;
        if (key === "resume") done = attachResume(el, value, win);
        else if (el.tagName === "SELECT") done = selectOption(el, value);
        else setNativeValue(el, String(value));
        if (done) el.style.outline = "2px solid #2f9e6e";
        fields.push({ label, key, status: done ? "filled" : "not_fillable" });
      }
    });

    return {
      url: doc.location.href,
      title: doc.title,
      isTopFrame: win === win.top,
      fields,
      unmatched,
      blockedFrames: blockedApplicationFrames(doc),
    };
  }

  // Best guess from a page title, for the user to check before adding it to the tracker.
  function parseJobTitle(title) {
    const text = String(title || "").replace(/\s+/g, " ").trim();
    const patterns = [
      [/^Job Application for (.+) at (.+)$/i, 1, 2], // Greenhouse
      [/^(.+) - Careers at (.+)$/i, 1, 2],
      [/^(.+) @ (.+)$/, 1, 2], // Ashby
      [/^(.+?) - (.+)$/, 2, 1], // Lever: "Company - Role"
      [/^(.+) at (.+)$/i, 1, 2],
    ];
    for (const [pattern, role, company] of patterns) {
      const match = text.match(pattern);
      if (match) return { role: match[role].trim(), company: match[company].trim() };
    }
    return { role: text, company: "" };
  }

  const api = { classify, matchKey, normalize, parseJobTitle, run };
  root.LaunchpadAutofill = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
