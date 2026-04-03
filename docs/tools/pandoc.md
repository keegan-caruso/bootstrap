# pandoc

`pandoc` converts between Markdown and many other document formats.

## Common Commands

- `pandoc README.md -t html`: convert Markdown to HTML
- `pandoc notes.md -o notes.pdf`: render to PDF when a PDF engine is available
- `pandoc doc.md -o doc.docx`: convert Markdown to Word
- `pandoc --from gfm --to commonmark README.md`: normalize Markdown dialects
