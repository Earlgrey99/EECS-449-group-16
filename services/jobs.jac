"""Job listings served to the search feed."""

glob JOBS: list[dict[str, str | int]] = [
    {"id": 1, "title": "Frontend Engineer", "company": "Lumen Labs", "location": "Cleveland, OH", "salary": "115,000", "type": "Full-time", "tags": "React, TypeScript, CSS", "desc": "Build accessible, fast interfaces for our analytics product alongside a small design-minded team."},
    {"id": 2, "title": "Backend Engineer", "company": "Northwind Data", "location": "Remote", "salary": "128,000", "type": "Full-time", "tags": "Python, SQL, APIs", "desc": "Design and scale the data services behind our real-time reporting pipelines."},
    {"id": 3, "title": "Data Analyst", "company": "Cascade Health", "location": "Chicago, IL", "salary": "84,000", "type": "Full-time", "tags": "SQL, Dashboards, Python", "desc": "Turn clinical data into clear dashboards that care teams use every day."},
    {"id": 4, "title": "Machine Learning Intern", "company": "Orbit AI", "location": "Pittsburgh, PA", "salary": "42,000", "type": "Internship", "tags": "PyTorch, NLP, Research", "desc": "Work with our research group on language models for document understanding."},
    {"id": 5, "title": "DevOps Engineer", "company": "Halcyon Cloud", "location": "Remote", "salary": "135,000", "type": "Full-time", "tags": "Kubernetes, Terraform, AWS", "desc": "Own the deployment platform that keeps our customer workloads healthy."},
    {"id": 6, "title": "Product Designer", "company": "Marigold Studio", "location": "Cleveland, OH", "salary": "96,000", "type": "Contract", "tags": "Figma, Prototyping, UX", "desc": "Shape product experiences for consumer apps from first sketch to shipped UI."},
    {"id": 7, "title": "Software Engineer, New Grad", "company": "Bluepeak Systems", "location": "Columbus, OH", "salary": "98,000", "type": "Full-time", "tags": "Java, Spring, Distributed systems", "desc": "Join our platform team building reliable services for logistics customers."},
    {"id": 8, "title": "QA Automation Engineer", "company": "Riverbend Software", "location": "Remote", "salary": "89,000", "type": "Part-time", "tags": "Playwright, Python, CI/CD", "desc": "Grow our end-to-end test suite so releases stay fast and dependable."},
];

def:pub list_jobs() -> list[dict[str, str | int]] {
    return JOBS;
}