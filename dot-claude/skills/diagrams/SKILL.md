---
description: Generate architecture and flow diagrams using mermaid-cli (mmdc)
triggers:
  - diagram
  - mermaid
  - architecture diagram
  - flow chart
  - sequence diagram
  - generate diagram
  - visualize
  - erd
  - class diagram
paths: ["**/*.md", "**/docs/**", "**/*.mermaid", "**/*.diagram", "**/*.drawio"]
---

# Diagram Generation

Use `mmdc` (mermaid-cli) to render diagrams as PNG/SVG.

## Usage
```bash
# Write mermaid to file, then render
cat > /tmp/diagram.mmd << 'EOF'
graph TD
    A[Client] --> B[API Gateway]
    B --> C[Auth Service]
    B --> D[App Service]
    D --> E[(Database)]
EOF

mmdc -i /tmp/diagram.mmd -o diagram.png          # PNG output
mmdc -i /tmp/diagram.mmd -o diagram.svg           # SVG output
mmdc -i /tmp/diagram.mmd -o diagram.png -w 1200   # custom width
mmdc -i /tmp/diagram.mmd -o diagram.pdf           # PDF output
```

## Diagram Types

### Architecture / System Design
```mermaid
graph TD
    LB[Load Balancer] --> S1[Server 1]
    LB --> S2[Server 2]
    S1 --> DB[(PostgreSQL)]
    S2 --> DB
    S1 --> Cache[(Redis)]
    S2 --> Cache
```

### Sequence Diagram
```mermaid
sequenceDiagram
    Client->>API: POST /login
    API->>Auth: validate(credentials)
    Auth-->>API: token
    API-->>Client: 200 OK {token}
```

### Entity Relationship
```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "ordered in"
```

### Git Flow
```mermaid
gitgraph
    commit
    branch feature
    commit
    commit
    checkout main
    merge feature
    commit
```

### State Diagram
```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Review: submit
    Review --> Approved: approve
    Review --> Draft: request changes
    Approved --> Deployed: deploy
    Deployed --> [*]
```

### Flowchart (CI/CD Pipeline)
```mermaid
graph LR
    A[Push] --> B[Lint]
    A --> C[Test]
    B --> D{All Pass?}
    C --> D
    D -->|Yes| E[Build]
    D -->|No| F[Notify]
    E --> G[Deploy]
```

## Workflow
1. Write mermaid syntax to a `.mmd` file.
2. Render with `mmdc -i input.mmd -o output.png`.
3. For docs, use SVG: `mmdc -i input.mmd -o output.svg`.
4. Store diagrams in `docs/diagrams/` or project root.
5. Reference in README: `![Architecture](docs/diagrams/arch.png)`.

## Tips
- Use `graph TD` (top-down) or `graph LR` (left-right) for direction.
- Keep diagrams focused — one concept per diagram.
- Use descriptive node IDs: `DB[(PostgreSQL)]` not `A[(DB)]`.
- For large systems, break into multiple diagrams.
