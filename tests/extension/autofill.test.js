// Run with: node --test tests/extension/autofill.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const { classify, matchKey } = require("../../extension/autofill.js");

const keyFor = (attrs) => classify(attrs).key;

test("matches the labels real application forms use", () => {
  const cases = {
    "First Name": "first_name",
    "Legal first name": "first_name",
    "Last Name *": "last_name",
    Surname: "last_name",
    "Full Name": "name",
    Name: "name",
    "Your name": "name",
    "Email Address": "email",
    "E-mail (required)": "email",
    "Phone Number": "phone",
    "Mobile phone": "phone",
    "LinkedIn Profile": "linkedin",
    "LinkedIn URL": "linkedin",
    GitHub: "github",
    "Personal website": "portfolio",
    "Current location": "location",
  };
  for (const [label, expected] of Object.entries(cases)) {
    assert.equal(matchKey(label), expected, label);
  }
});

test("matches name attributes from common hiring systems", () => {
  assert.equal(keyFor({ name: "job_application[first_name]" }), "first_name");
  assert.equal(keyFor({ name: "candidate[email]" }), "email");
  assert.equal(keyFor({ name: "urls[LinkedIn]" }), "linkedin");
  assert.equal(keyFor({ automationId: "legalNameSection_firstName" }), "first_name");
  assert.equal(keyFor({ id: "firstName" }), "first_name");
});

test("does not fill fields about someone or something else", () => {
  const labels = [
    "Company name",
    "Current company",
    "Employer name",
    "School name",
    "Hiring manager name",
    "Emergency contact first name",
    "Emergency contact phone",
    "Reference email",
    "Referrer name",
    "Username",
    "Project name",
    "File name",
    "Cover letter",
    "How did you hear about us?",
  ];
  for (const label of labels) {
    assert.equal(keyFor({ label }), null, label);
  }
});

test("a visible label beats a misleading name attribute", () => {
  assert.equal(keyFor({ label: "Company", name: "name" }), null);
  assert.equal(keyFor({ label: "Why this role?", name: "email", type: "email" }), null);
  assert.equal(keyFor({ label: "Emergency contact", autocomplete: "tel", type: "tel" }), null);
});

test("uses autocomplete and input type only when there is no label", () => {
  assert.equal(keyFor({ autocomplete: "given-name" }), "first_name");
  assert.equal(keyFor({ autocomplete: "section-a email" }), "email");
  assert.equal(keyFor({ type: "email" }), "email");
  assert.equal(keyFor({ type: "tel" }), "phone");
  assert.equal(keyFor({ type: "email", name: "reference_email" }), null);
});

test("flags sensitive fields and never assigns them a value", () => {
  const labels = [
    "Gender",
    "Race / Ethnicity",
    "Are you Hispanic or Latino?",
    "Veteran status",
    "Disability status",
    "Date of birth",
    "Social Security Number",
    "Passport number",
    "Salary expectations",
    "Desired compensation",
    "Are you authorized to work in the US?",
    "Will you require visa sponsorship?",
    "Have you ever had a criminal conviction?",
    "Pronouns",
  ];
  for (const label of labels) {
    assert.deepEqual(classify({ label }), { key: null, sensitive: true }, label);
  }
  assert.equal(classify({ name: "ssn" }).sensitive, true);
  assert.equal(classify({ label: "Email", type: "password" }).sensitive, true);
  assert.equal(classify({ label: "Phone", name: "applicant_gender" }).sensitive, true);
});

test("sensitive words only match whole words", () => {
  assert.equal(classify({ label: "Stage" }).sensitive, false);
  assert.equal(classify({ label: "Embrace" }).sensitive, false);
  assert.equal(classify({ label: "Advisable" }).sensitive, false);
});

test("resumes only go in file inputs, and file inputs only take resumes", () => {
  assert.equal(keyFor({ label: "Resume/CV", type: "file" }), "resume");
  assert.equal(keyFor({ label: "Attach your resume", type: "file" }), "resume");
  assert.equal(keyFor({ label: "Resume", type: "text" }), null);
  assert.equal(keyFor({ label: "Cover letter", type: "file" }), null);
  assert.equal(keyFor({ label: "Name", type: "file" }), null);
});
