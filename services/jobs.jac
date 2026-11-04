"""Job listings served to the search feed and multi-provider API fetcher."""

import base64;
import json;
import os;
import re;
import urllib.error;
import urllib.parse;
import urllib.request;
import from db { load_env_file, get_user_by_email, get_user_by_oauth_id }
import from .auth_sync { resolve_token_identity }

glob JOBS: list[dict[str, str | int]] = [
    {"id": 1, "title": "Frontend Engineer", "company": "Lumen Labs", "location": "Cleveland, OH", "salary": "115,000", "type": "Full-time", "tags": "React, TypeScript, CSS, Next.js, Tailwind, GraphQL, Jest, Web Performance", "desc": "About Lumen Labs:\nLumen Labs builds real-time analytics, observability dashboards, and data exploration tools trusted by fast-growing engineering teams. We take pride in responsive interactions, accessible design, and pixel-perfect software craft.\n\nAbout the Role:\nWe are looking for a Frontend Engineer to lead UI development across our primary web application. You will collaborate closely with product designers and backend engineers to build slick, accessible data visualization components that render tens of thousands of telemetry points smoothly in the browser.\n\nKey Responsibilities:\n\u2022 Architect, build, and maintain high-performance web applications using React, TypeScript, and Next.js.\n\u2022 Translate Figma prototypes into responsive, accessible, and cross-browser compliant UI components.\n\u2022 Optimize client-side render cycles, bundle sizes, and state synchronization for data-dense dashboards.\n\u2022 Integrate frontend clients with GraphQL and REST APIs, handling error states and optimistic updates gracefully.\n\u2022 Write comprehensive unit, integration, and visual regression test suites using Jest and React Testing Library.\n\u2022 Participate in design critiques, code reviews, and help establish frontend engineering standards.\n\nRequired Qualifications:\n\u2022 3+ years of professional software engineering experience focusing on modern frontend web development.\n\u2022 Deep proficiency in JavaScript/TypeScript, React (hooks, context, lifecycle), and semantic HTML5/CSS3.\n\u2022 Demonstrated experience with modern CSS frameworks such as Tailwind CSS and modular CSS architectures.\n\u2022 Solid understanding of web fundamentals, DOM APIs, browser caching, and Core Web Vitals optimization.\n\u2022 Experience consuming GraphQL schemas or RESTful endpoints with client libraries like TanStack Query or Apollo.\n\nNice to Have:\n\u2022 Experience with charting libraries (D3.js, Recharts, or Chart.js) for large-scale data visualization.\n\u2022 Familiarity with end-to-end testing frameworks such as Playwright or Cypress.\n\u2022 Experience with design systems, Storybook, and WCAG 2.1 AA accessibility guidelines.\n\nWhat We Offer:\n\u2022 Competitive base salary ($115,000) with equity incentives.\n\u2022 Comprehensive employee insurance package (dental, vision, life, and wellness plans).\n\u2022 Hybrid work policy in Cleveland, OH with home office stipend.\n\u2022 $2,000 annual professional development and conference budget.\n\u2022 Flexible paid time off and parental leave.", "link": "", "snippet": "Build accessible, high-performance interfaces for our streaming analytics platform alongside a design-minded team.", "source": "local", "logo": ""},
    {"id": 2, "title": "Backend Engineer", "company": "Northwind Data", "location": "Remote", "salary": "128,000", "type": "Full-time", "tags": "Python, SQL, APIs, PostgreSQL, Docker, Redis, FastAPI, Distributed systems", "desc": "About Northwind Data:\nNorthwind Data provides enterprise-grade data orchestration, automated synchronization, and cloud storage management for distributed organizations. Our infrastructure processes over 50 million events every day with high availability and rigorous data integrity.\n\nAbout the Role:\nAs a Backend Engineer on our Platform Services team, you will design, implement, and maintain high-throughput backend services and APIs. You will work on optimizing database queries, handling asynchronous task queues, and ensuring our distributed data pipelines remain fast, fault-tolerant, and observable.\n\nKey Responsibilities:\n\u2022 Architect, build, and deploy scalable backend services and microservices using Python and FastAPI/Django.\n\u2022 Design schema migrations, indexing strategies, and query optimizations for PostgreSQL and Redis clusters.\n\u2022 Develop robust RESTful APIs and streaming endpoints consumed by web clients and third-party integrations.\n\u2022 Containerize services using Docker and manage deployments across multi-region cloud environments.\n\u2022 Implement monitoring, structured logging, and alerting to proactively identify and resolve bottlenecks.\n\u2022 Conduct thorough code reviews and mentor team members in backend software engineering best practices.\n\nRequired Qualifications:\n\u2022 3+ years of backend engineering experience developing production web services in Python.\n\u2022 Strong command of SQL, relational data modeling, transactions, and performance profiling in PostgreSQL.\n\u2022 Experience designing and maintaining production REST APIs with clear documentation and versioning.\n\u2022 Hands-on familiarity with Docker containerization, Linux environments, and CI/CD pipelines.\n\u2022 Solid grasp of distributed systems concepts, asynchronous programming (asyncio, Celery), and caching patterns.\n\nNice to Have:\n\u2022 Experience with message brokers such as Kafka, RabbitMQ, or AWS SQS.\n\u2022 Familiarity with Kubernetes, Terraform, and cloud platforms (AWS or GCP).\n\u2022 Knowledge of database replication, connection pooling (PgBouncer), and high-availability topologies.\n\nWhat We Offer:\n\u2022 Competitive remote salary ($128,000) and equity package.\n\u2022 Fully remote work with flexible hours across US time zones.\n\u2022 Comprehensive employee insurance package including dental, vision, and disability plans.\n\u2022 401(k) retirement plan with 4% company match.\n\u2022 Annual learning budget and generous home office setup allowance.", "link": "", "snippet": "Design and scale the resilient data services and high-throughput APIs behind our real-time analytics platform.", "source": "local", "logo": ""},
    {"id": 3, "title": "Data Analyst", "company": "Cascade Health", "location": "Chicago, IL", "salary": "84,000", "type": "Full-time", "tags": "SQL, Dashboards, Python, Data analysis, Tableau, Excel, Healthcare, Statistics", "desc": "About Cascade Health:\nCascade Health is a leading healthcare technology and analytics provider dedicated to improving patient clinical outcomes, reducing hospital readmissions, and optimizing clinical workflow efficiencies across regional hospital networks.\n\nAbout the Role:\nWe are seeking an inquisitive Data Analyst to join our Clinical Intelligence division. In this role, you will analyze clinical, operational, and population health datasets to generate actionable insights and interactive dashboards that guide hospital administrators and clinical staff in making data-driven decisions.\n\nKey Responsibilities:\n\u2022 Formulate advanced SQL queries to extract, transform, and aggregate complex electronic health records (EHR) and claims data.\n\u2022 Build, publish, and maintain interactive visual dashboards and automated KPI reports using Tableau and Python.\n\u2022 Collaborate with medical directors, nurse managers, and hospital executives to understand workflow challenges and translate clinical questions into analytical models.\n\u2022 Conduct statistical analyses to evaluate the efficacy of patient care programs and identify trends in clinical outcomes.\n\u2022 Perform data validation and quality verification reviews to ensure strict compliance with healthcare data governance and HIPAA standards.\n\u2022 Present analytical findings, forecasts, and strategic recommendations in concise, accessible executive summaries.\n\nRequired Qualifications:\n\u2022 2+ years of professional experience in data analytics, business intelligence, or healthcare informatics.\n\u2022 Advanced proficiency in SQL (window functions, CTEs, subqueries, complex multi-table joins).\n\u2022 Hands-on experience developing dashboards and reports using Tableau, Power BI, or similar BI tools.\n\u2022 Practical experience with Python data manipulation libraries (pandas, numpy) or R for exploratory data analysis.\n\u2022 Strong analytical mindset with experience in statistical testing, cohort analysis, and trend forecasting.\n\u2022 Bachelor\u2019s degree in Data Analytics, Health Informatics, Statistics, Computer Science, or equivalent practical experience.\n\nNice to Have:\n\u2022 Familiarity with healthcare data standards (HL7, FHIR, ICD-10, CPT) and EHR platforms (Epic, Cerner).\n\u2022 Experience working with cloud data warehouses such as Snowflake, BigQuery, or Amazon Redshift.\n\u2022 Prior experience presenting data findings to clinical or non-technical stakeholders.\n\nWhat We Offer:\n\u2022 Base salary of $84,000 plus performance bonus.\n\u2022 Hybrid work flexibility in Chicago, IL (2 days in office).\n\u2022 Premium health, dental, and vision plans.\n\u2022 Generous retirement contribution and wellness perks.", "link": "", "snippet": "Turn clinical and operational healthcare data into actionable visual dashboards that care teams and leadership rely on.", "source": "local", "logo": ""},
    {"id": 4, "title": "Machine Learning Intern", "company": "Orbit AI", "location": "Pittsburgh, PA", "salary": "42,000", "type": "Internship", "tags": "PyTorch, NLP, Research, Machine learning, Python, Hugging Face, Transformers, Data analysis", "desc": "About Orbit AI:\nOrbit AI is an applied artificial intelligence research lab developing multimodal foundation models and intelligent document parsing solutions for legal, scientific, and enterprise workflows.\n\nAbout the Role:\nWe are offering a summer and fall Machine Learning Internship for students passionate about natural language processing and computer vision. You will work directly with our research scientists and ML engineers to design, train, and benchmark novel transformer architectures on specialized domain datasets.\n\nKey Responsibilities:\n\u2022 Prototype, train, and evaluate deep learning models using PyTorch, Hugging Face Transformers, and distributed GPU clusters.\n\u2022 Curate, preprocess, and augment large-scale text and multimodal document datasets for pretraining and fine-tuning.\n\u2022 Benchmark model performance against industry baselines and analyze failure modes across challenging edge cases.\n\u2022 Implement optimization techniques including quantization, LoRA, and speculative decoding to reduce inference latencies.\n\u2022 Document experimental results clearly and present findings during weekly lab symposiums.\n\nRequired Qualifications:\n\u2022 Currently enrolled in a Bachelor's, Master's, or PhD program in Computer Science, Machine Learning, Data Science, or related quantitative field.\n\u2022 Strong programming fundamentals in Python and solid experience with PyTorch or TensorFlow.\n\u2022 Understanding of core machine learning principles, neural network architectures, attention mechanisms, and optimization algorithms.\n\u2022 Familiarity with NLP concepts, tokenization, embeddings, and modern transformer models.\n\u2022 Demonstrated curiosity through academic research, open-source contributions, or Kaggle/personal ML projects.\n\nNice to Have:\n\u2022 Experience with large language model fine-tuning frameworks (PEFT, DeepSpeed, vLLM).\n\u2022 Coursework or research in document analysis, optical character recognition (OCR), or multimodal learning.\n\u2022 Authorship or co-authorship on peer-reviewed research papers (ACL, EMNLP, CVPR, NeurIPS).\n\nWhat We Offer:\n\u2022 Competitive internship compensation ($42,000 annualized / $3,500 monthly stipend).\n\u2022 Full access to high-performance GPU compute clusters (H100/A100).\n\u2022 Direct mentorship from PhD research scientists and former university faculty.\n\u2022 Flexible hybrid schedule in Pittsburgh, PA with relocation assistance for eligible students.", "link": "", "snippet": "Work with our research group on language models and multimodal document understanding architectures.", "source": "local", "logo": ""},
    {"id": 5, "title": "DevOps Engineer", "company": "Halcyon Cloud", "location": "Remote", "salary": "135,000", "type": "Full-time", "tags": "Kubernetes, Terraform, AWS, Docker, CI/CD, Linux, Prometheus, Python", "desc": "About Halcyon Cloud:\nHalcyon Cloud provides automated infrastructure management, zero-trust cloud security, and reliability engineering tools for enterprise engineering teams running mission-critical workloads.\n\nAbout the Role:\nWe are seeking a DevOps Engineer to take ownership of our cloud infrastructure and deployment automation. You will scale our multi-region Kubernetes clusters on AWS, write modular infrastructure-as-code with Terraform, and streamline CI/CD pipelines to ensure our developers can ship code rapidly and reliably.\n\nKey Responsibilities:\n\u2022 Architect, provision, and maintain resilient multi-cluster AWS environments using Terraform and infrastructure-as-code principles.\n\u2022 Oversee production Kubernetes (EKS) operations including node group scaling, ingress controllers, service meshes, and security policies.\n\u2022 Build, maintain, and optimize continuous integration and deployment (CI/CD) pipelines using GitHub Actions.\n\u2022 Implement comprehensive observability, distributed tracing, and metrics alerting using Prometheus, Grafana, and OpenTelemetry.\n\u2022 Enforce cloud security compliance, secret management (HashiCorp Vault / AWS Secrets Manager), and least-privilege IAM policies.\n\u2022 Participate in an on-call rotation and lead post-incident reviews to drive continuous platform reliability improvements.\n\nRequired Qualifications:\n\u2022 3+ years of professional DevOps, Site Reliability, or Cloud Platform Engineering experience.\n\u2022 Hands-on expertise managing production Kubernetes clusters and containerized applications with Docker.\n\u2022 Advanced Terraform proficiency for provisioning cloud infrastructure across AWS services (EKS, VPC, RDS, S3, IAM).\n\u2022 Strong Linux systems administration skills, shell scripting (Bash), and automation scripting with Python or Go.\n\u2022 Proven experience designing automated CI/CD pipelines and zero-downtime deployment strategies (blue/green, canary).\n\nNice to Have:\n\u2022 CKA (Certified Kubernetes Administrator) or AWS Certified Solutions Architect credential.\n\u2022 Experience with GitOps deployment workflows using ArgoCD or Flux.\n\u2022 Familiarity with service mesh technologies (Istio, Linkerd) and network security policies.\n\nWhat We Offer:\n\u2022 Competitive compensation ($135,000 base salary) plus equity.\n\u2022 100% remote flexibility with home office stipend.\n\u2022 Comprehensive employee insurance package including dental, vision, and disability plans.\n\u2022 Unlimited paid time off with mandatory 3-week minimum policy.\n\u2022 $2,500 annual conference and continuous education stipend.", "link": "", "snippet": "Own and scale the automated cloud infrastructure, container platforms, and CI/CD pipelines powering our global SaaS platform.", "source": "local", "logo": ""},
    {"id": 6, "title": "Product Designer", "company": "Marigold Studio", "location": "Cleveland, OH", "salary": "96,000", "type": "Contract", "tags": "Figma, Prototyping, UX, User research, Design systems, UI, Mobile design, Wireframing", "desc": "About Marigold Studio:\nMarigold Studio is a boutique design consultancy and venture studio that partners with innovative startups and high-growth brands to build human-centered consumer digital products.\n\nAbout the Role:\nWe are looking for a creative and detail-oriented Product Designer on a contract basis to lead the UX and UI design for two consumer mobile and web applications. You will shepherd projects from early discovery and wireframing through high-fidelity interactive prototypes ready for engineering implementation.\n\nKey Responsibilities:\n\u2022 Lead end-to-end design sprints, including user journey mapping, wireframing, high-fidelity UI design, and interactive prototyping in Figma.\n\u2022 Conduct qualitative user research interviews, usability testing sessions, and survey analyses to validate design hypotheses.\n\u2022 Expand and maintain our comprehensive Figma design system, ensuring consistent component libraries, tokens, and typography.\n\u2022 Partner with product managers to define feature scopes, user stories, and acceptance criteria.\n\u2022 Work hand-in-hand with UI developers during implementation to review builds and polish micro-interactions and animations.\n\nRequired Qualifications:\n\u2022 3+ years of professional digital product design experience across mobile (iOS/Android) and responsive web applications.\n\u2022 Mastery of Figma, including advanced auto-layout, component variants, variable modes, and interactive prototyping.\n\u2022 Solid understanding of user-centered design methodologies, information architecture, and accessibility standards (WCAG).\n\u2022 Strong portfolio demonstrating your design process, user problem-solving, and visually compelling shipped digital products.\n\u2022 Clear verbal and written communication skills with ability to articulate design rationale to cross-functional stakeholders.\n\nNice to Have:\n\u2022 Familiarity with basic web code (HTML, CSS concepts) to facilitate engineering handoffs.\n\u2022 Experience with micro-animation tools like Principle, Rive, or After Effects (Lottie).\n\u2022 Background designing for e-commerce, lifestyle, or social consumer apps.\n\nWhat We Offer:\n\u2022 Competitive contract rate ($96,000 annualized equivalent).\n\u2022 6-month contract with strong potential for extension or full-time conversion.\n\u2022 Flexible hybrid schedule in Cleveland, OH or remote within the region.\n\u2022 High-impact, collaborative design team environment.", "link": "", "snippet": "Shape intuitive and delightful product experiences for consumer applications from first sketch to shipped UI.", "source": "local", "logo": ""},
    {"id": 7, "title": "Software Engineer, New Grad", "company": "Bluepeak Systems", "location": "Columbus, OH", "salary": "98,000", "type": "Full-time", "tags": "Java, Spring, Distributed systems, SQL, Git, REST, Docker, Agile", "desc": "About Bluepeak Systems:\nBluepeak Systems engineers mission-critical enterprise software powering logistics, inventory management, and freight dispatch for global supply chain leaders. Our high-throughput systems coordinate millions of freight miles every day.\n\nAbout the Role:\nWe are seeking motivated recent graduates and entry-level Software Engineers to join our core Platform Engineering team in Columbus, OH. You will participate in the design, development, and maintenance of resilient microservices and distributed data processing pipelines under the mentorship of senior engineers.\n\nKey Responsibilities:\n\u2022 Build backend business services and RESTful APIs using Java and the Spring Boot ecosystem.\n\u2022 Write clean, testable, well-documented code backed by comprehensive JUnit and integration tests.\n\u2022 Collaborate with team members to design relational database schemas and write optimized SQL queries in PostgreSQL.\n\u2022 Participate in daily agile standups, sprint planning, and retrospective meetings.\n\u2022 Learn cloud-native architectures, containerization with Docker, and CI/CD deployment automation.\n\u2022 Diagnose production incidents, analyze diagnostic logs, and implement bug fixes with senior peer guidance.\n\nRequired Qualifications:\n\u2022 Bachelor's or Master's degree in Computer Science, Software Engineering, Computer Engineering, or related technical discipline (recent grad or graduating within 6 months).\n\u2022 Strong foundational knowledge in Java, C++, or another object-oriented programming language.\n\u2022 Solid understanding of data structures, algorithms, object-oriented design patterns, and relational databases (SQL).\n\u2022 Experience using Git version control and modern IDEs (IntelliJ IDEA, VS Code).\n\u2022 Collaborative attitude, strong problem-solving skills, and passion for continuous learning.\n\nNice to Have:\n\u2022 Prior internship experience in backend software engineering or web application development.\n\u2022 Coursework or personal projects using Spring Boot, Docker, or cloud platforms (AWS, Azure).\n\u2022 Familiarity with asynchronous messaging (Kafka, RabbitMQ) or distributed system concepts.\n\nWhat We Offer:\n\u2022 Competitive starting salary ($98,000) with annual performance bonus.\n\u2022 Structured 6-month technical onboarding and dedicated senior engineer mentorship.\n\u2022 Comprehensive employee insurance package starting Day 1 with dental and vision.\n\u2022 401(k) with 5% immediate company match.\n\u2022 Columbus, OH office with free parking, commuter benefits, and hybrid work flexibility.", "link": "", "snippet": "Join our core platform engineering team building reliable, distributed services for global logistics and supply chain networks.", "source": "local", "logo": ""},
    {"id": 8, "title": "QA Automation Engineer", "company": "Riverbend Software", "location": "Remote", "salary": "89,000", "type": "Part-time", "tags": "Playwright, Python, CI/CD, Selenium, Test automation, Git, QA, APIs", "desc": "About Riverbend Software:\nRiverbend Software develops enterprise workflow automation, digital compliance, and contract intelligence software for corporate and legal institutions.\n\nAbout the Role:\nWe are looking for a QA Automation Engineer to join our team on a part-time basis (20-25 hours/week). You will be responsible for creating, expanding, and maintaining automated end-to-end browser tests and API validation suites that run automatically on every pull request.\n\nKey Responsibilities:\n\u2022 Build, enhance, and maintain automated UI test suites using Playwright and Python.\n\u2022 Develop automated integration tests against RESTful backend endpoints to verify data contracts and edge conditions.\n\u2022 Integrate test suites into GitHub Actions CI/CD workflows, reducing flakiness and optimizing parallel test execution.\n\u2022 Perform exploratory and regression testing on newly developed features prior to production releases.\n\u2022 Create detailed, reproducible bug reports with network logs, steps to reproduce, and output logs.\n\u2022 Collaborate with software developers to advocate for testability, automated coverage, and software quality best practices.\n\nRequired Qualifications:\n\u2022 2+ years of professional quality assurance experience with strong emphasis on automated testing.\n\u2022 Proficiency with Python and modern browser automation frameworks (Playwright or Selenium).\n\u2022 Hands-on experience testing RESTful APIs using tools like Postman, Requests, or Pytest.\n\u2022 Familiarity with Git version control and integrating test suites into CI/CD pipelines (GitHub Actions).\n\u2022 Clear analytical thinking with an eye for subtle UI regressions and edge cases.\n\nNice to Have:\n\u2022 Experience with performance or load testing tools (Locust, k6, JMeter).\n\u2022 Understanding of web accessibility standards (WCAG) and automated accessibility inspection tools.\n\u2022 Familiarity with PostgreSQL and writing SQL queries to verify backend data states.\n\nWhat We Offer:\n\u2022 Competitive hourly compensation ($89,000 annualized equivalent).\n\u2022 Flexible part-time hours (approx. 20-25 hrs/week) with 100% remote autonomy.\n\u2022 Opportunity to transition to full-time as the QA practice expands.\n\u2022 Equipment stipend and software subscriptions provided.", "link": "", "snippet": "Grow our end-to-end and API test automation suites so releases stay fast, dependable, and regression-free.", "source": "local", "logo": ""},
    {"id": 9, "title": "Software Engineer", "company": "Vanguard Tech", "location": "Remote", "salary": "118,000", "type": "Full-time", "tags": "Python, TypeScript, React, PostgreSQL, Docker, REST, Microservices, Git", "desc": "About Vanguard Tech:\nVanguard Tech builds secure enterprise collaboration and document workflow solutions utilized by Fortune 500 enterprises worldwide.\n\nAbout the Role:\nWe are hiring a Software Engineer to join our Core Applications team. In this full-stack role, you will build user-friendly client interfaces in React and TypeScript while developing high-throughput microservices in Python. You will work on everything from real-time collaborative document editing to asynchronous export pipelines.\n\nKey Responsibilities:\n\u2022 Develop full-stack software features spanning modern web client applications (React, TypeScript) and backend APIs (Python).\n\u2022 Build and maintain reliable RESTful endpoints and asynchronous background workers.\n\u2022 Design and optimize relational database models in PostgreSQL for high concurrency and zero data loss.\n\u2022 Deploy and support services in Docker containers running on cloud infrastructure.\n\u2022 Participate in technical design RFCs, peer code reviews, and sprint planning meetings.\n\u2022 Troubleshoot issues across the stack to ensure optimal performance, security, and uptime.\n\nRequired Qualifications:\n\u2022 2-4 years of professional full-stack software engineering experience.\n\u2022 Solid programming proficiency in Python and TypeScript/JavaScript.\n\u2022 Experience building responsive single-page web applications with React.\n\u2022 Practical knowledge of relational database design, SQL querying, and ORMs (SQLAlchemy, Django ORM).\n\u2022 Understanding of containerization (Docker), version control (Git), and CI/CD pipelines.\n\nNice to Have:\n\u2022 Experience with WebSockets or real-time state synchronization.\n\u2022 Familiarity with cloud platforms (AWS or GCP) and serverless functions.\n\u2022 Knowledge of Redis caching and Celery task queues.\n\nWhat We Offer:\n\u2022 Base salary of $118,000 plus equity incentives.\n\u2022 Fully remote work policy across North American time zones.\n\u2022 Comprehensive employee insurance package including dental, vision, and disability plans.\n\u2022 401(k) matching and annual wellness stipend.\n\u2022 $1,500 annual home office setup and tech equipment refresh allowance.", "link": "https://jooble.org", "snippet": "Build accessible, fast web applications and microservices across core cloud platform services.", "source": "jooble", "logo": ""},
    {"id": 10, "title": "Full Stack Software Engineer", "company": "Beacon Health Systems", "location": "Remote", "salary": "124,000", "type": "Full-time", "tags": "React, Node.js, TypeScript, Next.js, PostgreSQL, REST, Tailwind, Docker", "desc": "About Beacon Health Systems:\nBeacon Health Systems develops innovative digital health solutions, patient engagement portals, and clinical decision support systems that empower clinicians and patients alike.\n\nAbout the Role:\nWe are looking for a Full Stack Software Engineer to help build our next-generation telehealth and patient care portal platform. You will work across the entire stack\u2014designing intuitive, HIPAA-compliant patient interfaces with React and Next.js, and architecting robust, secure backend services in Node.js and TypeScript.\n\nKey Responsibilities:\n\u2022 Architect, build, and deploy full-stack web applications using React, Next.js, and Node.js with TypeScript.\n\u2022 Create clean, accessible UI components utilizing Tailwind CSS and headless component libraries.\n\u2022 Design and maintain secure, authenticated REST APIs backed by PostgreSQL databases.\n\u2022 Implement strict security controls, data encryption, and activity logging to ensure HIPAA compliance.\n\u2022 Write unit, integration, and end-to-end tests to guarantee patient care data integrity and application reliability.\n\u2022 Collaborate with healthcare compliance officers, UX researchers, and clinical stakeholders.\n\nRequired Qualifications:\n\u2022 3+ years of professional full-stack web development experience.\n\u2022 High proficiency with React, TypeScript, Node.js, and modern CSS frameworks (Tailwind CSS).\n\u2022 Experience building and securing production REST APIs and handling authentication (JWT, OAuth2).\n\u2022 Strong SQL and relational database modeling skills in PostgreSQL.\n\u2022 Commitment to writing clean, maintainable, and well-tested code.\n\nNice to Have:\n\u2022 Prior experience in healthtech, medical software, or working with HIPAA/HITRUST requirements.\n\u2022 Experience with GraphQL or Next.js server components.\n\u2022 Familiarity with Docker containerization and cloud deployments.\n\nWhat We Offer:\n\u2022 Competitive base salary ($124,000) with annual performance bonus.\n\u2022 100% remote work flexibility.\n\u2022 Top-tier medical, dental, and vision benefits.\n\u2022 401(k) with company match.\n\u2022 Generous paid time off, mental health days, and parental leave.", "link": "https://jooble.org", "snippet": "Develop modern healthcare web applications, telehealth portals, and responsive clinical dashboards.", "source": "jooble", "logo": ""},
    {"id": 11, "title": "Senior Software Engineer", "company": "Apex Learning", "location": "Remote", "salary": "145,000", "type": "Full-time", "tags": "Python, Django, PostgreSQL, Redis, AWS, Distributed systems, Docker, CI/CD", "desc": "About Apex Learning:\nApex Learning is an educational technology leader providing personalized digital curricula, automated grading platforms, and classroom analytics to school districts across the globe.\n\nAbout the Role:\nWe are seeking a Senior Software Engineer to lead the architecture and scaling of our core instructional backend platform. You will tackle complex technical challenges involving high-concurrency student testing sessions, real-time grading analytics, and data pipeline integrations that support millions of active learners.\n\nKey Responsibilities:\n\u2022 Lead the architecture, technical design, and implementation of distributed backend services using Python and Django.\n\u2022 Optimize relational databases and caching architectures across PostgreSQL and Redis to handle peak morning traffic spikes.\n\u2022 Architect resilient background processing and asynchronous message queues for assessment evaluation and reporting.\n\u2022 Mentor junior and mid-level engineers through pairing, code reviews, and architectural brown-bag sessions.\n\u2022 Establish best practices for testing, observability (Datadog/New Relic), and continuous deployment on AWS.\n\u2022 Collaborate with product managers, UX designers, and curriculum specialists to define technical roadmaps.\n\nRequired Qualifications:\n\u2022 5+ years of software engineering experience developing high-scale web platforms in Python.\n\u2022 Deep expertise with Django (or similar Python web frameworks) and relational database tuning (PostgreSQL).\n\u2022 Proven track record designing, building, and maintaining distributed cloud systems on AWS.\n\u2022 Strong experience with in-memory caching (Redis) and asynchronous task execution (Celery).\n\u2022 Excellent communication skills with the ability to articulate complex technical trade-offs to diverse audiences.\n\nNice to Have:\n\u2022 Experience in EdTech or large-scale multi-tenant SaaS environments.\n\u2022 Hands-on familiarity with Kubernetes and Infrastructure as Code (Terraform).\n\u2022 Experience designing and executing zero-downtime database migrations.\n\nWhat We Offer:\n\u2022 Senior base salary ($145,000) plus annual performance bonus and equity.\n\u2022 Flexible remote work culture with summer Friday half-days.\n\u2022 Comprehensive employee insurance package with wellness savings account, dental, and vision.\n\u2022 401(k) with 4% company match.\n\u2022 Continuous learning stipend for books, certifications, and conferences.", "link": "https://jooble.org", "snippet": "Architect secure, distributed learning platform services, interactive student workflows, and data pipelines.", "source": "jooble", "logo": ""},
    {"id": 12, "title": "Software Engineer, Platform", "company": "Skyline Cloud", "location": "Remote", "salary": "132,000", "type": "Full-time", "tags": "AWS, Docker, Kubernetes, Linux, Python, Terraform, CI/CD, Go", "desc": "About Skyline Cloud:\nSkyline Cloud builds developer platforms and infrastructure automation tools that enable engineering organizations to deploy, manage, and scale cloud applications with speed and confidence.\n\nAbout the Role:\nWe are looking for a Platform Software Engineer to build and scale our internal developer platform and core cloud infrastructure. You will work on Kubernetes container runtimes, infrastructure-as-code automation, and developer tooling that empower dozens of product engineering teams to ship code safely.\n\nKey Responsibilities:\n\u2022 Design, build, and maintain internal developer platforms, CI/CD automation, and deployment pipelines.\n\u2022 Manage multi-region Kubernetes (EKS) clusters, service meshes, and ingress architectures on AWS.\n\u2022 Write reusable infrastructure modules and automated provisioning scripts using Terraform and Python.\n\u2022 Enhance platform reliability with comprehensive observability, distributed metrics, and alerting (Prometheus, Grafana).\n\u2022 Partner with product engineering teams to eliminate deployment friction and accelerate developer velocity.\n\u2022 Provide on-call operational support and conduct blameless incident reviews.\n\nRequired Qualifications:\n\u2022 3+ years of experience in platform engineering, DevOps, or backend infrastructure development.\n\u2022 Deep knowledge of Kubernetes, containerization (Docker), and cloud platform architecture on AWS.\n\u2022 Strong scripting and automation skills in Python or Go, with solid Linux systems fundamentals.\n\u2022 Hands-on experience authoring modular infrastructure-as-code using Terraform.\n\u2022 Experience designing and maintaining CI/CD systems (GitHub Actions, GitLab CI).\n\nNice to Have:\n\u2022 Experience with GitOps methodologies and tools like ArgoCD.\n\u2022 Familiarity with service mesh architectures (Istio, Linkerd) and network security policies.\n\u2022 Knowledge of compliance frameworks like SOC 2 and ISO 27001.\n\nWhat We Offer:\n\u2022 Base salary of $132,000 with equity grant.\n\u2022 Fully remote work with flexible hours.\n\u2022 Premium insurance benefits with dental, vision, and wellness coverage.\n\u2022 401(k) retirement plan with employer contribution.\n\u2022 $2,000 annual home workspace and technical education allowance.", "link": "https://jooble.org", "snippet": "Scale automated cloud infrastructure, container platforms, and deployment pipelines for enterprise services.", "source": "jooble", "logo": ""},
    {"id": 13, "title": "Backend Software Engineer", "company": "Crestview Labs", "location": "Remote", "salary": "126,000", "type": "Full-time", "tags": "Python, REST, SQL, FastAPI, PostgreSQL, Redis, Docker, Git", "desc": "About Crestview Labs:\nCrestview Labs develops quantitative analytics tools, algorithmic data feeds, and market intelligence platforms for institutional researchers and asset management firms.\n\nAbout the Role:\nWe are seeking a Backend Software Engineer to design, implement, and maintain high-throughput REST and WebSocket APIs. In this role, you will build data ingestion pipelines and microservices capable of parsing and streaming market indicators with millisecond-level responsiveness.\n\nKey Responsibilities:\n\u2022 Design, build, and optimize high-throughput REST and WebSocket APIs using Python and FastAPI.\n\u2022 Architect relational schemas, timeseries ingest pipelines, and caching layers with PostgreSQL and Redis.\n\u2022 Ensure low-latency API response times and 99.99% uptime for mission-critical analytical feeds.\n\u2022 Write comprehensive automated unit, integration, and load test suites.\n\u2022 Collaborate with data scientists and quant researchers to transform prototype models into production services.\n\u2022 Maintain clear API specifications using OpenAPI/Swagger and author technical documentation.\n\nRequired Qualifications:\n\u2022 3+ years of backend software engineering experience with Python.\n\u2022 Strong experience building asynchronous, high-concurrency web services with FastAPI, Starlette, or asyncio.\n\u2022 Advanced SQL skills with deep knowledge of relational schema design and query optimization in PostgreSQL.\n\u2022 Experience using Redis for caching, session stores, or message broker patterns.\n\u2022 Hands-on experience with Docker, Git version control, and Linux environments.\n\nNice to Have:\n\u2022 Familiarity with timeseries databases (TimescaleDB, InfluxDB) or columnar formats (Parquet, DuckDB).\n\u2022 Experience with quantitative datasets, algorithmic modeling concepts, or market data feeds.\n\u2022 Exposure to message streaming platforms such as Apache Kafka or RabbitMQ.\n\nWhat We Offer:\n\u2022 Competitive base salary ($126,000) and bonus eligibility.\n\u2022 100% remote work freedom with flexible scheduling.\n\u2022 Comprehensive employee insurance package including dental, vision, and disability plans.\n\u2022 401(k) retirement match.\n\u2022 Generous paid time off, technology stipend, and conference sponsorships.", "link": "https://jooble.org", "snippet": "Design performant backend APIs, real-time data pipelines, and low-latency integration services.", "source": "jooble", "logo": ""},
];

