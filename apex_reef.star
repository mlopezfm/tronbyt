"""
Applet: Apex Reef
Summary: Reef parameters from Apex
Description: Shows temperature, pH, alkalinity, calcium, magnesium and salinity read directly from a Neptune Systems Apex controller on your local network.
Author: claude
"""

load("cache.star", "cache")
load("http.star", "http")
load("humanize.star", "humanize")
load("images/apex_logo_16.png", APEX_LOGO_16_ASSET = "file")
load("images/apex_logo_8.png", APEX_LOGO_8_ASSET = "file")
load("render.star", "canvas", "render")
load("schema.star", "schema")

APEX_LOGO_8 = APEX_LOGO_8_ASSET.readall()
APEX_LOGO_16 = APEX_LOGO_16_ASSET.readall()

DEFAULT_HOST = "192.168.1.230"
SID_TTL_SECONDS = 1800
STATUS_TTL_SECONDS = 60

# On 64x32 the six readings don't fit at a readable size, so they alternate
# between two pages of three.
PAGE_FRAMES = 50
FRAME_DELAY_MS = 100

LABEL_COLOR = "#7FA7C9"
OK_COLOR = "#FFFFFF"
WARN_COLOR = "#FF5A36"
MISSING_COLOR = "#555555"

# The reading shown on each row, in display order. `types` are the Apex input
# types (lowercased) that can supply it; `name_key` is the config field that
# lets the user pin a specific probe by its Apex name. Each label gets its own
# `color` so the rows are easy to tell apart at a glance.
PARAMS = [
    {"key": "temp", "color": "#18FFFF", "short": "TEMP", "long": "Temp", "types": ["temp"], "name_key": "temp_name"},
    {"key": "ph", "color": "#BA68C8", "short": "PH", "long": "pH", "types": ["ph"], "name_key": "ph_name"},
    {"key": "alk", "color": "#FFEE58", "short": "ALK", "long": "Alkalinity", "types": ["alk"], "name_key": "alk_name"},
    {"key": "ca", "color": "#81C784", "short": "CA", "long": "Calcium", "types": ["ca"], "name_key": "ca_name"},
    {"key": "mg", "color": "#F06292", "short": "MG", "long": "Magnesium", "types": ["mg"], "name_key": "mg_name"},
    {"key": "salt", "color": "#448AFF", "short": "SALT", "long": "Salinity", "types": ["cond", "salt", "salinity"], "name_key": "salt_name"},
]

PROBE_KEYS = ["temp", "ph", "salt"]
TRIDENT_KEYS = ["alk", "ca", "mg"]

DEMO_VALUES = {
    "temp": 78.4,
    "ph": 8.12,
    "alk": 8.3,
    "ca": 425,
    "mg": 1350,
    "salt": 35.0,
}

def is_square():
    w, h = canvas.size()
    return h == w

def base_url(host):
    host = host.strip().rstrip("/")
    if not host.startswith("http://") and not host.startswith("https://"):
        host = "http://" + host
    return host

def parse_json(response):
    """Returns the decoded body, or None when the response is not usable JSON."""
    if response.status_code != 200:
        return None
    body = response.body().strip()
    if not body.startswith("{"):
        return None
    return response.json()

def rest_login(base, username, password):
    """Logs in to the Apex REST API (firmware 5.x+) and returns the session id."""
    response = http.post(
        base + "/rest/login",
        json_body = {"login": username, "password": password, "remember_me": False},
    )
    data = parse_json(response)
    if data and data.get("connect.sid"):
        return data["connect.sid"]

    for part in response.headers.get("Set-Cookie", "").split(";"):
        part = part.strip()
        if part.startswith("connect.sid="):
            return part[len("connect.sid="):]
    return None

def rest_status(base, sid):
    response = http.get(
        base + "/rest/status",
        headers = {"Cookie": "connect.sid=" + sid},
        ttl_seconds = STATUS_TTL_SECONDS,
    )
    return parse_json(response)

def legacy_status(base, username, password):
    """Older firmware only offers status.json behind HTTP basic auth."""
    response = http.get(
        base + "/cgi-bin/status.json",
        auth = (username, password),
        ttl_seconds = STATUS_TTL_SECONDS,
    )
    return parse_json(response)

