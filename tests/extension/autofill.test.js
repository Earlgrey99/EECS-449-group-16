// Run with: node --test tests/extension/autofill.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const { chooseOption, classify, classifyQuestion, matchKey, parseJobTitle } = require("../../extension/autofill.js");

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
    const result = classify({ label });
    assert.equal(result.key, null, label);
    assert.equal(result.sensitive, true, label);
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

test("handles what live hiring sites do", () => {
  // Greenhouse and Lever upload buttons, where only the name says "resume".
  assert.equal(keyFor({ label: "Attach", name: "resume", type: "file" }), "resume");
  assert.equal(keyFor({ label: "Resume/CV ATTACH RESUME/CV", name: "resume", type: "file" }), "resume");
  assert.equal(keyFor({ label: "Attach", name: "cover_letter", type: "file" }), null);
  assert.equal(keyFor({ label: "Cover letter", name: "resume", type: "file" }), null);
  assert.equal(keyFor({ label: "Location (City)*", name: "candidate-location" }), "location");
  assert.equal(keyFor({ label: "Github" }), "github");
  assert.equal(keyFor({ label: "Full name\u2731", name: "name" }), "name");
  // Left for the user.
  assert.equal(keyFor({ label: "Current company", name: "org" }), null);
  assert.equal(keyFor({ label: "Preferred First Name" }), null);
  assert.equal(keyFor({ label: "Other Website", name: "urls[Other]" }), null);
  assert.equal(keyFor({ label: "What country are you based in?" }), null);
  assert.equal(keyFor({ label: "Has someone at Linear referred you for this role?" }), null);
  assert.equal(keyFor({ label: "Get industry insights and updates", name: "email", type: "email" }), null);
});

test("guesses the job from real page titles", () => {
  const cases = {
    "Job Application for Account Executive, Enterprise at Figma": ["Account Executive, Enterprise", "Figma"],
    "Palantir Technologies - Administrative Business Partner": ["Administrative Business Partner", "Palantir Technologies"],
    "Spotify - Account Executive - Commercial": ["Account Executive - Commercial", "Spotify"],
    "Engineering Manager - EU @ Ashby": ["Engineering Manager - EU", "Ashby"],
    "AirCover Specialist - Careers at Airbnb": ["AirCover Specialist", "Airbnb"],
    "Data Analyst at Cascade Health": ["Data Analyst", "Cascade Health"],
    "Apply now": ["Apply now", ""],
  };
  for (const [title, [role, company]] of Object.entries(cases)) {
    assert.deepEqual(parseJobTitle(title), { role, company }, title);
  }
});

test("knows which saved answer a question asks for", () => {
  const cases = {
    "Are you legally authorized to work in the United States?": "work_authorized",
    "Are you authorized to work in the country for which you applied?": "work_authorized",
    "Will you now or in the future require sponsorship for employment visa status?": "needs_sponsorship",
    "Are you Hispanic/Latino?": "hispanic",
    "Please identify your race": "race",
    Gender: "gender",
    "Veteran Status": "veteran",
    "Disability Status": "disability",
    Pronouns: "pronouns",
    "Salary expectations": "salary",
    "Current company": "current_company",
    "Most recent employer": "current_company",
    "Current job title": "current_title",
    "School name": "school",
    "Degree": "degree",
    "Field of study": "major",
    "Graduation year": "grad_year",
    "Country*": "country",
    "What country are you based in?": "country",
    "Which country do you intend to work from?": "country",
  };
  for (const [text, key] of Object.entries(cases)) {
    assert.equal(classifyQuestion(text).question, key, text);
  }
  assert.deepEqual(classifyQuestion("Why do you want this job?"), {});
  assert.deepEqual(classifyQuestion("Do you require a visa?"), { sensitive: true });
});

test("never answers blocked questions", () => {
  for (const text of [
    "Password", "Social Security Number", "Passport number", "Date of birth", "What is your age range?",
    "Bank account", "Have you ever been convicted of a felony?", "Religion", "Sexual orientation",
    "Credit card number", "Driver's license number",
  ]) {
    assert.equal(classifyQuestion(text).blocked, true, text);
    assert.equal(classify({ label: text }).blocked, true, text);
  }
  assert.equal(classify({ label: "Question 9", name: "applicant_ssn" }).blocked, true);
});

test("picks only one clear option for a saved answer", () => {
  const yesNo = ["Yes", "No", "Prefer not to disclose"];
  assert.equal(chooseOption("work_authorized", "yes", yesNo), 0);
  assert.equal(chooseOption("work_authorized", "no", yesNo), 1);
  assert.equal(chooseOption("hispanic", "decline", yesNo), 2);

  const gender = ["Female", "Male", "Decline to self-identify"];
  assert.equal(chooseOption("gender", "woman", gender), 0);
  assert.equal(chooseOption("gender", "man", gender), 1);
  assert.equal(chooseOption("gender", "decline", gender), 2);
  assert.equal(chooseOption("gender", "man", ["Woman", "Man", "Non-binary"]), 1);
  assert.equal(chooseOption("gender", "nonbinary", ["Woman", "Man", "Non-binary"]), 2);

  const veteran = ["I am not a protected veteran", "I identify as one or more of the classifications of a protected veteran", "I don't wish to answer"];
  assert.equal(chooseOption("veteran", "no", veteran), 0);
  assert.equal(chooseOption("veteran", "yes", veteran), 1);
  assert.equal(chooseOption("veteran", "decline", veteran), 2);

  const disability = ["Yes, I have a disability", "No, I do not have a disability", "I do not wish to answer"];
  assert.equal(chooseOption("disability", "yes", disability), 0);
  assert.equal(chooseOption("disability", "no", disability), 1);
  assert.equal(chooseOption("disability", "decline", disability), 2);

  const race = ["Asian", "Black or African American", "White (Not Hispanic or Latino)", "Hispanic or Latino", "Two or More Races"];
  assert.equal(chooseOption("race", "white", race), 2);
  assert.equal(chooseOption("race", "hispanic", race), 3);
  assert.equal(chooseOption("race", "two_or_more", race), 4);

  assert.equal(chooseOption("country", "United States", ["Canada", "United States", "Mexico"]), 1);
  assert.equal(chooseOption("degree", "Bachelor", ["Bachelor's Degree", "Master's Degree"]), 0);
});

test("leaves the question when options are unclear", () => {
  assert.equal(chooseOption("work_authorized", "yes", ["Yes, with restrictions", "Yes, without restrictions", "No"]), -1);
  assert.equal(chooseOption("gender", "man", ["Option A", "Option B"]), -1);
  assert.equal(chooseOption("hispanic", "decline", ["Yes", "No"]), -1);
  assert.equal(chooseOption("country", "", ["Canada"]), -1);
  assert.equal(chooseOption("veteran", "yes", ["Yes", "Yes, recently separated"]), -1);
});