def:pub list_jobs -> list[dict[str, str | int]] {
    return JOBS;
}

def _extract_salary_values(salary_val: any) -> list[float] {
    if salary_val is None {
        return [];
    }
    if isinstance(salary_val, (int, float)) {
        return [float(salary_val)];
    }
    text = str(salary_val).strip();
    if not text {
        return [];
    }
    cleaned = text.replace(",", "");
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*([kK])?", cleaned);
    values: list[float] = [];
    for (num_str, k_suffix) in matches {
        try {
            val = float(num_str);
            if k_suffix.lower() == "k" {
                val = val * 1000.0;
            }
            values.append(val);
        } except ValueError {
            continue;
        }
    }
    return values;
}

def _matches_contract_type(job_type: any, target_type: str) -> bool {
    if not job_type or not target_type {
        return False;
    }
    jt = str(job_type).strip().lower();
    target_str = str(target_type).strip().lower();
    targets = [t.strip() for t in target_str.split(",") if t.strip()] if "," in target_str else [target_str];
    jt_norm = jt.replace("-", " ");
    for tt in targets {
        if tt == jt or tt in jt {
            return True;
        }
        tt_norm = tt.replace("-", " ");
        if tt_norm == jt_norm or tt_norm in jt_norm {
            return True;
        }
    }
    return False;
}

