const $ = (id) => document.getElementById(id);
const chat = $('chat');
const feed = $('feed');
const rows = $('rows');
const input = $('input');
const suggestEl = $('suggest');

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'fivechat';
const post = (name, data = {}) =>
    fetch(`https://${resource}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) }).catch(() => {});

// Lua sends an empty or sparse list as an object
const list = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);

let cfg = { fadeAfter: 10000, maxLength: 256, showIds: true, localChat: true };
let me = { id: null, names: [], ownStaff: true };
let open = false;
let active = 'all';
let fadeTimer;
const KEEP = 250;

function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
}

// ------------------------------------------------------------------ tabs

const tabs = {
    all: { label: 'All' },
    local: { label: 'Local' },
    ooc: { label: 'OOC' },
    staff: { label: 'Staff', hidden: true },
    call: { label: '911', hidden: true },
};

for (const [id, t] of Object.entries(tabs)) {
    t.el = el('button', 'tab');
    t.el.append(el('span', '', t.label), (t.dot = el('i', 'dot')));
    t.el.addEventListener('mousedown', (e) => e.preventDefault());
    t.el.addEventListener('click', () => setTab(id));
    $('tabs').append(t.el);
}

function drawTabs() {
    for (const [id, t] of Object.entries(tabs)) {
        t.el.hidden = !!t.hidden;
        t.el.classList.toggle('on', id === active);
    }
    const mode = sendMode();
    $('mode').textContent = { ooc: 'OOC', staff: 'Staff' }[mode] || (cfg.localChat ? 'Local' : 'Say');
    $('mode').className = `mode ${mode}`;
    input.placeholder = mode === 'say' && cfg.localChat ? 'Talk to people nearby, or type / for commands' : 'Type a message';
}

function setTab(id) {
    if (!tabs[id] || tabs[id].hidden) id = 'all';
    active = id;
    for (const [k, t] of Object.entries(tabs)) if (id === 'all' || k === id) t.dot.className = 'dot';
    for (const row of rows.children) row.hidden = !shows(row.dataset.channel);
    feed.scrollTop = feed.scrollHeight;
    drawTabs();
}

const shows = (channel) => active === 'all' || active === channel;
const sendMode = () => (active === 'ooc' ? 'ooc' : active === 'staff' ? 'staff' : 'say');

function unread(channel, mention) {
    for (const id of new Set(['all', channel])) {
        const t = tabs[id];
        if (!t || t.hidden || shows(id)) continue;
        if (!t.dot.classList.contains('mention')) t.dot.className = mention ? 'dot on mention' : 'dot on';
    }
}

// ------------------------------------------------------- colour codes, templates

const colors = ['#f4f2fb', '#ff5c6c', '#3dd68c', '#f7d046', '#5c9dff', '#2bd9cc', '#c77dff', '#f4f2fb', '#ff8a5c', '#9aa0b4'];

// Writes text with ^1 style codes as spans. State carries over between writes.
class Painter {
    constructor() {
        this.frag = document.createDocumentFragment();
        this.color = null;
        this.bold = this.under = this.strike = false;
    }
    code(c) {
        if (c >= '0' && c <= '9') this.color = colors[+c];
        else if (c === '*') this.bold = true;
        else if (c === '_') this.under = true;
        else if (c === '~') this.strike = true;
        else if (c === '=') this.under = this.strike = true;
        else if (c === 'r') { this.color = null; this.bold = this.under = this.strike = false; }
    }
    write(text, base) {
        String(text).split(/\^([0-9*_~=r])/).forEach((bit, i) => {
            if (i % 2) return this.code(bit);
            if (!bit) return;
            const color = this.color || base;
            if (!color && !this.bold && !this.under && !this.strike) return this.frag.append(bit);
            const s = el('span', '', bit);
            if (color) s.style.color = color;
            if (this.bold) s.style.fontWeight = '700';
            const deco = [this.under && 'underline', this.strike && 'line-through'].filter(Boolean).join(' ');
            if (deco) s.style.textDecoration = deco;
            this.frag.append(s);
        });
        return this;
    }
}

const templates = { default: '<b>{0}</b>: {1}', defaultAlt: '{0}', print: '<pre>{0}</pre>' };

const allowed = new Set(['B', 'STRONG', 'I', 'EM', 'U', 'S', 'SMALL', 'SPAN', 'DIV', 'P', 'BR', 'PRE', 'CODE', 'H1', 'H2', 'H3', 'H4', 'UL', 'OL', 'LI']);
const dropped = new Set(['SCRIPT', 'STYLE', 'TEMPLATE', 'IFRAME', 'OBJECT', 'EMBED', 'NOSCRIPT', 'TITLE', 'TEXTAREA', 'SVG', 'MATH', 'SELECT']);

// Templates come from other resources and are allowed some markup, but nothing
// that runs, loads or covers the screen. Unknown tags become their text.
function sanitize(node) {
    for (const child of [...node.childNodes]) {
        if (child.nodeType === Node.TEXT_NODE) continue;
        const tag = child.nodeName.toUpperCase();
        if (child.nodeType !== Node.ELEMENT_NODE || dropped.has(tag)) {
            child.remove();
            continue;
        }
        if (!allowed.has(tag)) {
            child.replaceWith(document.createTextNode(child.textContent));
            continue;
        }
        for (const a of [...child.attributes]) if (a.name !== 'class' && a.name !== 'style') child.removeAttribute(a.name);
        for (const p of [...child.style]) {
            if (p === 'position' || /url\(|expression|image-set/i.test(child.style.getPropertyValue(p))) child.style.removeProperty(p);
        }
        sanitize(child);
    }
}

const rgb = (c) => {
    c = list(c).map((n) => Math.max(0, Math.min(255, Number(n) || 0)));
    return c.length >= 3 ? `rgb(${c[0]}, ${c[1]}, ${c[2]})` : null;
};

// The default chat's message format: args put into a template. The template is
// parsed and cleaned first, args only ever go in as text.
function stock(m) {
    const args = list(m.args).map((a) => (a === null || a === undefined ? '' : String(a)));
    const params = m.params && typeof m.params === 'object' ? m.params : {};
    const tpl = m.template || templates[m.templateId] || (args.length > 1 ? templates.default : templates.defaultAlt);
    const color = rgb(m.color);

    const t = document.createElement('template');
    t.innerHTML = String(tpl);
    const body = t.content;
    sanitize(body);

    const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
    const texts = [];
    while (walker.nextNode()) texts.push(walker.currentNode);
    for (const node of texts) {
        const p = new Painter();
        node.nodeValue.split(/\{(\w+)\}/).forEach((part, i) => {
            if (i % 2 === 0) return p.write(part);
            const v = /^\d+$/.test(part) ? args[+part] : params[part];
            if (v === undefined || v === null) return p.write(`{${part}}`);
            p.write(String(v), part === '0' ? color : null);
        });
        node.replaceWith(p.frag);
    }

    const row = el('div', m.multiline ? 'msg stock multiline' : 'msg stock');
    row.append(body);
    let channel = tabs[m.channel] ? m.channel : 'all';
    if (!tabs[m.channel] && args.length > 1 && args[0].startsWith('[Staff] ')) channel = 'staff';
    return { row, channel };
}

// ------------------------------------------------------------- own messages

const tags = { ooc: 'OOC', looc: 'LOOC', twt: 'Twitter', ad: 'Advert', call: '911', staff: 'Staff' };

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function mentions(m) {
    if (!m.id || m.id === me.id || m.kind === 'system') return false;
    const text = m.text || '';
    if (me.id && new RegExp(`(^|[^\\w])@${me.id}(?!\\d)`).test(text)) return true;
    return me.names.some((n) => n && n.length > 2 && new RegExp(`(^|[^\\p{L}\\p{N}])@?${escapeRe(n)}($|[^\\p{L}\\p{N}])`, 'iu').test(text));
}

function who(m) {
    const frag = document.createDocumentFragment();
    if (cfg.showIds && m.id) frag.append(el('span', 'id', m.id));
    frag.append(el('span', 'who', m.author || ''));
    return frag;
}

function rp(m) {
    const row = el('div', `msg ${m.kind}`);
    if (tags[m.kind]) row.append(el('span', 'tag', tags[m.kind]));
    const text = el('span', 'text', m.text || '');

    if (m.kind === 'system') {
        row.append(text);
    } else if (m.kind === 'me') {
        row.append(who(m), text);
    } else if (m.kind === 'do') {
        row.append(text, el('span', 'by', `(( ${m.author || ''} ))`));
        if (cfg.showIds && m.id) row.append(el('span', 'id', m.id));
    } else if (m.kind === 'twt') {
        row.append(who(m), el('span', 'handle', `@${(m.author || '').replace(/\s+/g, '_')}`), text);
    } else {
        row.append(who(m));
        if (m.where) row.append(el('span', 'where', m.where));
        row.append(text);
    }
    if (m.far) row.classList.add('far');
    const mention = mentions(m);
    if (mention) row.classList.add('mention');
    return { row, channel: tabs[m.channel] ? m.channel : 'all', mention };
}

function add(m) {
    if (!m || typeof m !== 'object') return;
    const { row, channel, mention } = m.kind ? rp(m) : stock(m);
    if (channel === 'call' || channel === 'staff') {
        if (tabs[channel].hidden && (channel === 'staff' || me.emergency)) {
            tabs[channel].hidden = false;
            drawTabs();
        }
    }
    row.dataset.channel = channel;
    row.hidden = !shows(channel);

    const atBottom = feed.scrollTop + feed.clientHeight >= feed.scrollHeight - 24;
    rows.append(row);
    while (rows.childElementCount > KEEP) rows.firstElementChild.remove();
    if (atBottom || !open) feed.scrollTop = feed.scrollHeight;

    if (row.hidden) unread(channel, mention);
    else wake();
}

// --------------------------------------------------------------- fading

function wake() {
    chat.classList.remove('faded');
    clearTimeout(fadeTimer);
    if (!open) fadeTimer = setTimeout(() => chat.classList.add('faded'), cfg.fadeAfter);
}

// ------------------------------------------------------------ suggestions

const suggestions = new Map();
let cycle = null;

function addSuggestion(s) {
    if (!s || typeof s.name !== 'string' || !s.name) return;
    const name = s.name.startsWith('/') ? s.name : `/${s.name}`;
    const params = list(s.params).filter((p) => p && typeof p.name === 'string').map((p) => ({ name: p.name, help: p.help ? String(p.help) : '' }));
    const help = s.help ? String(s.help) : '';
    // a bare name from a command list shouldn't replace one that has help
    if (suggestions.has(name.toLowerCase()) && !help && !params.length) return;
    suggestions.set(name.toLowerCase(), { name, help, params });
}

function matches(text) {
    const word = text.split(' ')[0].toLowerCase();
    if (text.includes(' ')) return suggestions.has(word) ? [suggestions.get(word)] : [];
    return [...suggestions.entries()]
        .filter(([k]) => k.startsWith(word))
        .sort(([a], [b]) => a.length - b.length || a.localeCompare(b))
        .slice(0, 6)
        .map(([, s]) => s);
}

function drawSuggest() {
    const text = cycle ? cycle.base : input.value;
    if (!open || !text.startsWith('/')) return (suggestEl.hidden = true);
    const found = cycle ? cycle.list : matches(text);
    const typing = !cycle && text.includes(' ') ? text.split(' ').length - 2 : -1;

    suggestEl.replaceChildren(
        ...found.map((s, i) => {
            const li = el('li', cycle && cycle.i === i ? 'sel' : '');
            const line = el('div', 'line');
            line.append(el('b', '', s.name));
            s.params.forEach((p, n) => line.append(el('span', n === typing ? 'param on' : 'param', p.name)));
            li.append(line);
            const help = typing >= 0 && s.params[typing] && s.params[typing].help ? s.params[typing].help : s.help;
            if (help) li.append(el('small', '', help));
            return li;
        }),
    );
    suggestEl.hidden = !found.length;
}

function complete(step) {
    if (!cycle) {
        if (!input.value.startsWith('/') || input.value.includes(' ')) return false;
        const found = matches(input.value);
        if (!found.length) return false;
        cycle = { base: input.value, list: found, i: -1 };
    }
    const n = cycle.list.length;
    cycle.i = (cycle.i + step + n) % n;
    input.value = `${cycle.list[cycle.i].name} `;
    drawSuggest();
    return true;
}

// ----------------------------------------------------------------- input

let history = [];
try {
    history = JSON.parse(localStorage.getItem('fivechat:history')) || [];
} catch {}
let back = -1;
let draft = '';

function remember(text) {
    if (history[history.length - 1] !== text) history.push(text);
    history = history.slice(-50);
    try {
        localStorage.setItem('fivechat:history', JSON.stringify(history));
    } catch {}
}

function recall(step) {
    if (!history.length) return;
    if (back === -1) draft = input.value;
    back = Math.max(-1, Math.min(history.length - 1, back + step));
    input.value = back === -1 ? draft : history[history.length - 1 - back];
    input.setSelectionRange(input.value.length, input.value.length);
    cycle = null;
    drawSuggest();
    drawCount();
}

function drawCount() {
    const left = cfg.maxLength - input.value.length;
    $('count').textContent = left < cfg.maxLength * 0.2 ? left : '';
    $('count').classList.toggle('over', left < 0);
}

function setOpen(state) {
    open = state;
    chat.classList.toggle('open', state);
    if (state) {
        clearTimeout(fadeTimer);
        chat.classList.remove('faded');
        drawTabs();
        input.value = '';
        back = -1;
        cycle = null;
        drawCount();
        drawSuggest();
        feed.scrollTop = feed.scrollHeight;
        setTimeout(() => input.focus(), 0);
    } else {
        input.blur();
        suggestEl.hidden = true;
        feed.scrollTop = feed.scrollHeight;
        wake();
    }
}

input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        const text = input.value.trim();
        if (text) remember(text);
        setOpen(false);
        post('send', { text, mode: sendMode() });
    } else if (e.key === 'Escape') {
        e.preventDefault();
        setOpen(false);
        post('close');
    } else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        recall(e.key === 'ArrowUp' ? 1 : -1);
    } else if (e.key === 'Tab') {
        e.preventDefault();
        complete(e.shiftKey ? -1 : 1);
    } else if (e.key === 'ArrowRight' && input.selectionStart === input.value.length && !cycle) {
        if (complete(1)) e.preventDefault();
    } else if (e.key === 'PageUp' || e.key === 'PageDown') {
        e.preventDefault();
        feed.scrollBy(0, (e.key === 'PageUp' ? -1 : 1) * feed.clientHeight * 0.8);
    }
});

input.addEventListener('input', () => {
    cycle = null;
    back = -1;
    drawSuggest();
    drawCount();
});

// keep typing even after clicking somewhere in the chat
document.addEventListener('mouseup', () => open && input.focus());

// ------------------------------------------------------------- from Lua

const actions = {
    config(d) {
        cfg = { ...cfg, ...d };
        input.maxLength = cfg.maxLength + 64;
        drawTabs();
    },
    open: () => setOpen(true),
    close: () => setOpen(false),
    message: (d) => add(d.message),
    suggestion: (d) => addSuggestion(d.suggestion),
    suggestions: (d) => list(d.list).forEach(addSuggestion),
    removeSuggestion(d) {
        if (typeof d.name === 'string') suggestions.delete((d.name.startsWith('/') ? d.name : `/${d.name}`).toLowerCase());
    },
    template(d) {
        if (typeof d.id === 'string' && typeof d.html === 'string') templates[d.id] = d.html;
    },
    clear() {
        rows.replaceChildren();
        for (const t of Object.values(tabs)) t.dot.className = 'dot';
    },
    state(d) {
        const s = d.state || {};
        me = { id: s.id, names: list(s.names).filter((n) => typeof n === 'string'), ownStaff: s.ownStaff !== false, emergency: !!s.emergency };
        tabs.staff.hidden = !s.staff;
        tabs.call.hidden = !s.emergency;
        if (tabs[active].hidden) setTab('all');
        drawTabs();
    },
    hidden: (d) => document.body.classList.toggle('hidden', !!d.value),
};

window.addEventListener('message', (e) => {
    const d = e.data;
    if (d && typeof d === 'object' && actions[d.action]) actions[d.action](d);
});

drawTabs();
post('loaded');
