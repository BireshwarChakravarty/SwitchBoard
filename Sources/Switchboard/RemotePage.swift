import Foundation

/// The iPhone web remote: one self-contained page (no external files, so it
/// works on a network without internet access), served by RemoteControl.
/// Add it to the Home Screen from Safari's Share menu to use it like an app.
enum RemotePage {
    static let manifest = ##"""
    {
      "name": "Switchboard",
      "short_name": "Switchboard",
      "start_url": "/",
      "display": "standalone",
      "background_color": "#101014",
      "theme_color": "#101014",
      "icons": [{ "src": "/icon.png", "sizes": "180x180", "type": "image/png" }]
    }
    """##

    static let html = ##"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-title" content="Switchboard">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="color-scheme" content="light dark">
    <link rel="apple-touch-icon" href="/icon.png">
    <link rel="manifest" href="/manifest.webmanifest">
    <title>Switchboard</title>
    <style>
    :root {
      --bg-1: #e9eef7; --bg-2: #f6f1ea;
      --card: rgba(255,255,255,.62); --card-edge: rgba(255,255,255,.75);
      --row: rgba(0,0,0,.045); --text: #1c1c1e; --muted: #6b6b72;
      --track: rgba(0,0,0,.09); --fill: #ffffff; --fill-edge: rgba(0,0,0,.08);
      --accent: #0a84ff; --danger: #ff3b30; --warn: #ff9f0a;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg-1: #0d0f16; --bg-2: #1a1420;
        --card: rgba(44,44,52,.55); --card-edge: rgba(255,255,255,.09);
        --row: rgba(255,255,255,.06); --text: #f5f5f7; --muted: #a1a1aa;
        --track: rgba(255,255,255,.12); --fill: #f5f5f7; --fill-edge: rgba(255,255,255,.2);
      }
    }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html { background: var(--bg-1); }
    body {
      margin: 0; min-height: 100vh; color: var(--text);
      font: 15px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      background:
        radial-gradient(120% 60% at 0% 0%, rgba(10,132,255,.18), transparent 60%),
        radial-gradient(100% 60% at 100% 100%, rgba(191,90,242,.16), transparent 60%),
        linear-gradient(160deg, var(--bg-1), var(--bg-2));
      background-attachment: fixed;
      -webkit-user-select: none; user-select: none;
    }
    main {
      max-width: 520px; margin: 0 auto;
      padding: calc(env(safe-area-inset-top) + 20px) 16px calc(env(safe-area-inset-bottom) + 28px);
    }
    header { padding: 4px 6px 16px; }
    h1 { font-size: 30px; font-weight: 700; letter-spacing: -.02em; margin: 0; }
    .sub { color: var(--muted); font-size: 14px; margin-top: 2px; }
    .card {
      background: var(--card); border: 1px solid var(--card-edge); border-radius: 24px;
      padding: 8px; margin-bottom: 14px;
      -webkit-backdrop-filter: blur(30px) saturate(180%); backdrop-filter: blur(30px) saturate(180%);
      box-shadow: 0 10px 30px rgba(0,0,0,.08);
    }
    .card > h2 { font-size: 13px; font-weight: 600; color: var(--muted); text-transform: uppercase;
      letter-spacing: .04em; margin: 8px 10px 6px; }
    .row { display: flex; align-items: center; gap: 12px; padding: 10px; border-radius: 16px; }
    .row.selectable { cursor: pointer; }
    .row.selected { background: var(--row); }
    .badge { width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center;
      background: var(--row); color: var(--muted); flex: none; }
    .badge.on { background: var(--accent); color: #fff; }
    .badge svg { width: 19px; height: 19px; }
    .grow { flex: 1; min-width: 0; }
    .name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .status { color: var(--muted); font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .status.problem { color: var(--warn); }

    .switch { appearance: none; -webkit-appearance: none; width: 51px; height: 31px; border-radius: 16px;
      background: var(--track); position: relative; flex: none; transition: background .2s; margin: 0; }
    .switch::after { content: ""; position: absolute; top: 2px; left: 2px; width: 27px; height: 27px;
      border-radius: 50%; background: #fff; box-shadow: 0 2px 6px rgba(0,0,0,.25); transition: transform .2s; }
    .switch:checked { background: #34c759; }
    .switch:checked::after { transform: translateX(20px); }
    .switch:disabled { opacity: .5; }

    .control { padding: 8px 10px 12px; }
    .control .label { display: flex; justify-content: space-between; font-weight: 600; margin-bottom: 8px; }
    .control .value { color: var(--muted); font-weight: 500; font-variant-numeric: tabular-nums; }
    input[type=range] { -webkit-appearance: none; appearance: none; width: 100%; height: 44px; margin: 0;
      border-radius: 22px; background: linear-gradient(to right, var(--fill) var(--p, 50%), var(--track) var(--p, 50%));
      box-shadow: inset 0 0 0 1px var(--fill-edge); touch-action: pan-y; }
    input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 0; height: 44px; }
    select { width: 100%; font: inherit; color: var(--text); background: var(--row); border: 0;
      border-radius: 14px; padding: 12px; -webkit-appearance: none; appearance: none; }
    .empty { color: var(--muted); padding: 6px 10px 12px; font-size: 14px; }

    details > summary { list-style: none; cursor: pointer; display: flex; justify-content: space-between;
      align-items: center; padding: 10px; font-weight: 600; }
    details > summary::-webkit-details-marker { display: none; }
    details > summary::after { content: "›"; color: var(--muted); font-size: 22px; transition: transform .2s; }
    details[open] > summary::after { transform: rotate(90deg); }
    .help { color: var(--muted); font-size: 14px; padding: 0 10px 8px; }
    .help ol { padding-left: 20px; margin: 6px 0; }
    .link { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-top: 1px solid var(--row); }
    .link .what { font-size: 14px; font-weight: 600; }
    .link .url { font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted);
      word-break: break-all; -webkit-user-select: all; user-select: all; }

    button { font: inherit; font-weight: 600; border: 0; border-radius: 999px; padding: 9px 16px;
      background: var(--row); color: var(--text); cursor: pointer; }
    button.primary { background: var(--accent); color: #fff; }
    button.small { padding: 6px 12px; font-size: 13px; flex: none; }
    button:disabled { opacity: .5; }

    #pair { text-align: center; padding: 24px 12px; }
    #pair p { color: var(--muted); margin: 8px 0 18px; }
    #code { width: 100%; max-width: 260px; font: 600 32px ui-monospace, SFMono-Regular, Menlo, monospace;
      letter-spacing: .3em; text-align: center; padding: 12px; border-radius: 16px; border: 0;
      background: var(--row); color: var(--text); -webkit-user-select: text; user-select: text; }
    #pair .error { color: var(--danger); min-height: 20px; margin: 10px 0; font-size: 14px; }

    footer { text-align: center; color: var(--muted); font-size: 13px; padding: 6px; }
    footer button { background: none; color: var(--accent); padding: 6px; font-weight: 500; }
    #toast { position: fixed; left: 50%; bottom: calc(env(safe-area-inset-bottom) + 20px);
      transform: translate(-50%, 20px); opacity: 0; transition: all .25s; max-width: calc(100% - 32px);
      background: rgba(30,30,34,.92); color: #fff; padding: 10px 16px; border-radius: 14px; font-size: 14px;
      pointer-events: none; }
    #toast.show { opacity: 1; transform: translate(-50%, 0); }
    [hidden] { display: none !important; }
    </style>
    </head>
    <body>
    <main>
      <header>
        <h1>Switchboard</h1>
        <div class="sub" id="mac">Your Mac's screens</div>
      </header>

      <section class="card" id="pair" hidden>
        <div class="badge on" style="margin: 0 auto 12px; width: 52px; height: 52px">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="5" y="2" width="14" height="20" rx="3"/><path d="M11 18h2"/></svg>
        </div>
        <h2 style="font-size: 20px; margin: 0">Pair this iPhone</h2>
        <p>Enter the code shown on your Mac in<br>Switchboard → Settings → iPhone Remote.</p>
        <form id="pairForm">
          <input id="code" inputmode="numeric" autocomplete="one-time-code" maxlength="7" placeholder="000000" aria-label="Pairing code">
          <div class="error" id="pairError" role="alert"></div>
          <button class="primary" type="submit" id="pairButton">Pair</button>
        </form>
      </section>

      <div id="app" hidden>
        <section class="card">
          <h2>Screens</h2>
          <div id="screens"></div>
        </section>
        <section class="card" id="controls"></section>
        <section class="card" id="all" hidden>
          <h2>All Screens</h2>
          <div id="allControl"></div>
        </section>
        <section class="card">
          <details id="shortcuts">
            <summary>Shortcuts &amp; Siri</summary>
            <div class="help">
              Make a shortcut for any of these, then run it from Siri, the Home Screen or Control Center:
              <ol>
                <li>In the Shortcuts app, tap <b>+</b> and add the <b>Get Contents of URL</b> action.</li>
                <li>Paste a link below as its URL.</li>
                <li>Tap <b>Show More</b> and set <b>Method</b> to <b>POST</b>.</li>
                <li>Name the shortcut, for example “ARZOPA Off”. Say it to Siri to run it.</li>
              </ol>
              Each link contains this iPhone's key: keep them to yourself. Your iPhone must be on the same network as the Mac.
            </div>
            <div id="links"></div>
          </details>
        </section>
        <footer>
          <div id="version"></div>
          <button type="button" id="unpair">Unpair this iPhone</button>
        </footer>
      </div>
    </main>
    <div id="toast" role="status"></div>

    <script>
    (function () {
      "use strict";
      var STORE = "switchboard.key";
      var key = null, state = null, selectedId = null, busy = 0, pollTimer = null;
      // While a slider is held (and briefly after), don't redraw under the finger.
      var holdUntil = 0;

      function load() { try { return localStorage.getItem(STORE); } catch (e) { return null; } }
      function save(value) {
        try { if (value) localStorage.setItem(STORE, value); else localStorage.removeItem(STORE); } catch (e) {}
      }
      function $(id) { return document.getElementById(id); }
      function el(tag, cls, text) {
        var node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text != null) node.textContent = text;
        return node;
      }

      var toastTimer = null;
      function toast(text) {
        var t = $("toast");
        t.textContent = text;
        t.classList.add("show");
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { t.classList.remove("show"); }, 2600);
      }

      function request(method, path, body) {
        var headers = {};
        if (key) headers["Authorization"] = "Bearer " + key;
        if (body) headers["Content-Type"] = "application/json";
        return fetch(path, { method: method, headers: headers, body: body ? JSON.stringify(body) : undefined, cache: "no-store" })
          .then(function (response) {
            return response.json().catch(function () { return {}; }).then(function (data) {
              if (response.status === 401 && path !== "/api/pair") { unpaired(); throw new Error(data.error || "Not paired"); }
              if (!response.ok) throw new Error(data.error || ("Error " + response.status));
              return data;
            });
          });
      }

      // Pairing

      function unpaired() {
        key = null; save(null); state = null;
        stopPolling();
        $("app").hidden = true;
        $("pair").hidden = false;
      }

      $("pairForm").addEventListener("submit", function (event) {
        event.preventDefault();
        var code = $("code").value.replace(/\D/g, "");
        if (code.length !== 6) { $("pairError").textContent = "The code has six digits."; return; }
        $("pairButton").disabled = true;
        $("pairError").textContent = "";
        request("POST", "/api/pair", { code: code }).then(function (data) {
          key = data.key; save(key);
          $("code").value = "";
          $("pair").hidden = true;
          start();
        }).catch(function (error) {
          $("pairError").textContent = error.message;
        }).then(function () { $("pairButton").disabled = false; });
      });

      $("unpair").addEventListener("click", function () {
        if (confirm("Unpair this iPhone? You'll need a new code from the Mac to pair it again.")) unpaired();
      });

      // State

      function refresh() {
        if (!key || busy > 0 || Date.now() < holdUntil) return Promise.resolve();
        return request("GET", "/api/screens").then(apply).catch(function () {});
      }

      function apply(next) {
        state = next;
        render();
      }

      function startPolling() {
        stopPolling();
        pollTimer = setInterval(function () { if (!document.hidden) refresh(); }, 3000);
      }
      function stopPolling() { if (pollTimer) clearInterval(pollTimer); pollTimer = null; }

      function start() {
        $("app").hidden = false;
        refresh();
        startPolling();
      }

      document.addEventListener("visibilitychange", function () { if (!document.hidden) refresh(); });

      function act(path) {
        busy++;
        return request("POST", path).then(function (data) {
          if (data.state) apply(data.state);
          return data;
        }).catch(function (error) {
          toast(error.message);
          throw error;
        }).then(function (data) { busy--; return data; }, function (error) { busy--; refresh(); throw error; });
      }

      // Rendering

      var monitorIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/></svg>';

      function screenStatus(screen) {
        if (screen.problem) return { text: screen.problem, problem: true };
        if (!screen.isOn) return { text: "Off" };
        if (screen.note) return { text: screen.note };
        if (screen.isBuiltIn) return { text: "Built-in" };
        return { text: screen.brightness != null ? "Brightness " + screen.brightness + "%" : "On" };
      }

      function render() {
        if (!state) return;
        $("mac").textContent = state.mac;
        $("version").textContent = "Switchboard · " + state.version;
        var screens = state.screens;
        if (!screens.some(function (s) { return s.id === selectedId; })) {
          var first = screens.filter(function (s) { return s.isOn && !s.isBuiltIn; })[0] || screens[0];
          selectedId = first ? first.id : null;
        }

        var list = $("screens");
        list.textContent = "";
        if (!screens.length) list.appendChild(el("div", "empty", "No screens found."));
        screens.forEach(function (screen) {
          var row = el("div", "row selectable" + (screen.id === selectedId ? " selected" : ""));
          var badge = el("div", "badge" + (screen.isOn ? " on" : ""));
          badge.innerHTML = monitorIcon;
          var text = el("div", "grow");
          text.appendChild(el("div", "name", screen.name));
          var status = screenStatus(screen);
          text.appendChild(el("div", "status" + (status.problem ? " problem" : ""), status.text));
          row.appendChild(badge);
          row.appendChild(text);
          if (screen.canSwitch) {
            var toggle = el("input", "switch");
            toggle.type = "checkbox";
            toggle.checked = screen.isOn;
            toggle.setAttribute("aria-label", "Power for " + screen.name);
            toggle.addEventListener("click", function (event) { event.stopPropagation(); });
            toggle.addEventListener("change", function () {
              toggle.disabled = true;
              act("/api/screens/" + screen.id + "/" + (toggle.checked ? "on" : "off")).catch(function () {});
            });
            row.appendChild(toggle);
          }
          row.addEventListener("click", function () { selectedId = screen.id; render(); });
          list.appendChild(row);
        });

        renderControls(screens.filter(function (s) { return s.id === selectedId; })[0]);
        renderAll();
        renderLinks();
      }

      function slider(label, value, onSet) {
        var wrap = el("div", "control");
        var head = el("div", "label");
        head.appendChild(el("span", null, label));
        var shown = el("span", "value", value + "%");
        head.appendChild(shown);
        var input = el("input");
        input.type = "range"; input.min = 0; input.max = 100; input.step = 1; input.value = value;
        input.setAttribute("aria-label", label);
        input.style.setProperty("--p", value + "%");

        // Send the latest value at most every 120 ms while dragging.
        var pending = null, sending = false;
        function flush() {
          if (pending == null || sending) return;
          var v = pending; pending = null; sending = true;
          onSet(v).catch(function () {}).then(function () {
            sending = false;
            setTimeout(flush, 120);
          });
        }
        input.addEventListener("input", function () {
          shown.textContent = input.value + "%";
          input.style.setProperty("--p", input.value + "%");
          pending = Number(input.value);
          flush();
        });
        input.addEventListener("pointerdown", function () { holdUntil = Infinity; });
        function release() { holdUntil = Date.now() + 1500; }
        input.addEventListener("pointerup", release);
        input.addEventListener("pointercancel", release);
        input.addEventListener("change", function () {
          pending = Number(input.value);
          flush();
          release();
        });
        wrap.appendChild(head);
        wrap.appendChild(input);
        return wrap;
      }

      function setControl(screenId, control) {
        return function (value) {
          return request("POST", "/api/screens/" + screenId + "/" + control + "/" + value)
            .catch(function (error) { toast(error.message); });
        };
      }

      function renderControls(screen) {
        var card = $("controls");
        if (card.contains(document.activeElement) && document.activeElement.tagName === "SELECT") return;
        card.textContent = "";
        if (!screen) { card.hidden = true; return; }
        card.hidden = false;
        card.appendChild(el("h2", null, screen.name));
        if (!screen.isOn) { card.appendChild(el("div", "empty", "Switched off.")); return; }
        var any = false;
        if (screen.brightness != null) { any = true; card.appendChild(slider("Brightness", screen.brightness, setControl(screen.id, "brightness"))); }
        if (screen.contrast != null) { any = true; card.appendChild(slider("Contrast", screen.contrast, setControl(screen.id, "contrast"))); }
        if (screen.volume != null) { any = true; card.appendChild(slider("Volume", screen.volume, setControl(screen.id, "volume"))); }
        if (screen.resolutions.length > 1 && screen.resolution != null) {
          any = true;
          var wrap = el("div", "control");
          var head = el("div", "label");
          head.appendChild(el("span", null, "Resolution"));
          wrap.appendChild(head);
          var select = el("select");
          select.setAttribute("aria-label", "Resolution");
          screen.resolutions.forEach(function (label, index) {
            var option = el("option", null, label);
            option.value = index;
            if (index === screen.resolution) option.selected = true;
            select.appendChild(option);
          });
          select.addEventListener("change", function () {
            act("/api/screens/" + screen.id + "/resolution/" + select.value).catch(function () {});
            select.blur();
          });
          wrap.appendChild(select);
          card.appendChild(wrap);
        }
        if (!any) card.appendChild(el("div", "empty", "This screen has no adjustable controls."));
      }

      function renderAll() {
        var card = $("all");
        if (state.allScreens == null) { card.hidden = true; return; }
        card.hidden = false;
        var holder = $("allControl");
        holder.textContent = "";
        holder.appendChild(slider("Brightness", state.allScreens, function (value) {
          return request("POST", "/api/screens/all/brightness/" + value).catch(function (error) { toast(error.message); });
        }));
      }

      function copy(text) {
        var field = el("textarea");
        field.value = text;
        field.setAttribute("readonly", "");
        field.style.position = "fixed"; field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        field.setSelectionRange(0, text.length);
        var ok = false;
        try { ok = document.execCommand("copy"); } catch (e) {}
        document.body.removeChild(field);
        if (!ok && navigator.clipboard) {
          navigator.clipboard.writeText(text).then(function () { toast("Copied"); }, function () { toast("Press and hold the link to copy it"); });
          return;
        }
        toast(ok ? "Copied" : "Press and hold the link to copy it");
      }

      function renderLinks() {
        var holder = $("links");
        if ($("shortcuts").open && holder.childElementCount) return; // keep it still while it's being used
        holder.textContent = "";
        var base = location.origin + "/api/screens/";
        var items = [];
        state.screens.forEach(function (screen) {
          if (screen.canSwitch) {
            items.push([screen.name + " On", screen.slug + "/on"]);
            items.push([screen.name + " Off", screen.slug + "/off"]);
            items.push([screen.name + " On/Off", screen.slug + "/toggle"]);
          }
          if (screen.brightness != null) items.push([screen.name + " Brightness 50%", screen.slug + "/brightness/50"]);
        });
        if (state.allScreens != null) items.push(["All Screens Brightness 50%", "all/brightness/50"]);
        items.forEach(function (item) {
          var url = base + item[1] + "?key=" + encodeURIComponent(key);
          var row = el("div", "link");
          var text = el("div", "grow");
          text.appendChild(el("div", "what", item[0]));
          text.appendChild(el("div", "url", url));
          var button = el("button", "small", "Copy");
          button.type = "button";
          button.addEventListener("click", function () { copy(url); });
          row.appendChild(text);
          row.appendChild(button);
          holder.appendChild(row);
        });
        if (!items.length) holder.appendChild(el("div", "empty", "No screens to make shortcuts for."));
        var note = el("div", "help", "Change the number at the end of a brightness link to any value from 0 to 100.");
        note.style.paddingTop = "8px";
        holder.appendChild(note);
      }

      key = load();
      if (key) start(); else unpaired();
    })();
    </script>
    </body>
    </html>
    """##
}