def _matches_company(job_company: any, target_company: str) -> bool {
    if not job_company or not target_company {
        return False;
    }
    jc = str(job_company).strip().lower();
    tc = str(target_company).strip().lower();
    return tc in jc;
}

glob SECTOR_KEYWORDS: dict[str, list[str]] = {
    "Technology & Software": ["tech", "software", "developer", "engineer", "data", "cloud", "ai", "machine learning", "it", "web", "frontend", "backend", "full stack", "devops", "systems", "qa", "qa automation", "python", "typescript", "react", "java", "sql", "pytorch", "kubernetes", "aws", "terraform"],
    "Finance & Banking": ["finance", "financial", "bank", "banking", "fintech", "accounting", "accountant", "invest", "investment", "trading", "wealth", "credit", "audit", "tax", "risk"],
    "Healthcare & Biotech": ["health", "healthcare", "clinical", "care", "biotech", "medical", "hospital", "pharma", "pharmaceutical", "nurse", "doctor", "biology", "patient", "medicine"],
    "Education & Research": ["education", "research", "university", "academic", "learning", "school", "teach", "teacher", "professor", "intern", "internship", "study", "student"],
    "Aerospace & Defense": ["aerospace", "defense", "aviation", "military", "satellite", "space", "aircraft", "naval", "security clearance"],
    "E-Commerce & Retail": ["commerce", "ecommerce", "retail", "store", "merchandise", "shop", "sales", "buyer", "inventory", "customer service"],
    "Consulting & Professional Services": ["consult", "consulting", "consultant", "advisory", "professional services", "strategy", "management consulting"],
    "Media & Entertainment": ["media", "entertainment", "game", "gaming", "music", "film", "video", "broadcast", "design", "designer", "ux", "creative", "art", "figma", "content"],
    "Government & Non-Profit": ["government", "usajobs", "non-profit", "nonprofit", "public sector", "federal", "civic", "policy", "agency", "civil service"],
    "Other": []
};

