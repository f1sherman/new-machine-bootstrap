Keep every command line at 80 characters or fewer. Use syntactically valid
line breaks and continuation syntax. Never rely on visual wrapping. Never use
heredocs in commands intended for user copy and paste. Use `printf`, repeated
options, helper scripts, or direct file-editing tools instead.

1. Put a `\` line continuation only between complete arguments. Never put it
   inside a path, URL, quoted string, `--opt=value`, or `key=value` pair.
   Keep option values attached to `=`.

   Bad (splits the path into two arguments):

   ```bash
   cat ~/.config/rendered/\
     service/config.yaml
   ```

   Correct:

   ```bash
   cat \
     ~/.config/rendered/service/config.yaml
   ```

2. If one argument exceeds about 60 characters, keep it whole in a short shell
   variable on its own line, then use a quoted expansion such as `"$f"`.
   If the assignment would exceed 80 characters, build it with `printf` or
   append whole path components to the variable. Never split the argument.

   Bad:

   ```bash
   cat ~/.config/remote-environments/rendered/\
     production/application/settings.yaml
   ```

   Correct:

   ```bash
   f="$HOME/.config/remote-environments/rendered"
   f="$f/production/application/settings.yaml"
   cat "$f"
   ```

3. Use literal line breaks inside quoted programs only where the program treats
   newlines as whitespace, such as between expressions in a single-quoted
   `jq` or `awk` program. Keep paths and data values free of inserted newlines.

   Bad (inserts a newline and spaces into the path):

   ```bash
   cat "$HOME/.config/rendered/
     service/config.yaml"
   ```

   Correct (newlines separate expressions in a program, not parts of a value):

   ```bash
   jq '
     .items[]
     | .metadata.name
   ' input.json
   ```

4. Before sending a multi-line command, rejoin it as the shell does: remove each
   unquoted `\` plus newline and retain the next line's indentation. Between
   unquoted arguments, that indentation acts as whitespace. Check that every
   intended argument remains whole. Do not assume the shell inserts a space;
   quoted newlines remain literal unless the shell escapes them.

   Bad (rejoins as `jsonpath=  '{.metadata.name}'`, two arguments):

   ```bash
   kubectl get pod example -o jsonpath=\
     '{.metadata.name}'
   ```

   Correct (the format and template remain one argument):

   ```bash
   kubectl get pod example \
     -o jsonpath='{.metadata.name}'
   ```
