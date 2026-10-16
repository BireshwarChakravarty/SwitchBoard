# Remote API

When **Settings → iPhone Remote** is on, Switchboard serves a web page and a
small JSON API on port **8723** of your Mac, on the local network only. The
iPhone web app and the generated Siri shortcuts both use this API, and you can
use it from Shortcuts, scripts or home-automation tools.

```text
http://<your-mac>.local:8723
```

## Authentication

Every API request except pairing needs a key. Send it in any of these:

- `Authorization: Bearer <key>`
- `X-Switchboard-Key: <key>`
- `?key=<key>` in the URL (convenient in Shortcuts)

To get a key, pair with the six-digit code shown under **Settings → iPhone
Remote**:

```bash
curl -X POST http://mac-mini.local:8723/api/pair -d '{"code": "482913"}'
# {"key":"9f86d0…"}
```

The code changes after each successful pairing, and is replaced after five
wrong attempts. Keys stay valid until **Forget All** or **Reset to Defaults**.
**Add Shortcuts…** issues its own key. Switchboard stores only SHA-256 hashes
of keys.

## Endpoints

| Method | Path | Action |
|---|---|---|
| `GET` | `/api/screens` | Every screen's state |
| `POST` | `/api/screens/<screen>/on` | Switch a screen on |
| `POST` | `/api/screens/<screen>/off` | Switch a screen off |
| `POST` | `/api/screens/<screen>/toggle` | Switch a screen on or off |
| `POST` | `/api/screens/<screen>/brightness/<0–100>` | Set brightness (combined hardware and software) |
| `POST` | `/api/screens/<screen>/contrast/<0–100>` | Set contrast (DDC/CI monitors) |
| `POST` | `/api/screens/<screen>/volume/<0–100>` | Set speaker volume (DDC/CI monitors) |
| `POST` | `/api/screens/<screen>/resolution/<n>` | Choose a resolution by its index in `resolutions` |
| `POST` | `/api/screens/all/brightness/<0–100>` | Set every adjustable screen's brightness |
| `POST` | `/api/pair` | Exchange a pairing code for a key |

Actions must use `POST`; reads use `GET`. Values may be decimals or end in `%`
(`40.5`, `40%`); they're rounded to whole numbers.

`<screen>` is a screen's name, matched loosely: any case, with or without
spaces or punctuation (`dell-u2723qe`, `DELL U2723QE`), or a unique part of it
(`u2723`). A numeric display ID also works. A name that matches more than one
screen is rejected.

## Responses

Actions return a human-readable `message`, which Shortcuts shows and Siri
reads out, and the new state:

```json
{
  "message": "Portable Display switched off",
  "state": { "...": "as GET /api/screens" }
}
```

`GET /api/screens`:

```json
{
  "mac": "Mac mini",
  "version": "Version 2.0.2",
  "allScreens": 60,
  "screens": [
    {
      "id": 2,
      "name": "DELL U2723QE",
      "slug": "dell-u2723qe",
      "isOn": true,
      "isBuiltIn": false,
      "canSwitch": false,
      "note": "Mirrored to Portable Display",
      "problem": null,
      "brightness": 70,
      "contrast": 50,
      "volume": 30,
      "resolutions": ["1920 × 1080", "2560 × 1440", "3840 × 2160"],
      "resolution": 1
    }
  ]
}
```

Controls a screen doesn't support are `null`. `canSwitch` is false for a
screen whose power switch is hidden, and for the last screen that's on.

## Errors

Errors use HTTP status codes, with `error` and `message` both set to a
readable explanation:

| Status | Meaning |
|---|---|
| `400` | Bad value, such as a brightness over 100 |
| `401` | Missing or unknown key, or a wrong pairing code |
| `404` | Unknown path, or no screen matches the name |
| `405` | Wrong method (actions need `POST`) |
| `409` | Not possible right now: the screen is off, its switch is hidden, it's the only screen on, or it has no such control |
| `429` | Too many wrong pairing codes; the Mac shows a new one |

## Examples

```bash
KEY=9f86d0…
MAC=http://mac-mini.local:8723

curl -X POST "$MAC/api/screens/portable-display/off" -H "Authorization: Bearer $KEY"
curl -X POST "$MAC/api/screens/all/brightness/40" -H "Authorization: Bearer $KEY"
curl "$MAC/api/screens" -H "Authorization: Bearer $KEY"
```

In Shortcuts, use **Get Contents of URL** with the full URL (including
`?key=`) and **Method** set to **POST**.

## Security notes

The API is plain HTTP on your local network, so anyone who can watch your
network traffic could read a key. Use it on networks you trust, and use
**Forget All** if a key may have leaked. The server accepts one request per
connection, rejects requests over 64 KB, and drops connections that stall.