def _matches_sector(job: dict[str, any], target_sector: str) -> bool {
    if not target_sector or not str(target_sector).strip() {
        return True;
    }
    raw_sec = str(target_sector).strip();
    if raw_sec.lower() in ["all", "any", "all sectors"] {
        return True;
    }
    sectors = [s.strip() for s in raw_sec.split(",") if s.strip()];
    if not sectors {
        return True;
    }
    j_title = str(job.get("title", "")).lower();
    j_comp = str(job.get("company", "")).lower();
    j_tags = str(job.get("tags", "")).lower();
    j_desc = str(job.get("desc", "") or job.get("snippet", "")).lower();
    j_haystack = f"{j_title} {j_comp} {j_tags} {j_desc}";

    for sec in sectors {
        if sec == "Other" or sec.lower() == "other" {
            return True;
        }
        sec_low = sec.lower();
        sec_words = [w for w in re.split(r"[^a-zA-Z]+", sec_low) if len(w) > 3 and w not in ["and", "other"]];
        for w in sec_words {
            if w in j_haystack {
                return True;
            }
        }
        kw_list = SECTOR_KEYWORDS.get(sec, []);
        for kw in kw_list {
            if kw in j_haystack {
                return True;
            }
        }
    }
    return False;
}

# --- URL Builders ---

