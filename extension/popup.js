"use strict";

const DEFAULT_BASE = "http://localhost:8000";
const DETAIL_FIELDS = ["phone", "location", "linkedin", "github", "portfolio"];
const $ = (id) => document.getElementById(id);

let account = null;

const GROUPS = [
  { status: "filled", title: "Filled. Please review" },
  { status: "ready", title: "Ready to fill" },
  { status: "kept", title: "Already has a value, left unchanged" },
  { status: "no_value", title: "No saved value. Add it under Details", warn: true },
  { status: "not_fillable", title: "Couldn't fill. Please complete by hand", warn: true },
  { status: "sensitive", title: "Please answer these yourself", warn: true },
];

function showMessage(text, isError = false) {
  const el = $("message");
  el.textContent = text || "";
  el.hidden = !text;
  el.classList.toggle("error", isError);
}

async function getBase() {
  const { base } = await chrome.storage.local.get("base");
  return base || DEFAULT_BASE;
}

async function callLaunchpad(fn, body, token) {
  const base = await getBase();
  const response = await fetch(`${base}/function/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  if (response.status === 401) {
    const expired = new Error("Your Launchpad session has expired. Please connect again.");
    expired.expired = true;
    throw expired;
  }
  if (!response.ok) throw new Error(`Launchpad returned an error (${response.status}).`);
  const payload = await response.json();
  return payload?.data?.result ?? {};
}

// Reads the token from a signed-in Launchpad tab, so the extension works for
// Google users too and never handles a password. Session storage clears it when
// the browser closes.
async function connect() {
  const base = await getBase();
  const [tab] = await chrome.tabs.query({ url: `${base}/*` });
  if (!tab) {
    await chrome.tabs.create({ url: `${base}/login` });
    showMessage("Sign in to Launchpad in the new tab, then open this popup and connect again.");
    return;
  }
  const [{ result: token }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => localStorage.getItem("jac_token"),
  });
  if (!token) {
    await chrome.tabs.update(tab.id, { active: true, url: `${base}/login` });
    showMessage("Sign in to Launchpad in that tab, then open this popup and connect again.");
    return;
  }
  await chrome.storage.session.set({ token });
  await loadAccount();
}

async function disconnect() {
  await chrome.storage.session.remove("token");
  account = null;
  showMessage("");
  $("results").replaceChildren();
  render();
}

async function loadAccount() {
  const { token } = await chrome.storage.session.get("token");
  account = null;
  if (token) {
    try {
      const result = await callLaunchpad("get_user_profile_data", { token }, token);
      if (!result.ok) throw Object.assign(new Error(result.error || "Couldn't load your profile."), { expired: true });
      account = { user: result.user || {}, resume: result.latest_resume || null };
    } catch (error) {
      if (error.expired) await chrome.storage.session.remove("token");
      showMessage(error.message, true);
    }
  }
  render();
}

function render() {
  $("connect-view").hidden = Boolean(account);
  $("main-view").hidden = !account;
  if (!account) return;
  const { user, resume } = account;
  const name = [user.first_name, user.last_name].filter(Boolean).join(" ") || user.name || "";
  $("account-name").textContent = name ? `${name} (${user.email})` : user.email || "";
  $("resume-row").hidden = !resume;
  $("no-resume").hidden = Boolean(resume);
  if (resume) $("resume-title").textContent = resume.title || "Saved resume";
}

async function buildProfile() {
  const { user, resume } = account;
  const { details = {} } = await chrome.storage.local.get("details");
  const profile = {
    first_name: user.first_name || "",
    last_name: user.last_name || "",
    name: [user.first_name, user.last_name].filter(Boolean).join(" ") || user.name || "",
    email: user.email || "",
    phone: user.phone || "",
  };
  // The Launchpad location field holds target job locations, not where the user
  // lives, so only the City saved under Details is used for location.
  for (const field of DETAIL_FIELDS) {
    if (details[field]) profile[field] = details[field];
  }
  if (resume && $("include-resume").checked) {
    profile.resume = { title: resume.title, content: resume.content };
  }
  return profile;
}

async function targetTabId() {
  const fromQuery = new URLSearchParams(location.search).get("tab");
  if (fromQuery) return Number(fromQuery);
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab?.id;
}

async function runOnPage(apply) {
  showMessage("");
  $("preview").disabled = $("fill").disabled = true;
  try {
    const tabId = await targetTabId();
    const target = { tabId, allFrames: true };
    await chrome.scripting.executeScript({ target, files: ["autofill.js"] });
    const profile = await buildProfile();
    const frames = await chrome.scripting.executeScript({
      target,
      func: (values, isApply) => window.LaunchpadAutofill.run(values, { apply: isApply }, document),
      args: [profile, apply],
    });
    renderResults(frames.map((frame) => frame.result).filter(Boolean));
  } catch (error) {
    showMessage(friendlyInjectionError(error), true);
  } finally {
    $("preview").disabled = $("fill").disabled = false;
  }
}

function friendlyInjectionError(error) {
  const text = String(error?.message || error);
  if (/cannot access|cannot be scripted|extensions gallery|chrome:\/\//i.test(text)) {
    return "Autofill can't run on this page. Open a job application and try again.";
  }
  return `Autofill failed: ${text}`;
}

// Labels come from the job site, so they are only ever inserted as text.
function renderResults(reports) {
  const box = $("results");
  box.replaceChildren();
  const fields = reports.flatMap((report) => report.fields);
  const unmatched = reports.reduce((total, report) => total + report.unmatched, 0);

  for (const group of GROUPS) {
    const matching = fields.filter((field) => field.status === group.status);
    if (!matching.length) continue;
    const heading = document.createElement("h2");
    heading.textContent = `${group.title} (${matching.length})`;
    if (group.warn) heading.classList.add("warn");
    const list = document.createElement("ul");
    for (const field of matching) {
      const item = document.createElement("li");
      item.textContent = field.label;
      list.append(item);
    }
    box.append(heading, list);
  }

  if (unmatched) {
    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = `${unmatched} other field${unmatched === 1 ? "" : "s"} left for you to complete.`;
    box.append(note);
  }

  const blocked = reports.flatMap((report) => report.blockedFrames);
  if (blocked.length) {
    const note = document.createElement("p");
    note.textContent = "This application is embedded from another site. ";
    const link = document.createElement("a");
    link.href = blocked[0];
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = "Open it in its own tab";
    note.append(link, ", then try again.");
    box.append(note);
  }

  if (!fields.length && !blocked.length) {
    showMessage("No application fields found on this page.");
  }
}

async function loadDetailsForm() {
  const { details = {} } = await chrome.storage.local.get("details");
  const form = $("details-form");
  for (const field of DETAIL_FIELDS) form.elements[field].value = details[field] || "";
  form.elements.base.value = await getBase();
}

// Only http://localhost may be plain HTTP, because the session token travels to this address.
function parseBase(value) {
  const url = new URL(value);
  const isLocal = url.protocol === "http:" && url.host === "localhost:8000";
  if (!isLocal && url.protocol !== "https:") {
    throw new Error("Use https, or http://localhost:8000 for local development.");
  }
  return url.origin;
}

async function saveDetails(event) {
  event.preventDefault();
  const form = event.target;
  try {
    const base = parseBase(form.elements.base.value);
    if (base !== DEFAULT_BASE) {
      const granted = await chrome.permissions.request({ origins: [`${base}/*`] });
      if (!granted) throw new Error("Launchpad needs permission to reach that address.");
    }
    const details = {};
    for (const field of DETAIL_FIELDS) details[field] = form.elements[field].value.trim();
    const previous = await getBase();
    await chrome.storage.local.set({ details, base });
    if (previous !== base) await disconnect();
    showMessage("Saved.");
  } catch (error) {
    showMessage(error.message, true);
  }
}

$("connect").addEventListener("click", () => connect().catch((error) => showMessage(friendlyInjectionError(error), true)));
$("disconnect").addEventListener("click", disconnect);
$("preview").addEventListener("click", () => runOnPage(false));
$("fill").addEventListener("click", () => runOnPage(true));
$("details-form").addEventListener("submit", saveDetails);

loadDetailsForm();
loadAccount();
