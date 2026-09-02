# Screenshot drop folder

Save captures here with these exact filenames. Then say the word and I'll
base64-embed them into deck.html and republish — relative paths don't survive
publishing, so they have to be inlined.

macOS capture: Cmd+Shift+4, then drag. Or Cmd+Shift+5 for a window.

| filename | what to capture |
|---|---|
| `01-query-24x.png` | BigQuery console: the query returning 8,484,310 / 353,500 / 353,500 |
| `02-terraform-plan.png` | Terminal: `terraform plan` with the resource-count summary line |
| `03-storage-partitions.png` | Cloud Storage browser: the `version=` folders |
| `04-bigquery-datasets.png` | BigQuery: the bronze / silver / gold tree expanded |
| `05-workflow-graph.png` | Workflows: an execution's graph, all steps green, SUCCEEDED |
| `06-transform-logs.png` | Cloud Run: transform job log showing `PASS=26 WARN=0 ERROR=0` |
| `07-compliance.png` | Terminal: `./scripts/verify_compliance.sh`, ending `18 passed, 0 failed` |
| `08-billing.png` | Billing: current spend against the budget |

Console links: ../GCP_LINKS.md