def build_jooble_url(api_key: str, domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        if "{key}" in endpoint {
            return endpoint.replace("{key}", api_key);
        }
        clean_ep = endpoint.rstrip("/");
        if clean_ep.endswith("/api") {
            return f"{clean_ep}/{api_key}";
        }
        return endpoint;
    }
    raw_domain = domain or os.environ.get("JOOBLE_API_DOMAIN") or "jooble.org";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/{api_key}";
}

def build_usajobs_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("USAJOBS_API_DOMAIN") or "data.usajobs.gov";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/search";
}

def build_himalayas_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("HIMALAYAS_API_DOMAIN") or "himalayas.app";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/jobs/api/search";
}

def build_themuse_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("THEMUSE_API_DOMAIN") or "www.themuse.com";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/public/jobs";
}

# --- Normalizers ---

def normalize_jooble_job(raw: dict[str, any]) -> dict[str, any] {
    logo = str(raw.get("company_logo") or raw.get("companyLogo") or raw.get("logo") or "");
    full_desc = str(raw.get("description") or raw.get("desc") or raw.get("snippet", "") or "");
    return {
        "id": str(raw.get("id", "")),
        "title": raw.get("title", ""),
        "company": raw.get("company", ""),
        "location": raw.get("location", ""),
        "salary": str(raw.get("salary", "")) if raw.get("salary") is not None else "",
        "type": raw.get("type", "") or "",
        "link": raw.get("link", "") or "",
        "snippet": raw.get("snippet", "") or "",
        "desc": full_desc,
        "source": "jooble",
        "tags": str(raw.get("tags", "")) if raw.get("tags") is not None else "",
        "logo": logo
    };
}

