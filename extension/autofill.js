/*
 * Finds and fills job application fields. Runs only after the user asks.
 *
 * Rules:
 *  - It never clicks a submit button or submits a form.
 *  - It never answers a BLOCKED question, even with a saved value.
 *  - Personal questions are answered only from answers the user saved.
 *  - A wrong answer is worse than a blank field, so unclear fields are left alone.
 */
(function (root) {
  "use strict";

  // Never filled, whatever the user has saved.
  const BLOCKED = new RegExp(
    "\\b(" +
      [
        "password", "passcode", "ssn", "social security", "passport", "credit card", "card number",
        "cvv", "bank", "routing", "tax id", "national id", "driver s license", "drivers? license", "date of birth",
        "birth date", "birthday", "dob", "age", "religion", "sexual orientation",
        "criminal", "conviction", "convicted", "felony",
      ].join("|") +
      ")\\b"
  );

  // Personal questions. Answered only from saved answers.
  const SENSITIVE = new RegExp(
    "\\b(" +
      [
        "gender", "sex", "race", "racial", "ethnicity", "ethnic", "hispanic", "latino", "latina", "latinx",
        "disability", "disabled", "veteran", "pronouns?", "salary", "compensation", "pay expectations?",
        "work authorization", "authorized to work", "authorised to work", "eligible to work",
        "right to work", "sponsorship", "sponsor", "visa", "citizenship", "citizen", "immigration",
      ].join("|") +
      ")\\b"
  );

  // Which saved answer a question asks for. More specific questions come first.
  const QUESTIONS = [
    ["needs_sponsorship", /\b(sponsor|sponsorship)\b/],
    ["work_authorized", /\b(authori[sz]ed|eligible|permitted|right) to work\b|\blegally (authori[sz]ed|eligible|permitted)\b|\bwork authori[sz]ation\b/],
    ["hispanic", /\b(hispanic|latino|latina|latinx)\b/],
    ["race", /\b(race|racial|ethnicity|ethnic)\b/],
    ["gender", /\b(gender|sex)\b/],
    ["veteran", /\bveteran\b/],
    ["disability", /\b(disability|disabled)\b/],
    ["pronouns", /\bpronouns?\b/],
    ["salary", /\b(salary|compensation|pay expectations?)\b/],
    ["start_date", /\b(start date|when can you start|earliest (start|date)|available to start)\b/],
    ["current_company", /\b(current|most recent|latest) (company|employer)\b/],
    ["current_title", /\b(current|most recent|latest) (job )?title\b/],
    ["grad_year", /\b(graduation|grad) (year|date)\b/],
    ["major", /\b(major|field of study|discipline|area of study)\b/],
    ["degree", /\bdegree\b/],
    ["school", /\b(school|university|college)\b/],
    ["country", /^(country|country of residence|what country are you based in|which country do you (live in|intend to work from))$/],
  ];

  // Saved answers that must match one option exactly as described here.
  const OPTION_RULES = {
    gender: {
      man: /^(man|male)\b/,
      woman: /^(woman|female)\b/,
      nonbinary: /^non ?binary\b/,
    },
    race: {
      asian: /^asian\b/,
      black: /^black\b/,
      hispanic: /^(hispanic|latin[oaxe])/,
      indigenous: /^(american indian|indigenous|alaska)/,
      pacific: /^(native hawaiian|pacific islander)/,
      white: /^white\b/,
      two_or_more: /^(two or more|multiracial)/,
    },
    veteran: {
      yes: /^(yes|i identify|i am a)\b(?!.*\bnot\b)/,
      no: /^no\b|\bnot a\b|\bi am not\b/,
    },
    disability: {
      yes: /^yes\b/,
      no: /^no\b/,
    },
  };
  const DECLINE = /\b(prefer not|decline|choose not|do not wish|don t wish|not to (disclose|answer|say)|rather not)\b/;

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
   * Decide what a question is asking. Returns:
   *   { blocked: true }        never fill
   *   { question: "gender" }   fill only from that saved answer
   *   { sensitive: true }      personal, and we have no saved answer type for it
   *   {}                       an ordinary question
   */
  function classifyQuestion(text) {
    const value = normalize(text);
    if (!value) return {};
    if (BLOCKED.test(value)) return { blocked: true };
    for (const [key, pattern] of QUESTIONS) {
      if (pattern.test(value)) return { question: key };
    }
    return SENSITIVE.test(value) ? { sensitive: true } : {};
  }

  /*
   * Pick the one option matching a saved answer, or return -1. If several options
   * could match, it returns -1 so the user can decide.
   */
  function chooseOption(key, answer, options) {
    const wanted = normalize(answer);
    if (!wanted) return -1;
    const normalized = options.map(normalize);
    let matches;
    if (wanted === "decline") {
      matches = normalized.map((text, i) => (DECLINE.test(text) ? i : -1));
    } else if (OPTION_RULES[key] && OPTION_RULES[key][answer]) {
      const rule = OPTION_RULES[key][answer];
      matches = normalized.map((text, i) => (!DECLINE.test(text) && rule.test(text) ? i : -1));
    } else if (wanted === "yes" || wanted === "no") {
      const rule = new RegExp("^" + wanted + "\\b");
      matches = normalized.map((text, i) => (!DECLINE.test(text) && rule.test(text) ? i : -1));
    } else {
      const exact = normalized.indexOf(wanted);
      if (exact >= 0) return exact;
      matches = normalized.map((text, i) => (text.startsWith(wanted + " ") ? i : -1));
    }
    const found = matches.filter((i) => i >= 0);
    return found.length === 1 ? found[0] : -1;
  }

  /*
   * attrs: { type, autocomplete, label, placeholder, ariaLabel, name, id, automationId }
   * Returns { key, sensitive, blocked, question }. A visible label decides the match,
   * because a field labelled "Company" with name="name" is about the company.
   */
  function classify(attrs) {
    const type = String(attrs.type || "text").toLowerCase();
    const texts = [attrs.label, attrs.ariaLabel, attrs.placeholder, attrs.name, attrs.id, attrs.automationId];
    const asked = texts.map(classifyQuestion);
    const personal = texts.some((text) => SENSITIVE.test(normalize(text)));
    const hasLabel = Boolean(normalize(attrs.label) || normalize(attrs.ariaLabel));
    if (type === "password" || asked.some((item) => item.blocked)) {
      return { key: null, sensitive: true, blocked: true };
    }
    // The label decides which saved answer, because names like "q1" say nothing.
    const labelled = classifyQuestion(attrs.label || attrs.ariaLabel);
    const question = labelled.question || (!hasLabel && asked.map((item) => item.question).find(Boolean)) || null;
    if (question && type !== "file") {
      return { key: null, sensitive: personal, question };
    }
    if (personal) {
      return { key: null, sensitive: true };
    }

    let key = null;
    const auto = String(attrs.autocomplete || "").trim().toLowerCase().split(/\s+/).pop();
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
      } else if (child.nodeType === 1 && !child.matches("input, select, textarea, button, option") && child.getClientRects().length) {
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

  /*
   * The question a control belongs to, for controls with no label of their own: the
   * closest surrounding text that doesn't include another question's controls.
   */
  function questionNear(el, skipText, controls) {
    const isOwn = (node) => controls.includes(node);
    let node = el.parentElement;
    for (let depth = 0; node && depth < 6; depth += 1, node = node.parentElement) {
      if (node.matches("body, form")) break;
      const others = Array.from(node.querySelectorAll("input, select, textarea, button")).filter(
        // An icon-only button, like a dropdown's arrow, isn't another question's control.
        (item) => !isOwn(item) && item.type !== "hidden" && item.getClientRects().length
          && (item.tagName !== "BUTTON" || item.textContent.trim())
      );
      if (others.length) break;
      const heading = node.querySelector(":scope > legend, :scope > label, :scope > [class*=label], :scope > [class*=title], :scope > [class*=question]");
      let text = textOfLabel(heading || node);
      for (const option of skipText) text = text.replace(option, " ");
      text = text.replace(/\s+/g, " ").trim();
      if (normalize(text)) return text;
    }
    return "";
  }

  function describe(el, doc) {
    let label = labelFor(el, doc);
    if (!label && el.getAttribute("role") === "combobox" && !el.getAttribute("aria-label")) {
      label = questionNear(el, [], [el]);
    }
    return {
      type: el.tagName === "INPUT" ? el.getAttribute("type") || "text" : el.tagName.toLowerCase(),
      autocomplete: el.getAttribute("autocomplete"),
      label,
      ariaLabel: el.getAttribute("aria-label"),
      placeholder: el.getAttribute("placeholder"),
      name: el.getAttribute("name"),
      id: el.id,
      automationId: el.getAttribute("data-automation-id"),
    };
  }

  function isVisible(el) {
    if (!el.getClientRects().length) return false;
    return el.ownerDocument.defaultView.getComputedStyle(el).visibility !== "hidden";
  }

  function isUsable(el, type) {
    if (el.disabled || el.readOnly) return false;
    if (type === "file") return true; // Sites often hide the real file input behind a button.
    return isVisible(el);
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

  function pressOn(el) {
    const init = { bubbles: true, cancelable: true, view: el.ownerDocument.defaultView, button: 0 };
    el.dispatchEvent(new MouseEvent("mousedown", init));
    el.dispatchEvent(new MouseEvent("mouseup", init));
    el.dispatchEvent(new MouseEvent("click", init));
  }

  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  function visibleOptions(doc) {
    return Array.from(doc.querySelectorAll('[role="option"], .select__option')).filter(isVisible);
  }

  async function waitForOptions(doc, timeout) {
    const deadline = Date.now() + timeout;
    let options = visibleOptions(doc);
    while (!options.length && Date.now() < deadline) {
      await wait(100);
      options = visibleOptions(doc);
    }
    return options;
  }

  function closeCombobox(el) {
    el.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", bubbles: true }));
    el.blur();
  }

  function comboboxHasValue(el) {
    const control = el.closest(".select__control");
    return Boolean(control && control.querySelector(".select__single-value, .select__multi-value")) || String(el.value || "").trim() !== "";
  }

  // A dropdown built from a text box and a popup list, like react-select.
  async function pickFromList(el, key, answer, doc) {
    el.focus();
    pressOn(el.closest(".select__control") || el);
    el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", code: "ArrowDown", bubbles: true }));
    const options = await waitForOptions(doc, 1500);
    // Some lists only appear after typing, such as a country lookup.
    if (!options.length) return typeAndPick(el, String(answer), doc);
    const index = chooseOption(key, answer, options.map((option) => option.textContent));
    if (index < 0) {
      closeCombobox(el);
      return false;
    }
    pressOn(options[index]);
    await wait(50);
    return true;
  }

  // A search box whose suggestions come from typing, such as a city lookup.
  async function typeAndPick(el, value, doc) {
    el.focus();
    setNativeValue(el, value);
    el.dispatchEvent(new KeyboardEvent("keydown", { key: value.slice(-1), bubbles: true }));
    const options = await waitForOptions(doc, 3000);
    const wanted = normalize(value);
    const match = options.find((option) => normalize(option.textContent).startsWith(wanted));
    if (!match) {
      closeCombobox(el);
      return false;
    }
    pressOn(match);
    await wait(50);
    return true;
  }

  function isCombobox(el) {
    return el.getAttribute("role") === "combobox" || el.getAttribute("aria-autocomplete") === "list";
  }

  function selectOption(el, key, value) {
    const options = Array.from(el.options);
    let index = chooseOption(key, value, options.map((opt) => opt.textContent));
    if (index < 0) {
      const wanted = normalize(value);
      index = options.findIndex((opt) => wanted && normalize(opt.value) === wanted);
    }
    if (index < 0) return false;
    setNativeValue(el, options[index].value);
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
    if (isCombobox(el)) return comboboxHasValue(el);
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

  function optionText(input, doc) {
    const byFor = input.id ? doc.querySelector('label[for="' + CSS.escape(input.id) + '"]') : null;
    const label = byFor || input.closest("label");
    return label ? textOfLabel(label) : String(input.value || "");
  }

  function markFilled(el) {
    el.style.outline = "2px solid #2f9e6e";
  }

  // Radio groups, checkbox groups, and Yes/No buttons: one question, several choices.
  function findChoiceGroups(doc) {
    const groups = [];
    const inputs = Array.from(doc.querySelectorAll('input[type="radio"], input[type="checkbox"]'));
    const byName = new Map();
    for (const input of inputs) {
      const label = input.closest("label") || (input.id ? doc.querySelector('label[for="' + CSS.escape(input.id) + '"]') : null);
      if (!isVisible(input) && !(label && isVisible(label))) continue;
      // Sites reuse names like "Prefer not to answer" across questions, so a surrounding
      // fieldset decides the group. Those checkboxes are grouped below.
      if (input.type === "checkbox" && input.closest('fieldset, [role="group"]')) continue;
      const key = input.type + ":" + (input.name || input.closest("fieldset, [role=group], [role=radiogroup], li, div")?.className || "");
      if (!byName.has(key)) byName.set(key, []);
      byName.get(key).push(input);
    }
    for (const controls of byName.values()) {
      if (controls.length < 2 && controls[0].type === "radio") continue;
      if (controls.length < 2) continue;
      const options = controls.map((input) => optionText(input, doc));
      groups.push({ kind: controls[0].type, controls, options, question: questionNear(controls[0], options, controls) });
    }

    // Checkboxes that each have their own name, grouped by their shared container.
    const loose = inputs.filter((input) => input.type === "checkbox" && !groups.some((group) => group.controls.includes(input)) && (input.closest("label") ? isVisible(input.closest("label")) : isVisible(input)));
    const byParent = new Map();
    for (const input of loose) {
      const container = input.closest('fieldset, [role="group"]') || (input.closest("label") || input).parentElement?.parentElement;
      if (!container) continue;
      if (!byParent.has(container)) byParent.set(container, []);
      byParent.get(container).push(input);
    }
    for (const controls of byParent.values()) {
      if (controls.length < 2) continue;
      const options = controls.map((input) => optionText(input, doc));
      groups.push({ kind: "checkbox", controls, options, question: questionNear(controls[0], options, controls) });
    }

    const buttons = Array.from(doc.querySelectorAll("button")).filter(
      (button) => /^(yes|no)$/i.test(button.textContent.trim()) && isVisible(button)
    );
    const byButtonParent = new Map();
    for (const button of buttons) {
      if (!byButtonParent.has(button.parentElement)) byButtonParent.set(button.parentElement, []);
      byButtonParent.get(button.parentElement).push(button);
    }
    for (const controls of byButtonParent.values()) {
      if (controls.length !== 2) continue;
      const options = controls.map((button) => button.textContent.trim());
      groups.push({ kind: "button", controls, options, question: questionNear(controls[0], options, controls) });
    }
    return groups;
  }

  function groupHasAnswer(group) {
    if (group.kind === "button") return group.controls.some((button) => button.getAttribute("aria-pressed") === "true");
    return group.controls.some((input) => input.checked);
  }

  function fillChoiceGroup(group, key, answer) {
    const index = chooseOption(key, answer, group.options);
    if (index < 0) return false;
    const control = group.controls[index];
    if (group.kind === "button") {
      pressOn(control);
    } else {
      control.click();
    }
    markFilled(group.kind === "button" ? control : control.closest("label") || control);
    return true;
  }

  function labelForReport(attrs) {
    return String(attrs.label || attrs.ariaLabel || attrs.placeholder || attrs.name || attrs.id || "Unnamed field").slice(0, 80);
  }

  async function fillField(el, type, key, value, doc, win) {
    if (key === "resume") return attachResume(el, value, win) ? "filled" : "not_fillable";
    if (el.tagName === "SELECT") return selectOption(el, key, value) ? "filled" : "not_fillable";
    if (isCombobox(el)) {
      if (key === "location") return (await typeAndPick(el, String(value), doc)) ? "filled" : "check";
      return (await pickFromList(el, key, value, doc)) ? "filled" : "not_fillable";
    }
    setNativeValue(el, String(value));
    return "filled";
  }

  /*
   * profile: flat values, optional resume { title, content }, optional answers { key: value }
   * options: { apply: boolean }
   * The report holds field labels and outcomes, never the values.
   */
  async function run(profile, options, doc) {
    const win = doc.defaultView;
    const apply = Boolean(options && options.apply);
    const answers = profile.answers || {};
    const fields = [];
    let unmatched = 0;

    const plan = [];
    doc.querySelectorAll("input, textarea, select").forEach((el) => {
      const attrs = describe(el, doc);
      const type = String(attrs.type).toLowerCase();
      if (SKIPPED_TYPES.has(type)) return;
      const label = labelForReport(attrs);
      const result = classify(attrs);
      if (result.blocked) {
        if (type !== "password" && isUsable(el, type)) fields.push({ label, key: null, status: "blocked" });
        return;
      }
      if (result.question) {
        if (isUsable(el, type)) plan.push({ el, type, label, key: result.question, value: answers[result.question], isAnswer: true, sensitive: result.sensitive });
        return;
      }
      if (result.sensitive) {
        if (isUsable(el, type)) fields.push({ label, key: null, status: "sensitive" });
        return;
      }
      if (!result.key) {
        // Sites keep extra hidden file inputs, which aren't fields the user sees.
        if (type !== "file" && isUsable(el, type)) unmatched += 1;
        return;
      }
      if (!isUsable(el, type)) return;
      plan.push({
        el, type, key: result.key, value: result.key === "resume" ? profile.resume : profile[result.key],
        // Sites label upload buttons "Attach" and the like, which means nothing in a list.
        label: result.key === "resume" ? "Resume" : label,
      });
    });

    // The resume goes first, because some sites fill fields from it after it uploads.
    plan.sort((a, b) => Number(b.key === "resume") - Number(a.key === "resume"));
    let uploaded = false;
    for (const item of plan) {
      const { el, type, key, value, label } = item;
      if (!value) {
        fields.push({ label, key, status: item.isAnswer ? (item.sensitive ? "sensitive" : "no_answer") : "no_value" });
      } else if (hasValue(el, type)) {
        fields.push({ label, key, status: "kept" });
      } else if (!apply) {
        fields.push({ label, key, status: "ready" });
      } else {
        const status = await fillField(el, type, key, value, doc, win);
        if (status === "filled") markFilled(el);
        if (status === "filled" && key === "resume") uploaded = true;
        fields.push({ label, key, status });
        if (uploaded && key === "resume") await wait(600);
      }
    }

    for (const group of findChoiceGroups(doc)) {
      const label = String(group.question || "Unnamed question").slice(0, 80);
      const asked = classifyQuestion(group.question);
      if (asked.blocked) {
        fields.push({ label, key: null, status: "blocked" });
      } else if (!asked.question) {
        if (asked.sensitive) fields.push({ label, key: null, status: "sensitive" });
        else unmatched += 1;
      } else {
        const answer = answers[asked.question];
        const personal = SENSITIVE.test(normalize(group.question));
        if (!answer) {
          fields.push({ label, key: asked.question, status: personal ? "sensitive" : "no_answer" });
        } else if (groupHasAnswer(group)) {
          fields.push({ label, key: asked.question, status: "kept" });
        } else if (chooseOption(asked.question, answer, group.options) < 0) {
          fields.push({ label, key: asked.question, status: "not_fillable" });
        } else if (!apply) {
          fields.push({ label, key: asked.question, status: "ready" });
        } else {
          fields.push({ label, key: asked.question, status: fillChoiceGroup(group, asked.question, answer) ? "filled" : "not_fillable" });
        }
      }
    }

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

  const api = { chooseOption, classify, classifyQuestion, matchKey, normalize, parseJobTitle, run };
  root.LaunchpadAutofill = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
