"use strict";

const DEFAULT_BASE = "http://localhost:8000";
const $ = (id) => document.getElementById(id);
const send = (message) => chrome.runtime.sendMessage(message);

let account = null;
let pageUrl = "";

const GROUPS = [
  { status: "filled", title: "Filled. Please review" },
  { status: "ready", title: "Ready to fill" },
  { status: "kept", title: "Already has a value, left unchanged" },
  { status: "check", title: "Pick from the suggestions" },
  { status: "no_answer", title: "No saved answer", warn: true },
  { status: "no_value", title: "Not in your profile. Add it in Launchpad", warn: true },
  { status: "not_fillable", title: "Couldn't fill. Please complete by hand", warn: true },
  { status: "sensitive", title: "Please answer these yourself", warn: true },
  { status: "blocked", title: "Launchpad never answers these", warn: true },
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

async function connect() {
  const result = await send({ type: "connect" });
  if (!result.ok) throw new Error(result.error);
  if (!result.connected) {
    showMessage(result.message);
    return;
  }
  await loadAccount();
}

async function disconnect() {
  await send({ type: "disconnect" });
  account = null;
  showMessage("");
  $("results").replaceChildren();
  render();
}

async function loadAccount() {
  const result = await send({ type: "account" });
  account = null;
  if (result.ok && result.connected) {
    account = { user: result.user, resume: result.resume };
  } else if (result.error || result.message) {
    showMessage(result.error || result.message, true);
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
    const built = await send({ type: "profile", includeResume: $("include-resume").checked });
    if (!built.ok) throw new Error(built.error);
    if (!built.connected) {
      account = null;
      render();
      showMessage(built.message || "Please connect to Launchpad.");
      return;
    }
    const profile = built.profile;
    const frames = await chrome.scripting.executeScript({
      target,
      func: (values, isApply) => window.LaunchpadAutofill.run(values, { apply: isApply }, document),
      args: [profile, apply],
    });
    const reports = frames.map((frame) => frame.result).filter(Boolean);
    renderResults(reports);
    showTrackForm(reports);
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

// Offered once a page has application fields, with a guess the user can correct.
function showTrackForm(reports) {
  const top = reports.find((report) => report.isTopFrame) || reports[0];
  const hasFields = reports.some((report) => report.fields.length);
  $("track-form").hidden = !top || !hasFields;
  if (!top || !hasFields) return;
  const guess = window.LaunchpadAutofill.parseJobTitle(top.title);
  const form = $("track-form");
  if (!form.elements.role.value) form.elements.role.value = guess.role;
  if (!form.elements.company.value) form.elements.company.value = guess.company;
  pageUrl = top.url;
}

async function addToTracker(event) {
  event.preventDefault();
  const form = event.target;
  showMessage("");
  const result = await send({
    type: "track",
    role: form.elements.role.value,
    company: form.elements.company.value,
    url: pageUrl,
  });
  if (!result.ok) {
    showMessage(result.error, true);
    return;
  }
  form.hidden = true;
  showMessage(result.alreadyTracked ? "This job is already in your tracker." : "Added to your tracker.");
}

async function loadSettingsForm() {
  $("settings-form").elements.base.value = await getBase();
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

async function saveSettings(event) {
  event.preventDefault();
  const form = event.target;
  try {
    const base = parseBase(form.elements.base.value);
    if (base !== DEFAULT_BASE) {
      const granted = await chrome.permissions.request({ origins: [`${base}/*`] });
      if (!granted) throw new Error("Launchpad needs permission to reach that address.");
    }
    const previous = await getBase();
    await chrome.storage.local.set({ base });
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
$("settings-form").addEventListener("submit", saveSettings);
$("track-form").addEventListener("submit", addToTracker);
$("open-options").addEventListener("click", () => chrome.runtime.openOptionsPage());

loadSettingsForm();
loadAccount();