def normalize_usajobs_job(item: dict[str, any]) -> dict[str, any] {
    descriptor = item.get("MatchedObjectDescriptor", {}) if isinstance(item, dict) else {};
    pos_rem = descriptor.get("PositionRemuneration", []);
    salary_str = "";
    if isinstance(pos_rem, list) and len(pos_rem) > 0 and isinstance(pos_rem[0], dict) {
        min_r = pos_rem[0].get("MinimumRange");
        max_r = pos_rem[0].get("MaximumRange");
        if min_r is not None and max_r is not None and str(min_r) != str(max_r) {
            try {
                salary_str = f"${int(float(min_r)):,} - ${int(float(max_r)):,}";
            } except Exception {
                salary_str = f"${min_r} - ${max_r}";
            }
        } elif min_r is not None {
            try {
                salary_str = f"${int(float(min_r)):,}";
            } except Exception {
                salary_str = f"${min_r}";
            }
        }
    }
    pos_sched = descriptor.get("PositionSchedule", []);
    job_type = "";
    if isinstance(pos_sched, list) and len(pos_sched) > 0 and isinstance(pos_sched[0], dict) {
        job_type = pos_sched[0].get("Name", "") or "";
    }
    if not job_type {
        pos_off = descriptor.get("PositionOfferingType", []);
        if isinstance(pos_off, list) and len(pos_off) > 0 and isinstance(pos_off[0], dict) {
            job_type = pos_off[0].get("Name", "") or "";
        }
    }
    loc_display = descriptor.get("PositionLocationDisplay", "");
    if not loc_display {
        pos_locs = descriptor.get("PositionLocation", []);
        if isinstance(pos_locs, list) {
            loc_display = ", ".join([l.get("LocationName", "") for l in pos_locs if isinstance(l, dict) and l.get("LocationName")]);
        }
    }
    user_area = descriptor.get("UserArea", {}) if isinstance(descriptor.get("UserArea"), dict) else {};
    details = user_area.get("Details", {}) if isinstance(user_area.get("Details"), dict) else {};

    desc_sections: list[str] = [];
    job_summary = str(details.get("JobSummary") or "").strip();
    if job_summary {
        desc_sections.append(f"<p>{job_summary}</p>");
    }
    major_duties = details.get("MajorDuties", []);
    if isinstance(major_duties, list) and len(major_duties) > 0 {
        duty_items = "".join([f"<li>{str(d).strip()}</li>" for d in major_duties if str(d).strip()]);
        if duty_items {
            desc_sections.append(f"<div><p><strong>Major Duties:</strong></p><ul>{duty_items}</ul></div>");
        }
    } elif isinstance(major_duties, str) and major_duties.strip() {
        desc_sections.append(f"<div><p><strong>Major Duties:</strong></p><p>{major_duties.strip()}</p></div>");
    }
    qual_summary = str(descriptor.get("QualificationSummary") or "").strip();
    if qual_summary and qual_summary != job_summary {
        desc_sections.append(f"<div><p><strong>Qualifications:</strong></p><p>{qual_summary}</p></div>");
    }
    reqs = str(details.get("Requirements") or "").strip();
    if reqs {
        desc_sections.append(f"<div><p><strong>Requirements:</strong></p><p>{reqs}</p></div>");
    }
    evals = str(details.get("Evaluations") or "").strip();
    if evals {
        desc_sections.append(f"<div><p><strong>Evaluations:</strong></p><p>{evals}</p></div>");
    }
    edu = str(details.get("Education") or "").strip();
    if edu {
        desc_sections.append(f"<div><p><strong>Education:</strong></p><p>{edu}</p></div>");
    }
    full_desc = "\n".join(desc_sections).strip();
    if not full_desc {
        full_desc = job_summary or qual_summary or "";
    }
    snippet_desc = job_summary or qual_summary or "";

    job_cats = descriptor.get("JobCategory", []);
    tags_str = "";
    if isinstance(job_cats, list) {
        tags_str = ", ".join([c.get("Name", "") for c in job_cats if isinstance(c, dict) and c.get("Name")]);
    }
    app_uri = descriptor.get("PositionURI", "");
    apply_uris = descriptor.get("ApplyURI");
    if not app_uri and isinstance(apply_uris, list) and len(apply_uris) > 0 {
        app_uri = apply_uris[0];
    }
    logo = str(descriptor.get("Logo") or descriptor.get("OrganizationLogo") or details.get("CompanyLogo") or descriptor.get("logo") or item.get("logo") or "");
    return {
        "id": str(item.get("MatchedObjectId") or descriptor.get("PositionID", "")),
        "title": descriptor.get("PositionTitle", ""),
        "company": descriptor.get("OrganizationName") or descriptor.get("DepartmentName", ""),
        "location": loc_display,
        "salary": salary_str,
        "type": job_type,
        "link": app_uri,
        "snippet": snippet_desc,
        "desc": full_desc,
        "source": "usajobs",
        "tags": tags_str,
        "logo": logo
    };
}

def normalize_himalayas_job(job: dict[str, any]) -> dict[str, any] {
    loc_restr = job.get("locationRestrictions", []);
    loc_names = [];
    if isinstance(loc_restr, list) {
        for loc in loc_restr {
            if isinstance(loc, dict) and loc.get("name") {
                loc_names.append(loc["name"]);
            } elif isinstance(loc, str) {
                loc_names.append(loc);
            }
        }
    }
    location = ", ".join(loc_names) if loc_names else "Remote";
    salary_str = "";
    min_s = job.get("minSalary");
    max_s = job.get("maxSalary");
    if min_s is not None and max_s is not None and min_s != max_s {
        try {
            salary_str = f"${int(min_s):,} - ${int(max_s):,}";
        } except Exception {
            salary_str = f"${min_s} - ${max_s}";
        }
    } elif min_s is not None {
        try {
            salary_str = f"${int(min_s):,}";
        } except Exception {
            salary_str = f"${min_s}";
        }
    }
    cats = job.get("categories", []);
    tags_str = ", ".join(cats) if isinstance(cats, list) else str(cats or "");
    desc = job.get("description") or job.get("excerpt") or "";
    logo = str(job.get("companyLogo") or job.get("company_logo") or job.get("logo") or "");
    return {
        "id": str(job.get("guid", "")),
        "title": job.get("title", ""),
        "company": job.get("companyName", ""),
        "location": location,
        "salary": salary_str,
        "type": job.get("employmentType", "") or "",
        "link": job.get("applicationLink", "") or "",
        "snippet": job.get("excerpt", "") or "",
        "desc": desc,
        "source": "himalayas",
        "tags": tags_str,
        "logo": logo
    };
}

