"use strict";

const form = document.getElementById("demographics");
const FIELDS = ["gender", "race", "hispanic", "veteran", "disability", "pronouns"];

async function load() {
  const { demographics = {} } = await chrome.storage.local.get("demographics");
  for (const field of FIELDS) form.elements[field].value = demographics[field] || "";
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const demographics = {};
  for (const field of FIELDS) {
    const value = form.elements[field].value.trim();
    if (value) demographics[field] = value;
  }
  await chrome.storage.local.set({ demographics });
  document.getElementById("saved").textContent = "Saved.";
});

document.getElementById("open-profile").addEventListener("click", () => chrome.runtime.sendMessage({ type: "open_launchpad" }));

load();