def fetch_inputs(host, username, password):
    """Returns the list of Apex inputs, or None if the Apex could not be read."""
    base = base_url(host)
    sid_key = "apex_sid_{}_{}".format(base, username)

    status = None
    sid = cache.get(sid_key)
    if sid:
        status = rest_status(base, sid)

    if not status:
        sid = rest_login(base, username, password)
        if sid:
            # cache.set is a no-op outside of the server, so this is safe in `pixlet render`.
            cache.set(sid_key, sid, ttl_seconds = SID_TTL_SECONDS)
            status = rest_status(base, sid)

    if not status:
        status = legacy_status(base, username, password)

    if not status:
        return None

    # /rest/status puts inputs at the top level, status.json nests them under "istat".
    if "istat" in status:
        status = status["istat"]
    return status.get("inputs")

def find_value(inputs, param, wanted_name):
    wanted_name = wanted_name.strip().lower()
    for item in inputs:
        name = str(item.get("name", "")).lower()
        kind = str(item.get("type", "")).lower()
        if wanted_name:
            if name == wanted_name:
                return item.get("value")
        elif kind in param["types"]:
            return item.get("value")
    return None

def num(fmt, value):
    return humanize.float(fmt, float(value))

def format_value(key, value, show_units):
    """Returns (text, in_range) for a reading. in_range is None when there is no target range."""
    if value == None:
        return ("--", None)
    value = float(value)

    if key == "temp":
        # The Apex reports in whatever unit it is set to; reef temps under 50 must be Celsius.
        celsius = value < 50
        text = num("#.#", value)
        if show_units:
            text += "°C" if celsius else "°F"
        low, high = (24.4, 27.2) if celsius else (76.0, 81.0)
    elif key == "ph":
        text = num("#.##", value)
        low, high = (7.8, 8.5)
    elif key == "alk":
        # Trident defaults to dKH; anything this low is meq/L.
        meq = value < 5
        text = num("#.##", value) if meq else num("#.#", value)
        if show_units:
            text += " meq" if meq else " dKH"
        low, high = (2.5, 4.0) if meq else (7.0, 11.0)
    elif key == "ca":
        text = num("#.", value)
        if show_units:
            text += " ppm"
        low, high = (380.0, 480.0)
    elif key == "mg":
        text = num("#.", value)
        if show_units:
            text += " ppm"
        low, high = (1250.0, 1450.0)
    elif key == "salt":
        # A conductivity probe can be set to report ppt or specific gravity.
        sg = value < 2
        text = num("#.###", value) if sg else num("#.#", value)
        if show_units:
            text += " SG" if sg else " ppt"
        low, high = (1.023, 1.027) if sg else (32.0, 36.0)
    else:
        return (num("#.##", value), None)

    return (text, value >= low and value <= high)

def value_color(in_range, highlight):
    if in_range == None:
        return MISSING_COLOR
    if highlight and not in_range:
        return WARN_COLOR
    return OK_COLOR

def build_rows(params, values, config, font, width, row_height, long_labels):
    show_units = config.bool("show_units", True)
    highlight = config.bool("highlight", True)

    rows = []
    for param in params:
        text, in_range = format_value(param["key"], values.get(param["key"]), show_units)
        rows.append(
            render.Box(
                width = width,
                height = row_height,
                child = render.Row(
                    expanded = True,
                    main_align = "space_between",
                    cross_align = "center",
                    children = [
                        render.Text(param["long"] if long_labels else param["short"], font = font, color = param["color"]),
                        render.Text(text, font = font, color = value_color(in_range, highlight)),
                    ],
                ),
            ),
        )
    return rows

def header(config):
    """Logo in the top-left corner with the title beside it."""
    return render.Row(
        cross_align = "center",
        children = [
            render.Image(src = APEX_LOGO_8),
            render.Box(width = 2, height = 8),
            render.Text(config.get("title", "Reef") or "Reef", font = "tb-8", color = LABEL_COLOR),
        ],
    )

