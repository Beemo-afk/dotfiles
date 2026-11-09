1. generate invalid json output

```bash
foo='x[]'
declare -i foo
jsonvar foo
```

2. namerefs can break our output

```bash
declare -n foo=...
jsonvar foo
```

3. code execution lol

```bash
0() { code ...; }
a=0
declare -n proxy_var=_jv_ref[_jv_value=a]
jsonvar
```
