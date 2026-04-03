# yq

`yq` queries and transforms YAML data.

## Common Commands

- `yq '.foo' file.yml`: read one value
- `yq '.foo = "bar"' file.yml`: update a value
- `yq -P file.yml`: pretty-print YAML
- `yq '.items[] | .name' file.yml`: iterate through values
