---
name: md2pdf
description: Convert a Markdown file to PDF. Use when the user invokes /md2pdf, asks to "convert md to pdf", "update the pdf", "regenerate pdf", or "export md as pdf".
argument-hint: "[path/to/file.md] — defaults to sql_db/title_change_request.md if omitted"
allowed-tools: [Read, Write, PowerShell, Bash]
---

# md2pdf Skill

Convert a Markdown file to a styled PDF using Word COM. The source `.md` file is never modified.

## Steps

### 1. Resolve the target MD file

If the user provided a path as `$ARGUMENTS`, use that. Otherwise default to:
```
sql_db/title_change_request.md
```

Resolve the absolute path relative to the project root:
`c:\Users\zengsh\OneDrive - Westfund Ltd\Documents\Westfund_\Vscode_\`

### 2. Read the MD file

Use the Read tool to load the full content of the MD file.

### 3. Convert Markdown to HTML

Build a complete HTML document from the MD content. Apply this CSS style block:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>{{title}}</title>
<style>
  body {
    font-family: 'Segoe UI', Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #222;
    max-width: 750px;
    margin: 40px auto;
    padding: 0 20px;
  }
  h1 { font-size: 20pt; border-bottom: 2px solid #333; padding-bottom: 6px; margin-bottom: 16px; }
  h2 { font-size: 14pt; margin-top: 28px; margin-bottom: 8px; }
  h3 { font-size: 12pt; margin-top: 20px; margin-bottom: 6px; }
  table { border-collapse: collapse; width: 60%; margin: 16px 0; }
  th, td { border: 1px solid #bbb; padding: 8px 16px; text-align: center; }
  th { background: #f0f0f0; }
  hr { border: none; border-top: 1px solid #ccc; margin: 24px 0; }
  blockquote {
    border-left: 4px solid #888;
    margin: 16px 0;
    padding: 8px 16px;
    background: #f9f9f9;
    color: #444;
  }
  ul { padding-left: 24px; }
  li { margin-bottom: 4px; }
  del { color: #999; }
  strong { font-weight: 600; }
</style>
</head>
<body>
{{body}}
</body>
</html>
```

Apply these Markdown-to-HTML conversion rules manually (do NOT call an external parser):

| Markdown | HTML |
|----------|------|
| `# Heading` | `<h1>Heading</h1>` |
| `## Heading` | `<h2>Heading</h2>` |
| `### Heading` | `<h3>Heading</h3>` |
| `**text**` | `<strong>text</strong>` |
| `~~text~~` | `<del>text</del>` |
| `` `code` `` | `<code>code</code>` |
| `> blockquote` | `<blockquote>blockquote</blockquote>` |
| `---` | `<hr>` |
| `- item` | `<li>item</li>` (wrap groups in `<ul>`) |
| Blank line between paragraphs | `<p>...</p>` |
| Pipe tables (`\|...\|`) | `<table>` with `<th>` for header row, `<td>` for data rows; skip the separator row (`\|---\|`) |

### 4. Write the temporary HTML file

Write the HTML to a temp path in the same directory as the MD file:
```
<same_dir>\<basename>_temp.html
```

### 5. Convert HTML → PDF via Word COM

Run this PowerShell snippet:

```powershell
$htmlAbs = (Resolve-Path "<temp_html_path>").Path
$pdfAbs  = "<same_dir>\<basename>.pdf"

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Open($htmlAbs)
$doc.SaveAs([ref]$pdfAbs, [ref]17)   # 17 = wdFormatPDF
$doc.Close()
$word.Quit()
```

### 6. Clean up and report

- Delete the temporary HTML file
- Confirm success: report the output PDF path to the user
- Confirm that the source MD file was not modified

## Notes

- The PDF filename always matches the MD filename (same basename, `.pdf` extension)
- If a PDF already exists at that path, it is overwritten (this is the update behaviour)
- If Word COM is unavailable, report the error and stop — do not attempt fallback methods