def normalize_themuse_job(job: dict[str, any]) -> dict[str, any] {
    comp_obj = job.get("company");
    company_name = "";
    if isinstance(comp_obj, dict) {
        company_name = comp_obj.get("name", "");
    } elif comp_obj {
        company_name = str(comp_obj);
    }
    locs = job.get("locations", []);
    loc_names = [];
    if isinstance(locs, list) {
        for l in locs {
            if isinstance(l, dict) and l.get("name") {
                loc_names.append(l["name"]);
            } elif isinstance(l, str) {
                loc_names.append(l);
            }
        }
    }
    location = ", ".join(loc_names);
    refs = job.get("refs", {}) if isinstance(job.get("refs"), dict) else {};
    link = refs.get("landing_page", "") if isinstance(refs, dict) else "";
    cats = job.get("categories", []);
    cat_names = [];
    if isinstance(cats, list) {
        for c in cats {
            if isinstance(c, dict) and c.get("name") {
                cat_names.append(c["name"]);
            } elif isinstance(c, str) {
                cat_names.append(c);
            }
        }
    }
    tags_str = ", ".join(cat_names);
    contents = job.get("contents", "") or "";
    snippet = re.sub(r"<[^>]+>", " ", contents).strip() if contents else "";
    if len(snippet) > 250 {
        snippet = snippet[:247] + "...";
    }
    logo = "";
    if isinstance(comp_obj, dict) {
        logo = str(comp_obj.get("logo") or comp_obj.get("small_logo") or comp_obj.get("image") or "");
    }
    if not logo {
        logo = str(job.get("company_logo") or job.get("companyLogo") or job.get("logo") or "");
    }
    return {
        "id": str(job.get("id", "")),
        "title": job.get("name", ""),
        "company": company_name,
        "location": location,
        "salary": "",
        "type": job.get("type", "") or "",
        "link": link,
        "snippet": snippet,
        "desc": contents,
        "source": "themuse",
        "tags": tags_str,
        "logo": logo
    };
}

# --- Fetchers ---

def fetch_jooble(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("JOOBLE_API_KEY", "");
    if not key {
        raise ValueError("Jooble API key must be provided via JOOBLE_API_KEY env var, .env file, or --api-key argument.");
    }
    url = build_jooble_url(key, domain=domain, endpoint=endpoint);
    req_payload = {"keywords": search, "ResultOnPage": n};
    if location {
        req_payload["location"] = location;
    }
    if salary is not None {
        req_payload["salary"] = int(salary);
    }
    body = json.dumps(req_payload).encode("utf-8");
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"}
    );
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Jooble API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Jooble API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("jobs", []) if isinstance(resp_payload, dict) else [];
    return [normalize_jooble_job(j) for j in raw_jobs];
}

def fetch_usajobs(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("USAJOBS_API_KEY", "");
    if not key {
        raise ValueError("USAJobs API key must be provided via USAJOBS_API_KEY env var, .env file, or --api-key argument.");
    }
    base_url = build_usajobs_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"Keyword": search, "ResultsPerPage": n};
    if location {
        query_params["LocationName"] = location;
    }
    if salary is not None {
        query_params["RemunerationMinimumAmount"] = int(salary);
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    host = domain or "data.usajobs.gov";
    if host.startswith("https://") {
        host = host[8:];
    } elif host.startswith("http://") {
        host = host[7:];
    }
    host = host.split("/")[0];
    email = os.environ.get("USAJOBS_EMAIL", "robieli@umich.edu");
    req = urllib.request.Request(
        url,
        headers={
            "Host": host,
            "User-Agent": email,
            "Authorization-Key": key
        }
    );
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"USAJobs API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"USAJobs API network error: {e.reason}");
    }
    search_result = resp_payload.get("SearchResult", {}) if isinstance(resp_payload, dict) else {};
    items = search_result.get("SearchResultItems", []) if isinstance(search_result, dict) else [];
    return [normalize_usajobs_job(item) for item in items];
}

def fetch_himalayas(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("HIMALAYAS_API_KEY", "");
    base_url = build_himalayas_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"q": search, "limit": min(max(n, 1), 20)};
    if location {
        query_params["country"] = location;
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    headers: dict[str, str] = {"User-Agent": "Mozilla/5.0"};
    if key {
        headers["Authorization"] = f"Bearer {key}";
    }
    req = urllib.request.Request(url, headers=headers);
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Himalayas API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Himalayas API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("jobs", []) if isinstance(resp_payload, dict) else [];
    normalized = [normalize_himalayas_job(j) for j in raw_jobs];
    if salary is not None {
        sal_jobs = [];
        for job in normalized {
            sal_vals = _extract_salary_values(job.get("salary"));
            if sal_vals and max(sal_vals) >= int(salary) {
                sal_jobs.append(job);
            }
        }
        return sal_jobs[:n];
    }
    return normalized[:n];
}

def fetch_themuse(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    company: str | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("THEMUSE_API_KEY", os.environ.get("MUSE_API_KEY", ""));
    base_url = build_themuse_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"page": 1};
    if key {
        query_params["api_key"] = key;
    }
    if company {
        query_params["company"] = company;
    }
    if location {
        query_params["location"] = location;
    }
    if search {
        query_params["category"] = search;
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"});
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"The Muse API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"The Muse API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("results", []) if isinstance(resp_payload, dict) else [];
    normalized = [normalize_themuse_job(j) for j in raw_jobs];
    if salary is not None {
        # The Muse does not provide structured salary
        _ = salary;
    }
    return normalized[:n];
}

# --- Unified Fetch ---


def parse_multi_locations(loc_str: str) -> list[str] {
    if not loc_str {
        return [];
    }
    raw_parts = [p.strip() for p in loc_str.split(",") if p.strip()];
    locs: list[str] = [];
    idx = 0;
    while idx < len(raw_parts) {
        part = raw_parts[idx];
        if idx + 1 < len(raw_parts) and len(raw_parts[idx + 1]) == 2 and raw_parts[idx + 1].isalpha() {
            locs.append(f"{part}, {raw_parts[idx + 1]}");
            idx = idx + 2;
        } else {
            locs.append(part);
            idx = idx + 1;
        }
    }
    return locs;
}

