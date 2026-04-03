# jq

`jq` is a JSON processor for querying and transforming JSON.

## Common Commands

- `jq . file.json`: pretty-print JSON
- `jq '.name' file.json`: extract one field
- `jq '.items[] | .id' file.json`: iterate over array values
- `curl ... | jq`: inspect JSON API output