def render_values(values, config):
    width, _ = canvas.size()

    if canvas.is2x():
        # Logo column on the left, all six readings beside it.
        rows = build_rows(PARAMS, values, config, "6x10", width - 2 - 13 - 3 - 2, 10, True)
        return render.Root(
            child = render.Padding(
                pad = (2, 2, 2, 0),
                child = render.Row(
                    children = [
                        render.Image(src = APEX_LOGO_16),
                        render.Box(width = 3, height = 16),
                        render.Column(children = rows),
                    ],
                ),
            ),
        )

    if is_square():
        rows = build_rows(PARAMS, values, config, "tb-8", width - 2, 9, False)
        return render.Root(
            child = render.Padding(
                pad = (1, 1, 1, 0),
                child = render.Column(
                    children = [
                        header(config),
                        render.Box(width = width - 2, height = 1, color = "#1E3A52"),
                    ] + rows,
                ),
            ),
        )

    pages = []
    for group in (PROBE_KEYS, TRIDENT_KEYS):
        params = [p for p in PARAMS if p["key"] in group]
        pages.append(render.Column(children = build_rows(params, values, config, "tb-8", width - 2, 8, False)))
    return render.Root(
        delay = FRAME_DELAY_MS,
        show_full_animation = True,
        child = render.Padding(
            pad = (1, 0, 1, 0),
            child = render.Column(
                children = [
                    header(config),
                    render.Animation(children = [pages[0]] * PAGE_FRAMES + [pages[1]] * PAGE_FRAMES),
                ],
            ),
        ),
    )

def render_message(message):
    font = "terminus-12" if canvas.is2x() else "tb-8"
    return render.Root(
        child = render.Box(
            child = render.WrappedText(content = message, font = font, color = WARN_COLOR, align = "center"),
        ),
    )

def main(config):
    host = config.get("host", "")
    username = config.get("username", "")
    password = config.get("password", "")

    if not host or not username or not password:
        return render_values(DEMO_VALUES, config)

    inputs = fetch_inputs(host, username, password)
    if inputs == None:
        return render_message("Apex login failed")

    values = {}
    for param in PARAMS:
        values[param["key"]] = find_value(inputs, param, config.get(param["name_key"], ""))

    return render_values(values, config)

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "host",
                name = "Apex address",
                desc = "IP address or hostname of your Apex on the local network, e.g. " + DEFAULT_HOST,
                icon = "server",
                default = DEFAULT_HOST,
            ),
            schema.Text(
                id = "username",
                name = "Username",
                desc = "Apex local login (default: admin)",
                icon = "user",
                default = "admin",
            ),
            schema.Text(
                id = "password",
                name = "Password",
                desc = "Apex local password",
                icon = "lock",
                secret = True,
            ),
            schema.Toggle(
                id = "highlight",
                name = "Highlight out of range",
                desc = "Show readings outside typical reef ranges in red",
                icon = "triangleExclamation",
                default = True,
            ),
            schema.Toggle(
                id = "show_units",
                name = "Show units",
                desc = "Show units next to each reading",
                icon = "ruler",
                default = True,
            ),
            schema.Text(
                id = "title",
                name = "Title",
                desc = "Text shown next to the logo on 64x32 and 64x64 displays",
                icon = "heading",
                default = "Reef",
            ),
            schema.Text(
                id = "temp_name",
                name = "Temperature probe name",
                desc = "Optional. Apex input name to use (e.g. Tmp). Leave blank to auto-detect.",
                icon = "temperatureHalf",
                default = "",
            ),
            schema.Text(
                id = "ph_name",
                name = "pH probe name",
                desc = "Optional. Apex input name to use (e.g. pH). Leave blank to auto-detect.",
                icon = "flask",
                default = "",
            ),
            schema.Text(
                id = "alk_name",
                name = "Alkalinity input name",
                desc = "Optional. Apex input name to use (e.g. Alkx4). Leave blank to auto-detect.",
                icon = "vial",
                default = "",
            ),
            schema.Text(
                id = "ca_name",
                name = "Calcium input name",
                desc = "Optional. Apex input name to use (e.g. Cax4). Leave blank to auto-detect.",
                icon = "vial",
                default = "",
            ),
            schema.Text(
                id = "mg_name",
                name = "Magnesium input name",
                desc = "Optional. Apex input name to use (e.g. Mgx4). Leave blank to auto-detect.",
                icon = "vial",
                default = "",
            ),
            schema.Text(
                id = "salt_name",
                name = "Salinity probe name",
                desc = "Optional. Apex input name to use (e.g. Salt). Leave blank to auto-detect.",
                icon = "water",
                default = "",
            ),
        ],
    )