def fetch(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    contract_type: str | None = None,
    company: str | None = None,
    sector: str | None = None,
    api_key: str | None = None,
    source: str = "jooble",
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    if n <= 0 {
        return [];
    }
    load_env_file();
    src = (source or "jooble").strip().lower();
    raw_jobs: list[dict[str, any]] = [];

    if src == "all" or "," in src {
        sources_to_query = ["jooble", "usajobs", "himalayas", "themuse"] if src == "all" else [s.strip() for s in src.split(",") if s.strip()];
        for s in sources_to_query {
            try {
                if s == "jooble" {
                    raw_jobs.extend(fetch_jooble(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "usajobs" {
                    raw_jobs.extend(fetch_usajobs(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "himalayas" {
                    raw_jobs.extend(fetch_himalayas(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "themuse" {
                    raw_jobs.extend(fetch_themuse(n, search, location=location, salary=salary, company=company, api_key=api_key, domain=domain, endpoint=endpoint));
                }
            } except Exception as e {
                if len(sources_to_query) == 1 {
                    raise e;
                }
            }
        }
    } elif src == "usajobs" {
        raw_jobs = fetch_usajobs(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    } elif src == "himalayas" {
        raw_jobs = fetch_himalayas(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    } elif src == "themuse" {
        raw_jobs = fetch_themuse(n, search, location=location, salary=salary, company=company, api_key=api_key, domain=domain, endpoint=endpoint);
    } else {
        raw_jobs = fetch_jooble(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    }

    filtered_jobs = [];
    for job in raw_jobs {
        if company is not None and str(company).strip() != "" {
            if not _matches_company(job.get("company"), str(company).strip()) {
                continue;
            }
        }
        if contract_type is not None and str(contract_type).strip() != "" {
            if not _matches_contract_type(job.get("type"), str(contract_type).strip()) {
                continue;
            }
        }
        if sector is not None and str(sector).strip() != "" {
            if not _matches_sector(job, str(sector).strip()) {
                continue;
            }
        }
        if salary is not None {
            sal_vals = _extract_salary_values(job.get("salary"));
            if not sal_vals or max(sal_vals) < int(salary) {
                continue;
            }
        }
        if location is not None and str(location).strip() != "" {
            loc_target_str = str(location).strip().lower();
            targets = [t.lower() for t in parse_multi_locations(loc_target_str)] if parse_multi_locations(loc_target_str) else [loc_target_str];
            job_loc = str(job.get("location", "")).lower();
            matched_any_loc = False;
            for loc_target in targets {
                if "remote" in loc_target {
                    if "remote" in job_loc {
                        matched_any_loc = True;
                        break;
                    }
                } else {
                    if job_loc and (loc_target in job_loc or job_loc in loc_target) {
                        matched_any_loc = True;
                        break;
                    }
                }
            }
            if not matched_any_loc {
                continue;
            }
        }
        if search and src in ["themuse", "all"] {
            s_low = search.strip().lower();
            content = f"{job.get('title', '')} {job.get('company', '')} {job.get('desc', '')} {job.get('tags', '')}".lower();
            words = [w for w in s_low.split() if len(w) > 2];
            if words and not any([w in content for w in words]) {
                continue;
            }
        }
        filtered_jobs.append(job);
    }
    return filtered_jobs[:n];
}

def:pub get_user_tailored_jobs(
    email: str | None = None,
    token: str | None = None,
    conn: any = None
) -> dict[str, any] {
    actual_conn = conn if (conn is not None and not isinstance(conn, str)) else None;
    clean_email = str(email).strip().lower() if (email and str(email).strip()) else None;
    resolved_info = resolve_token_identity(token) if token else {};

    if not clean_email and resolved_info.get("email") {
        clean_email = str(resolved_info["email"]).strip().lower();
    }

    oauth_id = resolved_info.get("user_id");

    user: any = None;
    if clean_email {
        try {
            user = get_user_by_email(clean_email, conn=actual_conn);
        } except Exception {}
    }
    if user is None and oauth_id {
        try {
            user = get_user_by_oauth_id(str(oauth_id), auth_provider="google", conn=actual_conn);
        } except Exception {}
    }
    
    if user and user.get("cached_job_query") {
        query_dict: dict[str, any] = {};
        try {
            query_dict = json.loads(str(user["cached_job_query"]));
        } except Exception {
            query_dict = {};
        }
        if query_dict and "search" in query_dict {
            search_term = str(query_dict.get("search", "")).strip() or "Software Engineer";
            loc_term = query_dict.get("location");
            clean_loc = str(loc_term).strip() if loc_term else None;
            if clean_loc == "Remote" or (clean_loc and "remote" in clean_loc.lower()) {
                clean_loc = "Remote";
            }
            sal_term = query_dict.get("salary");
            clean_sal: int | None = None;
            if sal_term is not None {
                try {
                    clean_sal = int(sal_term);
                } except ValueError {
                    clean_sal = None;
                }
            }
            ct_term = query_dict.get("contract_type");
            comp_term = query_dict.get("company");
            src_term = str(query_dict.get("source", "all"));

            fetched_jobs: list[dict[str, any]] = [];
            try {
                fetched_jobs = fetch(
                    n=20,
                    search=search_term,
                    location=clean_loc,
                    salary=clean_sal,
                    contract_type=str(ct_term) if ct_term is not None else None,
                    company=str(comp_term) if comp_term is not None else None,
                    source=src_term
                );
            } except Exception {}

            if fetched_jobs {
                return {
                    "ok": True,
                    "jobs": fetched_jobs,
                    "query": query_dict,
                    "tailored": True,
                    "onboarding_completed": bool(user.get("onboarding_completed"))
                };
            }

            # Fallback to local jobs matching preferences
            fallback_jobs: list[dict[str, any]] = [];
            for j in JOBS {
                s_low = search_term.lower();
                j_text = f"{j.get('title', '')} {j.get('desc', '')} {j.get('tags', '')}".lower();
                matches_s = any([w in j_text for w in s_low.split() if len(w) > 2]) if s_low else True;
                matches_l = True;
                if clean_loc and clean_loc.lower() != "remote" {
                    matches_l = clean_loc.lower() in str(j.get("location", "")).lower();
                }
                if matches_s or matches_l {
                    fallback_jobs.append(dict(j));
                }
            }
            return {
                "ok": True,
                "jobs": fallback_jobs if fallback_jobs else [dict(j) for j in JOBS],
                "query": query_dict,
                "tailored": True,
                "onboarding_completed": bool(user.get("onboarding_completed"))
            };
        }
    }
    
    return {
        "ok": True,
        "jobs": [dict(j) for j in JOBS],
        "query": None,
        "tailored": False,
        "onboarding_completed": bool(user.get("onboarding_completed")) if user else False
    };
}

def:pub search_jobs(
    search: str = "",
    location: str | None = None,
    salary: int | None = None,
    contract_type: str | None = None,
    company: str | None = None,
    sector: str | None = None,
    source: str = "all",
    n: int = 20
) -> dict[str, any] {
    load_env_file();
    search_term = str(search or "").strip();
    clean_loc = str(location).strip() if (location and str(location).strip()) else None;
    if clean_loc and clean_loc.lower() == "remote" {
        clean_loc = "Remote";
    }
    clean_sal: int | None = None;
    if salary is not None {
        try {
            clean_sal = int(salary);
        } except (ValueError, TypeError) {
            clean_sal = None;
        }
    }
    ct_term = str(contract_type).strip() if (contract_type and str(contract_type).strip()) else None;
    comp_term = str(company).strip() if (company and str(company).strip()) else None;
    sec_term = str(sector).strip() if (sector and str(sector).strip()) else None;
    src_term = str(source or "all").strip().lower();

    fetched_jobs: list[dict[str, any]] = [];
    if src_term != "local" and (search_term or clean_loc or comp_term or clean_sal is not None or ct_term or sec_term) {
        try {
            fetched_jobs = fetch(
                n=n,
                search=search_term or "Software",
                location=clean_loc,
                salary=clean_sal,
                contract_type=ct_term,
                company=comp_term,
                sector=sec_term,
                source=src_term
            );
        } except Exception {}
    }

    if fetched_jobs {
        return {
            "ok": True,
            "jobs": fetched_jobs,
            "count": len(fetched_jobs),
            "query": {
                "search": search_term,
                "location": clean_loc or "",
                "salary": clean_sal,
                "contract_type": ct_term or "",
                "company": comp_term or "",
                "sector": sec_term or "",
                "source": src_term
            },
            "is_custom": True
        };
    }

    fallback_jobs: list[dict[str, any]] = [];
    for j in JOBS {
        if search_term {
            s_low = search_term.lower();
            j_text = f"{j.get('title', '')} {j.get('company', '')} {j.get('desc', '')} {j.get('tags', '')}".lower();
            words = [w for w in s_low.split() if len(w) > 2];
            if words and not any([w in j_text for w in words]) {
                continue;
            }
        }
        if clean_loc {
            clean_loc_low = clean_loc.lower();
            targets = [t.lower() for t in parse_multi_locations(clean_loc_low)] if parse_multi_locations(clean_loc_low) else [clean_loc_low];
            j_loc_str = str(j.get("location", "")).lower();
            matched_loc = False;
            for t in targets {
                if "remote" in t {
                    if "remote" in j_loc_str {
                        matched_loc = True;
                        break;
                    }
                } else {
                    if t in j_loc_str or j_loc_str in t {
                        matched_loc = True;
                        break;
                    }
                }
            }
            if not matched_loc {
                continue;
            }
        }
        if comp_term {
            if not _matches_company(j.get("company"), comp_term) {
                continue;
            }
        }
        if ct_term {
            if not _matches_contract_type(j.get("type"), ct_term) {
                continue;
            }
        }
        if sec_term {
            if not _matches_sector(j, sec_term) {
                continue;
            }
        }
        if clean_sal is not None {
            sal_vals = _extract_salary_values(j.get("salary"));
            if not sal_vals or max(sal_vals) < clean_sal {
                continue;
            }
        }
        fallback_jobs.append(dict(j));
    }

    if not fallback_jobs and search_term {
        s_low = search_term.lower();
        words = [w for w in s_low.split() if len(w) > 2];
        for j in JOBS {
            j_text = f"{j.get('title', '')} {j.get('company', '')} {j.get('desc', '')} {j.get('tags', '')}".lower();
            if words and any([w in j_text for w in words]) {
                fallback_jobs.append(dict(j));
            }
        }
    }

    return {
        "ok": True,
        "jobs": fallback_jobs[:n],
        "count": len(fallback_jobs[:n]),
        "query": {
            "search": search_term,
            "location": clean_loc or "",
            "salary": clean_sal,
            "contract_type": ct_term or "",
            "company": comp_term or "",
            "sector": sec_term or "",
            "source": src_term
        },
        "is_custom": True
    };
}
