#!/usr/bin/env python3
"""Convert benchmark markdown report to styled HTML."""
import sys
import re
from datetime import datetime

def md_to_html(md_path, html_path):
    with open(md_path, 'r') as f:
        lines = f.readlines()

    h = []
    h.append('<!DOCTYPE html>')
    h.append('<html lang="zh-CN">')
    h.append('<head>')
    h.append('<meta charset="UTF-8">')
    h.append('<meta name="viewport" content="width=device-width,initial-scale=1.0">')
    h.append('<title>网络监控 App 对比评测报告</title>')
    h.append('<style>')
    h.append('body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;max-width:960px;margin:0 auto;padding:20px;background:#f5f5f7;color:#1d1d1f;line-height:1.6}')
    h.append('h1{border-bottom:3px solid #007aff;padding-bottom:10px;color:#1d1d1f;margin-top:0}')
    h.append('h2{color:#1d1d1f;margin-top:36px;border-left:4px solid #007aff;padding-left:12px}')
    h.append('h3{color:#3a3a3c;margin-top:24px}')
    h.append('table{border-collapse:collapse;width:100%;margin:16px 0;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08)}')
    h.append('th{background:#007aff;color:#fff;padding:12px 16px;text-align:center;font-weight:600;font-size:0.95em}')
    h.append('td{padding:10px 16px;border-bottom:1px solid #e5e5ea;text-align:center}')
    h.append('tr:last-child td{border-bottom:none}')
    h.append('tr:hover{background:#f0f0f5}')
    h.append('blockquote{background:#fff;border-left:4px solid #007aff;margin:16px 0;padding:12px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06)}')
    h.append('code{background:#e5e5ea;padding:2px 8px;border-radius:4px;font-size:0.9em}')
    h.append('hr{border:none;border-top:1px solid #d1d1d6;margin:32px 0}')
    h.append('.footer{margin-top:48px;padding-top:16px;border-top:1px solid #d1d1d6;color:#86868b;font-size:0.9em;text-align:center}')
    h.append('</style>')
    h.append('</head>')
    h.append('<body>')

    in_table = False
    header_row = False

    for raw_line in lines:
        s = raw_line.rstrip('\n\r')

        if s.startswith('| '):
            if re.match(r'^\|[-: ]+\|', s):
                continue
            cells_str = s[2:-1] if s.endswith(' |') else s[1:]
            cells = [c.strip() for c in re.split(r' \| ', cells_str)]

            if not in_table:
                h.append('<table>')
                in_table = True
                header_row = True

            h.append('<tr>')
            for cell in cells:
                if header_row:
                    h.append(f'<th>{cell}</th>')
                else:
                    h.append(f'<td>{cell}</td>')
            h.append('</tr>')
            if header_row:
                header_row = False
        else:
            if in_table:
                h.append('</table>')
                in_table = False
                header_row = False

            if s.startswith('### '):
                h.append(f'<h3>{s[4:]}</h3>')
            elif s.startswith('## '):
                h.append(f'<h2>{s[3:]}</h2>')
            elif s.startswith('# '):
                h.append(f'<h1>{s[2:]}</h1>')
            elif s.startswith('> '):
                h.append(f'<blockquote>{s[2:]}</blockquote>')
            elif s.startswith('---'):
                h.append('<hr>')
            elif s == '':
                pass  # skip bare empty lines
            else:
                if not s.startswith('*报告') and not s.startswith('*生成'):
                    h.append(f'<p>{s}</p>')

    if in_table:
        h.append('</table>')

    h.append('<div class="footer">')
    h.append(f'<p>报告生成时间: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>')
    h.append('</div>')
    h.append('</body>')
    h.append('</html>')

    with open(html_path, 'w') as f:
        f.write('\n'.join(h))

    return True

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: compare-benchmark-html.py <input.md> <output.html>")
        sys.exit(1)
    success = md_to_html(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)
