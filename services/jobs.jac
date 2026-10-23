"""Job listings served to the search feed."""

glob JOBS: list[dict[str, str | int]] = [
    {"id": 1, "title": "Frontend Engineer", "company": "Lumen Labs", "location": "Cleveland, OH", "salary": "115,000", "type": "Full-time", "tags": "React, TypeScript, CSS"},
    {"id": 2, "title": "Backend Engineer", "company": "Northwind Data", "location": "Remote", "salary": "128,000", "type": "Full-time", "tags": "Python, SQL, APIs"},
    {"id": 3, "title": "Data Analyst", "company": "Cascade Health", "location": "Chicago, IL", "salary": "84,000", "type": "Full-time", "tags": "SQL, Dashboards, Python"},
    {"id": 4, "title": "Machine Learning Intern", "company": "Orbit AI", "location": "Pittsburgh, PA", "salary": "42,000", "type": "Internship", "tags": "PyTorch, NLP, Research"},
    {"id": 5, "title": "DevOps Engineer", "company": "Halcyon Cloud", "location": "Remote", "salary": "135,000", "type": "Full-time", "tags": "Kubernetes, Terraform, AWS"},
    {"id": 6, "title": "Product Designer", "company": "Marigold Studio", "location": "Cleveland, OH", "salary": "96,000", "type": "Contract", "tags": "Figma, Prototyping, UX"},
    {"id": 7, "title": "Software Engineer, New Grad", "company": "Bluepeak Systems", "location": "Columbus, OH", "salary": "98,000", "type": "Full-time", "tags": "Java, Spring, Distributed systems"},
    {"id": 8, "title": "QA Automation Engineer", "company": "Riverbend Software", "location": "Remote", "salary": "89,000", "type": "Part-time", "tags": "Playwright, Python, CI/CD"},
];

def:pub list_jobs() -> list[dict[str, str | int]] {
    return JOBS;
}