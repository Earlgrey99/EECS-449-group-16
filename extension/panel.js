"use strict";

/*
 * The on-page panel. It appears on hiring sites when a page has an application form,
 * and asks for profile data only after the user clicks Autofill. It lives in a shadow
 * root, so the site's styles don't change it and the site's scripts can't read it.
 */
(function () {
  if (window.__launchpadPanel) return;
  window.__launchpadPanel = true;

  const send = (message) => chrome.runtime.sendMessage(message);
  const PANEL_CSS = `
    :host { all: initial; }
    .panel { position: fixed; right: 16px; bottom: 16px; z-index: 2147483647; width: 300px; max-width: calc(100vw - 32px);
      max-height: calc(100vh - 32px); overflow-y: auto; box-sizing: border-box; padding: 12px 14px; border-radius: 12px;
      background: #fff; color: #1c2521; border: 1px solid #d9e0dc; box-shadow: 0 8px 28px rgba(0, 0, 0, .18);
      font: 13px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
    @media (prefers-color-scheme: dark) {
      .panel { background: #161b19; color: #e8eeeb; border-color: #36403b; }
      .muted, button.link, button.close { color: #a3aea8 !important; }
      button.secondary, input { color: #e8eeeb; border-color: #36403b !important; }
      button.primary { background: #4dbb8a !important; color: #0d1512 !important; }
      .warn { color: #e5ad5c !important; }
    }
    header { display: flex; align-items: center; justify-content: space-between; gap: 8px; font-weight: 600; font-size: 14px; }
    p { margin: 8px 0 0; overflow-wrap: anywhere; }
    .muted { color: #5f6b65; }
    .warn { color: #9a5b00; font-weight: 600; }
    ul { margin: 2px 0 0; padding-left: 16px; }
    li { overflow-wrap: anywhere; }
    button { font: inherit; cursor: pointer; border-radius: 8px; }
    button.primary { width: 100%; margin-top: 10px; padding: 8px 12px; border: 0; background: #23805a; color: #fff; font-weight: 600; }
    button.secondary { width: 100%; margin-top: 8px; padding: 7px 12px; background: transparent; border: 1px solid #d9e0dc; }
    button.link { padding: 0; border: 0; background: none; color: #5f6b65; text-decoration: underline; }
    button.close { padding: 0 4px; border: 0; background: none; color: #5f6b65; font-size: 16px; line-height: 1; }
    button:disabled { opacity: .6; cursor: default; }
    :focus-visible { outline: 2px solid #23805a; outline-offset: 2px; }
    label { display: block; margin-top: 8px; font-weight: 500; }
    input[type=text] { box-sizing: border-box; width: 100%; margin-top: 2px; padding: 6px 8px; border: 1px solid #d9e0dc; border-radius: 6px; background: transparent; font: inherit; color: inherit; }
    .footer { margin-top: 10px; display: flex; justify-content: space-between; gap: 8px; font-size: 12px; }
  `;

  const GROUPS = [
    { status: "check", title: "Pick from the suggestions" },
    { status: "not_fillable", title: "Couldn't match. Please answer", warn: true },
    { status: "no_value", title: "Not in your profile", warn: true },
    { status: "no_answer", title: "No saved answer", warn: true },
    { status: "sensitive", title: "Please answer these yourself", warn: true },
    { status: "blocked", title: "Launchpad never answers these", warn: true },
  ];

  let host = null;
  let body = null;
  let lastJob = null;

  const el = (tag, props = {}, ...children) => {
    const node = document.createElement(tag);
    Object.assign(node, props);
    node.append(...children);
    return node;
  };

  function mount() {
    if (host) return;
    host = document.createElement("div");
    host.id = "launchpad-autofill-panel";
    const shadow = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = PANEL_CSS;
    const panel = el("section", { className: "panel" });
    panel.setAttribute("aria-label", "Launchpad Autofill");
    const close = el("button", { className: "close", type: "button", textContent: "×" });
    close.setAttribute("aria-label", "Close Launchpad panel");
    close.addEventListener("click", () => {
      host.remove();
      host = null;
      dismissed = true;
    });
    body = el("div");
    panel.append(el("header", {}, el("span", { textContent: "Launchpad Autofill" }), close), body);
    shadow.append(style, panel);
    document.documentElement.append(host);
  }

  function setBody(...nodes) {
    mount();
    body.replaceChildren(...nodes);
  }

  function showFooter() {
    const settings = el("button", { className: "link", type: "button", textContent: "Saved answers" });
    settings.addEventListener("click", () => send({ type: "open_options" }));
    return el("div", { className: "footer" }, settings, el("span", { className: "muted", textContent: "You review and submit" }));
  }

  function showError(message) {
    setBody(el("p", { className: "warn", textContent: message }), autofillButton("Try again"), showFooter());
  }

  function autofillButton(text = "Autofill this application") {
    const button = el("button", { className: "primary", type: "button", textContent: text });
    button.addEventListener("click", () => fill(button));
    return button;
  }

  function showReady() {
    setBody(el("p", { className: "muted", textContent: "Fill this application from your Launchpad profile." }), autofillButton(), showFooter());
  }

  function showConnect(message) {
    const button = el("button", { className: "primary", type: "button", textContent: "Connect to Launchpad" });
    button.addEventListener("click", async () => {
      button.disabled = true;
      const result = await send({ type: "connect" });
      if (result.ok && result.connected) showReady();
      else showConnect(result.message || result.error || "Couldn't connect.");
    });
    setBody(el("p", { className: "muted", textContent: message || "Sign in to Launchpad, then connect." }), button);
  }

  function renderReport(report) {
    const filled = report.fields.filter((field) => field.status === "filled").length;
    const kept = report.fields.filter((field) => field.status === "kept").length;
    const nodes = [el("p", { textContent: `Filled ${filled} field${filled === 1 ? "" : "s"}${kept ? `, kept ${kept} you'd already answered` : ""}. Please review them.` })];
    for (const group of GROUPS) {
      const matching = report.fields.filter((field) => field.status === group.status);
      if (!matching.length) continue;
      nodes.push(el("p", { className: group.warn ? "warn" : "", textContent: group.title }));
      nodes.push(el("ul", {}, ...matching.map((field) => el("li", { textContent: field.label }))));
    }
    if (report.unmatched) {
      nodes.push(el("p", { className: "muted", textContent: `${report.unmatched} other question${report.unmatched === 1 ? "" : "s"} left for you.` }));
    }
    nodes.push(autofillButton("Fill again, for new fields"));
    nodes.push(showFooter());
    setBody(...nodes);
  }

  async function fill(button) {
    button.disabled = true;
    button.textContent = "Filling...";
    try {
      const result = await send({ type: "profile" });
      if (!result.ok) return showError(result.error);
      if (!result.connected) return showConnect(result.message);
      const report = await window.LaunchpadAutofill.run(result.profile, { apply: true }, document);
      lastJob = window.LaunchpadAutofill.parseJobTitle(document.title);
      renderReport(report);
    } catch (error) {
      showError(`Autofill failed: ${error.message || error}`);
    }
    return undefined;
  }

  function showTrack(job, url) {
    const role = el("input", { type: "text", value: job.role || "" });
    const company = el("input", { type: "text", value: job.company || "" });
    const add = el("button", { className: "primary", type: "button", textContent: "Add to tracker" });
    add.addEventListener("click", async () => {
      add.disabled = true;
      const result = await send({ type: "track", role: role.value, company: company.value, url });
      if (result.ok) setBody(el("p", { textContent: result.alreadyTracked ? "This job is already in your tracker." : "Added to your tracker." }));
      else {
        add.disabled = false;
        setBody(el("p", { className: "warn", textContent: result.error }));
      }
    });
    setBody(
      el("p", { textContent: "Submitted? Add it to your tracker." }),
      el("label", {}, "Job title", role),
      el("label", {}, "Company", company),
      add
    );
  }

  // Watches for the site's submit button. It only listens, and never presses it.
  function watchSubmit() {
    document.addEventListener("click", (event) => {
      const target = event.target.closest && event.target.closest('button, input[type="submit"]');
      if (!target || !event.isTrusted) return;
      const text = String(target.textContent || target.value || "");
      // Go by the text: a plain <button> counts as type="submit" by default.
      if (!/\b(submit|send application|apply)\b/i.test(text)) return;
      if (/\b(linkedin|indeed|search|subscribe|sign in|log in)\b/i.test(text)) return;
      const job = { ...(lastJob || window.LaunchpadAutofill.parseJobTitle(document.title)), url: location.href };
      send({ type: "remember_submit", job });
      showTrack(job, location.href);
    }, true);
  }

  let dismissed = false;

  function hasApplicationForm() {
    const fields = Array.from(document.querySelectorAll('input[type="file"], input[type="email"], input[type="tel"], input[name*="email" i], input[id*="email" i], textarea'));
    return fields.filter((field) => field.getClientRects().length || field.type === "file").length >= 2;
  }

  async function start() {
    const { job } = await send({ type: "recall_submit" });
    if (job && !hasApplicationForm()) {
      showTrack(job, job.url);
      return;
    }
    const offer = () => {
      if (dismissed || host || !hasApplicationForm()) return false;
      showReady();
      watchSubmit();
      return true;
    };
    if (offer()) return;
    // Many hiring sites build their forms after the page loads.
    const observer = new MutationObserver(() => {
      if (offer()) observer.disconnect();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => observer.disconnect(), 30000);
  }

  start();
})();
