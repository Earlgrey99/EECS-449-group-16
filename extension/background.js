"use strict";

/*
 * Holds the session token and talks to Launchpad, so the token never reaches a job
 * site's page. Only this extension's own scripts can send these messages.
 */

const DEFAULT_BASE = "http://localhost:8000";

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
    await chrome.storage.session.remove("token");
    throw new Error("Your Launchpad session has expired. Please connect again.");
  }
  if (!response.ok) throw new Error(`Launchpad returned an error (${response.status}).`);
  const payload = await response.json();
  return payload?.data?.result ?? {};
}

// Reads the token from a signed-in Launchpad tab, so the extension works for Google
// users too and never handles a password. Session storage clears it when the browser closes.
async function connect() {
  const base = await getBase();
  const [tab] = await chrome.tabs.query({ url: `${base}/*` });
  if (!tab) {
    await chrome.tabs.create({ url: `${base}/login` });
    return { connected: false, message: "Sign in to Launchpad in the new tab, then connect again." };
  }
  const [{ result: token }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => localStorage.getItem("jac_token"),
  });
  if (!token) {
    await chrome.tabs.update(tab.id, { active: true, url: `${base}/login` });
    return { connected: false, message: "Sign in to Launchpad in that tab, then connect again." };
  }
  await chrome.storage.session.set({ token });
  return { connected: true };
}

async function getAccount() {
  const { token } = await chrome.storage.session.get("token");
  if (!token) return { connected: false };
  const result = await callLaunchpad("get_user_profile_data", { token }, token);
  if (!result.ok) {
    await chrome.storage.session.remove("token");
    return { connected: false, message: result.error || "Couldn't load your profile." };
  }
  return { connected: true, user: result.user || {}, resume: result.latest_resume || null, answers: result.answers || {} };
}

// Demographic answers stay in this browser and are merged in only here.
async function buildProfile(includeResume) {
  const account = await getAccount();
  if (!account.connected) return account;
  const { user, resume } = account;
  const { demographics = {} } = await chrome.storage.local.get("demographics");
  const profile = {
    first_name: user.first_name || "",
    last_name: user.last_name || "",
    name: [user.first_name, user.last_name].filter(Boolean).join(" ") || user.name || "",
    email: user.email || "",
    phone: user.phone || "",
    // user.location holds target job locations, so city is where the user lives.
    location: user.city || "",
    linkedin: user.linkedin || "",
    github: user.github || "",
    portfolio: user.portfolio || "",
    answers: { ...account.answers, ...demographics },
  };
  if (resume && includeResume !== false) {
    profile.resume = { title: resume.title, content: resume.content };
  }
  return { connected: true, profile, resumeTitle: resume ? resume.title : "" };
}

async function addToTracker({ role, company, url }) {
  const { token } = await chrome.storage.session.get("token");
  if (!token) throw new Error("Connect to Launchpad first.");
  const now = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  const page = new URL(url);
  const result = await callLaunchpad("add_tracker_application", {
    token,
    role: String(role || "").trim(),
    company: String(company || "").trim(),
    applied_date: `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`,
    description: "",
    pay: null,
    status: "Applied",
    job_url: page.origin + page.pathname,
    salary_text: "",
  }, token);
  if (!result.ok) throw new Error(result.error || "Couldn't add this to your tracker.");
  return { alreadyTracked: Boolean(result.already_tracked) };
}

const HANDLERS = {
  connect,
  account: getAccount,
  profile: (message) => buildProfile(message.includeResume),
  disconnect: async () => {
    await chrome.storage.session.remove("token");
    return { connected: false };
  },
  track: addToTracker,
  // Remembers a submitted application across the thank-you page's load.
  remember_submit: async (message, sender) => {
    await chrome.storage.session.set({ [`submitted:${sender.tab.id}`]: message.job });
    return {};
  },
  recall_submit: async (message, sender) => {
    const key = `submitted:${sender.tab.id}`;
    const stored = await chrome.storage.session.get(key);
    await chrome.storage.session.remove(key);
    return { job: stored[key] || null };
  },
  open_options: async () => {
    await chrome.runtime.openOptionsPage();
    return {};
  },
  open_launchpad: async () => {
    await chrome.tabs.create({ url: `${await getBase()}/me` });
    return {};
  },
};

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  const handler = HANDLERS[message && message.type];
  if (!handler || sender.id !== chrome.runtime.id) return false;
  handler(message, sender)
    .then((result) => respond({ ok: true, ...result }))
    .catch((error) => respond({ ok: false, error: String(error.message || error) }));
  return true;
});
