# CONTRIBUTING

### AI

Using AI is allowed.  
However, low-quality code and PRs that do not follow the rules will be rejected.  
Take responsibility for the code you submit.

### CHANGE

Before proposing code, a spec change, or a new feature, consider whether it is really needed.  
This project follows the UNIX philosophy as far as it can.  
It also aims for a spec small enough to fit in your head.  
Always branch from `dev` and merge back into `dev`.

### COMMIT

Write commit messages in English, in the `prefix: message` format.  
Prefixes follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).  
Do not mark AI usage in a commit description with `Co-Authored-By` or a signature line.  
What matters is the quality of the code.

### PR

Before opening a PR, always make sure `zig build` and `zig fmt --check .` pass.  
Do not mark AI usage in a PR description with `Co-Authored-By` or a signature line.  
Keep the description as short and clear as possible, and follow the format below.
```md
# Summary

- message1
- message2
...
```
