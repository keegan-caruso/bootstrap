# xclip

`xclip` reads from and writes to the X clipboard on Linux.

## Common Commands

- `echo hello | xclip -selection clipboard`: copy text
- `xclip -selection clipboard -o`: print clipboard contents
- `cat file.txt | xclip -selection primary`: copy to the primary selection
