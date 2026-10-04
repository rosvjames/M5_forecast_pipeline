"""Genera docs/img/arquitectura.svg (diagrama de arquitectura). Uso: python3 docs/img/arquitectura.py"""
from pathlib import Path

W, H = 1200, 575


def box(x, y, w, h, lines, cls):
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" class="{cls}"/>']
    cy = y + h / 2 - (len(lines) - 1) * 9
    for i, t in enumerate(lines):
        fw = ' font-weight="600"' if i == 0 else ''
        out.append(f'<text x="{x + w / 2}" y="{cy + i * 18 + 4.5}" text-anchor="middle"{fw}>{t}</text>')
    return "\n".join(out)


def label(x, y, lines, anchor="middle"):
    return "\n".join(f'<text x="{x}" y="{y + i * 15}" text-anchor="{anchor}" class="lbl">{t}</text>'
                     for i, t in enumerate(lines))


def arrow(x1, y1, x2, y2, dash=False):
    d = ' stroke-dasharray="6 4"' if dash else ''
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="arr"{d} marker-end="url(#ah)"/>'


s = [f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="Helvetica, Arial, sans-serif" font-size="13" fill="#1f2933">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#52606d"/></marker></defs>
<style>
.grp{{fill:#fafafa;stroke:#9aa5b1;stroke-width:1.2}}
.sub{{fill:#ffffff;stroke:#9aa5b1;stroke-width:1;stroke-dasharray:4 3}}
.ext{{fill:#f0f1f3;stroke:#7b8794;stroke-width:1.2}}
.tool{{fill:#e3ecfb;stroke:#3f6bb0;stroke-width:1.2}}
.data{{fill:#e4f3e7;stroke:#3f8a52;stroke-width:1.2}}
.arr{{stroke:#52606d;stroke-width:1.5;fill:none}}
.lbl{{font-size:12px;fill:#3e4c59}}
.ttl{{font-size:13px;font-weight:600;fill:#52606d}}
</style>
<rect width="{W}" height="{H}" fill="#ffffff"/>''']

# Fuente externa
s.append(box(25, 15, 190, 56, ["Kaggle API", "M5 Forecasting (3 CSV)"], "ext"))

# Docker Compose: Kestra, dbt y Spark
s.append('<rect x="20" y="100" width="1160" height="175" rx="10" class="grp"/>')
s.append('<text x="1164" y="121" text-anchor="end" class="ttl">Docker Compose (local)</text>')
s.append('<rect x="40" y="132" width="425" height="130" rx="8" class="sub"/>')
s.append('<text x="455" y="150" text-anchor="end" class="lbl">Kestra + Postgres · orquestación e ingesta</text>')
s.append(box(55, 160, 190, 90, ["Flow ingest_raw", "bajo demanda", "descarga y sube los CSV"], "tool"))
s.append(box(260, 160, 190, 90, ["Flow load_sales_week", "cron sábados 06:00 UTC", "backfill · retries · idempotente"], "tool"))
s.append(box(600, 160, 220, 90, ["dbt Core", "modelos Silver y Gold", "118 tests"], "tool"))
s.append(box(915, 160, 230, 90, ["Spark standalone", "master + worker", "build_obt.py"], "tool"))

# Snowflake: stage y capas
s.append('<rect x="20" y="365" width="1160" height="190" rx="10" class="grp"/>')
s.append('<text x="36" y="544" class="ttl">Snowflake · base M5</text>')
xs = [40, 270, 500, 730, 960]
stores = [["@RAW_STAGE", "CSV originales +", "entregas semanales"],
          ["BRONZE", "CALENDAR · SELL_PRICES", "SALES_RAW · LOAD_LOG"],
          ["SILVER", "stg_* · int_sales_daily", "flags de calidad"],
          ["GOLD · star schema", "fact_sales", "+ 4 dimensiones"],
          ["OBT", "OBT_SALES", "item × tienda × día"]]
for x, lines in zip(xs, stores):
    s.append(box(x, 410, 190, 100, lines, "data"))
for i, t in [(0, None), (1, "dbt"), (2, "dbt")]:
    s.append(arrow(xs[i] + 190, 460, xs[i + 1] - 2, 460))
    if t:
        s.append(label(xs[i] + 210, 452, [t]))
# El COPY mueve datos del stage a Bronze dentro de Snowflake; los flows de Kestra solo lo ordenan.
s.append(label(310, 384, ["COPY por nombre de columna", "(lo ordenan los flows)"]))

# Flujos entre herramientas y Snowflake
s.append(arrow(120, 71, 120, 158)); s.append(label(130, 90, ["descarga"], "start"))
s.append(arrow(100, 250, 100, 408)); s.append(label(92, 315, ["PUT de", "los CSV"], "end"))
s.append(arrow(300, 250, 160, 408)); s.append(label(265, 312, ["publica la semana k", "(simulador de fuente)"], "start"))
s.append(arrow(690, 250, 600, 408, True)); s.append(arrow(730, 250, 815, 408, True))
s.append(label(710, 318, ["ejecuta SQL", "y tests"]))
s.append(arrow(870, 408, 960, 252)); s.append(label(858, 318, ["lee Gold"], "end"))
s.append(arrow(1100, 250, 1100, 408)); s.append(label(1090, 312, ["joins + validaciones,", "escribe la OBT"], "end"))
s.append('</svg>')

Path(__file__).with_name("arquitectura.svg").write_text("\n".join(s))
