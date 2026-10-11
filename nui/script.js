const isGame = !!window.invokeNative || window.location.protocol === 'nui:';
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Neon-Banking';

const NEON_SECRET = 'nB8-neon$bank-3zK9x!auth';
let neonAuthorized = !isGame;
let neonPending = [];

function neonHash(str) {
    let h = 5381;
    for (let i = 0; i < str.length; i++) {
        h = (h * 33 + str.charCodeAt(i)) % 4294967296;
    }
    return h;
}

function neonRequestAuth() {
    if (!isGame) return;
    fetch(`https://${resourceName}/neonAuth`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: '{}',
    }).catch(() => {});
}

const $ = (id) => document.getElementById(id);

const ICONS = {
    overview: '<path d="M4 11l8-7 8 7"/><path d="M6 10v9h12v-9"/><path d="M10 19v-5h4v5"/>',
    deposit: '<path d="M12 4v11"/><path d="M7 11l5 5 5-5"/><path d="M5 20h14"/>',
    withdraw: '<path d="M12 16V5"/><path d="M7 9l5-5 5 5"/><path d="M5 20h14"/>',
    transfer: '<path d="M4 12h14"/><path d="M13 6l6 6-6 6"/>',
    history: '<path d="M8 6h12"/><path d="M8 12h12"/><path d="M8 18h12"/><path d="M4 6h.01"/><path d="M4 12h.01"/><path d="M4 18h.01"/>',
    savings: '<rect x="3.5" y="5" width="17" height="14" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M12 9V8"/><path d="M12 16v-1"/><path d="M7 19v2"/><path d="M17 19v2"/>',
    percent: '<path d="M6 18L18 6"/><circle cx="7.5" cy="7.5" r="2"/><circle cx="16.5" cy="16.5" r="2"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    trash: '<path d="M5 7h14"/><path d="M9 7V5h6v2"/><path d="M7 7l1 12h8l1-12"/>',
    back: '<path d="M9 6h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5-6z"/><path d="M12 10l4 4"/><path d="M16 10l-4 4"/>',
    swap: '<path d="M5 8h13"/><path d="M15 5l3 3-3 3"/><path d="M19 16H6"/><path d="M9 13l-3 3 3 3"/>',
    dot: '<circle cx="12" cy="12" r="3"/>',
    cash: '<rect x="3" y="7" width="18" height="10" rx="1.5"/><circle cx="12" cy="12" r="2.5"/><path d="M6.5 10v4"/><path d="M17.5 10v4"/>',
    up: '<path d="M6 15l6-6 6 6"/>',
    down: '<path d="M6 9l6 6 6-6"/>',
    wave: '<path d="M8.5 16a6 6 0 0 0 0-8"/><path d="M12 18.5a10 10 0 0 0 0-13"/><path d="M15.5 21a14 14 0 0 0 0-18"/>',
};

const TABS = {
    overview: { label: 'Genel Bakış', kicker: 'Hesap özeti' },
    deposit: { label: 'Para Yatır', kicker: 'Nakitten hesaba' },
    withdraw: { label: 'Para Çek', kicker: 'Hesaptan nakite' },
    transfer: { label: 'Transfer', kicker: 'Başka oyuncuya gönder' },
    history: { label: 'Geçmiş', kicker: 'Hesap hareketleri' },
    savings: { label: 'Birikim', kicker: 'Birikim hesabı' },
};

const TX = {
    deposit: { label: 'Para yatırma', dir: 1, icon: 'deposit' },
    withdrawal: { label: 'Para çekme', dir: -1, icon: 'withdraw' },
    transfer_in: { label: 'Gelen transfer', dir: 1, icon: 'deposit' },
    transfer_out: { label: 'Giden transfer', dir: -1, icon: 'transfer' },
    fee: { label: 'Transfer komisyonu', dir: -1, icon: 'percent' },
    savings_deposit: { label: 'Birikime aktarım', dir: -1, icon: 'savings' },
    savings_withdrawal: { label: 'Birikimden aktarım', dir: 1, icon: 'savings' },
    savings_opened: { label: 'Birikim hesabı açıldı', dir: 0, icon: 'savings' },
    savings_closed: { label: 'Birikim hesabı kapatıldı', dir: 0, icon: 'savings' },
    account_transfer: { label: 'Hesaplar arası aktarım', dir: 0, icon: 'swap' },
    admin_deposit: { label: 'Hesaba eklenen tutar', dir: 1, icon: 'deposit' },
    admin_withdrawal: { label: 'Hesaptan alınan tutar', dir: -1, icon: 'withdraw' },
    admin_transfer_in: { label: 'Gelen aktarım', dir: 1, icon: 'deposit' },
    admin_transfer_out: { label: 'Giden aktarım', dir: -1, icon: 'transfer' },
    admin_cash_grant: { label: 'Nakit eklendi', dir: 0, icon: 'cash' },
    admin_cash_removal: { label: 'Nakit alındı', dir: 0, icon: 'cash' },
    admin_savings_deposit: { label: 'Birikime eklenen tutar', dir: 0, icon: 'savings' },
};

const state = {
    mode: 'bank',
    tab: 'overview',
    data: null,
    settings: {},
    pending: false,
    historyFilter: 'all',
    historySearch: '',
    savingsDir: 'in',
    pin: null,
    shown: { bank: 0, cash: 0 },
    armed: null,
    armedTimer: null,
};

function icon(name) {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ICONS.dot}</svg>`;
}

function esc(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function money(value) {
    const number = Math.floor(Number(value) || 0);
    const sign = number < 0 ? '-' : '';
    return sign + (state.settings.currency || '$') + Math.abs(number).toLocaleString('tr-TR');
}

function post(endpoint, body) {
    if (!isGame) {
        return demoPost(endpoint, body || {});
    }
    return fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
    }).then((resp) => resp.json()).catch(() => null);
}

function toast(message, type) {
    if (!message) return;
    const box = $('toasts');
    const item = document.createElement('div');
    item.className = `toast toast-${type || 'info'}`;
    item.textContent = message;
    box.appendChild(item);
    while (box.children.length > 3) {
        box.removeChild(box.firstChild);
    }
    setTimeout(() => {
        item.classList.add('is-leaving');
        setTimeout(() => item.remove(), 260);
    }, 3400);
}

function animateValue(el, key, target) {
    const from = state.shown[key] || 0;
    state.shown[key] = target;
    if (from === target) {
        el.textContent = money(target);
        return;
    }
    const start = performance.now();
    const step = (now) => {
        const progress = Math.min(1, (now - start) / 500);
        const eased = 1 - Math.pow(1 - progress, 3);
        el.textContent = money(from + (target - from) * eased);
        if (progress < 1 && state.shown[key] === target) {
            requestAnimationFrame(step);
        }
    };
    requestAnimationFrame(step);
}

function tabList() {
    if (state.mode === 'atm') {
        return ['withdraw', 'deposit', 'transfer', 'history'];
    }
    const tabs = ['overview', 'deposit', 'withdraw', 'transfer', 'history'];
    if (state.data && state.data.savings && state.data.savings.enabled) {
        tabs.push('savings');
    }
    return tabs;
}

function renderNav() {
    $('nav').innerHTML = tabList().map((tab) => `
        <button class="nav-item${tab === state.tab ? ' is-active' : ''}" type="button" data-tab="${tab}">
            ${icon(tab)}
            <span>${TABS[tab].label}</span>
        </button>`).join('');
}

function updateHeader() {
    const data = state.data;
    if (!data) return;
    $('bankName').textContent = state.settings.bankName || 'Banka';
    $('brandKicker').textContent = state.mode === 'atm' ? 'ATM' : 'Şube';
    $('viewKicker').textContent = TABS[state.tab].kicker;
    $('viewTitle').textContent = TABS[state.tab].label;
    $('pinBtn').hidden = state.mode === 'atm';
    $('pinBtnLabel').textContent = data.hasPin ? 'PIN değiştir' : 'PIN oluştur';
    animateValue($('bankValue'), 'bank', data.bank);
    animateValue($('cashValue'), 'cash', data.cash);
}

function formatDate(ts) {
    const date = new Date((Number(ts) || 0) * 1000);
    if (isNaN(date.getTime()) || !ts) return '';
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function txMeta(tx) {
    return TX[tx.type] || { label: tx.type, dir: 0, icon: 'dot' };
}

function txRow(tx) {
    const meta = txMeta(tx);
    const amount = Math.abs(Number(tx.amount) || 0);
    const tone = meta.dir > 0 ? 'in' : meta.dir < 0 ? 'out' : 'flat';
    const sign = meta.dir > 0 ? '+' : meta.dir < 0 ? '-' : '';
    const detail = [tx.description, formatDate(tx.ts)].filter(Boolean).map(esc).join(' · ');
    return `
        <li class="tx tx-${tone}">
            <span class="tx-icon">${icon(meta.icon)}</span>
            <div class="tx-text">
                <b>${esc(meta.label)}</b>
                <span>${detail}</span>
            </div>
            <b class="tx-amount">${amount > 0 ? sign + money(amount) : ''}</b>
        </li>`;
}

function emptyState(title, hint) {
    return `
        <div class="empty">
            ${icon('history')}
            <b>${esc(title)}</b>
            <span>${esc(hint)}</span>
        </div>`;
}

function dayLabel(day, isLast) {
    if (isLast) return 'Bugün';
    const parts = String(day).split('-').map(Number);
    const date = new Date(parts[0], (parts[1] || 1) - 1, parts[2] || 1);
    return date.toLocaleDateString('tr-TR', { weekday: 'short' });
}

function chart(history) {
    const points = history && history.length ? history : [{ day: '', balance: 0 }];
    const width = 720;
    const height = 230;
    const left = 28;
    const right = 28;
    const top = 40;
    const bottom = 38;
    const values = points.map((p) => Number(p.balance) || 0);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const span = max - min;
    const stepX = points.length > 1 ? (width - left - right) / (points.length - 1) : 0;
    const coords = values.map((value, i) => ({
        x: left + stepX * i,
        y: span === 0 ? top + (height - top - bottom) / 2 : top + (1 - (value - min) / span) * (height - top - bottom),
    }));

    let line = `M${coords[0].x},${coords[0].y}`;
    for (let i = 1; i < coords.length; i++) {
        const midX = (coords[i - 1].x + coords[i].x) / 2;
        line += ` C${midX},${coords[i - 1].y} ${midX},${coords[i].y} ${coords[i].x},${coords[i].y}`;
    }
    const floor = height - bottom;
    const area = `${line} L${coords[coords.length - 1].x},${floor} L${coords[0].x},${floor} Z`;

    const columns = coords.map((point, i) => {
        const last = i === coords.length - 1;
        const anchor = i === 0 ? 'start' : last ? 'end' : 'middle';
        const hitX = point.x - (stepX || width) / 2;
        return `
            <g class="chart-col${last ? ' is-last' : ''}">
                <rect x="${hitX}" y="0" width="${stepX || width}" height="${height}" fill="transparent"/>
                <line x1="${point.x}" y1="${top - 8}" x2="${point.x}" y2="${floor}"/>
                <circle cx="${point.x}" cy="${point.y}" r="4.5"/>
                <text class="chart-tip" x="${point.x}" y="${point.y - 14}" text-anchor="${anchor}">${esc(money(values[i]))}</text>
                <text class="chart-day" x="${point.x}" y="${height - 12}" text-anchor="${anchor}">${esc(dayLabel(points[i].day, last))}</text>
            </g>`;
    }).join('');

    return `
        <svg class="chart" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
            <defs>
                <linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stop-color="#5cc8ff" stop-opacity="0.38"/>
                    <stop offset="1" stop-color="#5cc8ff" stop-opacity="0"/>
                </linearGradient>
            </defs>
            <g class="chart-plot">
                <path class="chart-area" d="${area}" fill="url(#chartFill)"/>
                <path class="chart-line" d="${line}"/>
            </g>
            ${columns}
        </svg>`;
}

function viewOverview() {
    const data = state.data;
    const week = data.week || { income: 0, expense: 0 };
    const recent = (data.transactions || []).slice(0, 5);
    const savingsTile = data.savings.enabled ? `
        <div class="tile">
            <span class="tile-icon">${icon('savings')}</span>
            <div><span>Birikim</span><b>${data.savings.active ? money(data.savings.balance) : 'Hesap yok'}</b></div>
        </div>` : '';

    return `
        <div class="overview">
            <div class="card">
                <div class="card-glow"></div>
                <div class="card-top">
                    <b>${esc(state.settings.bankName || 'Banka')}</b>
                    <span class="card-wave">${icon('wave')}</span>
                </div>
                <div class="card-chip"><i></i><i></i><i></i></div>
                <div class="card-number"><span>••••</span><span>••••</span><span>••••</span><span>${esc(data.card)}</span></div>
                <div class="card-bottom">
                    <div><span>Kart sahibi</span><b>${esc(data.name)}</b></div>
                    <div><span>Tür</span><b>Vadesiz</b></div>
                </div>
            </div>

            <section class="panel chart-panel">
                <div class="panel-head">
                    <h3>Son 7 gün</h3>
                    <div class="legend">
                        <span class="legend-in">${icon('up')}${money(week.income)}</span>
                        <span class="legend-out">${icon('down')}${money(week.expense)}</span>
                    </div>
                </div>
                ${chart(data.history)}
            </section>

            <div class="tiles">
                <div class="tile">
                    <span class="tile-icon">${icon('cash')}</span>
                    <div><span>Üzerindeki nakit</span><b>${money(data.cash)}</b></div>
                </div>
                <div class="tile tile-in">
                    <span class="tile-icon">${icon('deposit')}</span>
                    <div><span>7 günlük giriş</span><b>${money(week.income)}</b></div>
                </div>
                <div class="tile tile-out">
                    <span class="tile-icon">${icon('withdraw')}</span>
                    <div><span>7 günlük çıkış</span><b>${money(week.expense)}</b></div>
                </div>
                ${savingsTile}
            </div>

            <section class="panel recent">
                <div class="panel-head">
                    <h3>Son işlemler</h3>
                    <button class="link" type="button" data-tab="history">Tümünü gör</button>
                </div>
                ${recent.length ? `<ul class="tx-list">${recent.map(txRow).join('')}</ul>` : emptyState('Henüz işlem yok', 'İlk işlemin burada görünecek.')}
            </section>
        </div>`;
}

function chips(max) {
    const amounts = (state.settings.quickAmounts || []).map((amount) => Math.floor(Number(amount) || 0)).filter((amount) => amount > 0);
    return `
        <div class="chips">
            ${amounts.map((amount) => `<button class="chip" type="button" data-chip="${amount}">${money(amount)}</button>`).join('')}
            <button class="chip chip-all" type="button" data-chip="${Math.max(0, Math.floor(max))}">Tümü</button>
        </div>`;
}

function flowView(options) {
    return `
        <div class="split">
            <section class="panel form">
                <h3>${esc(options.title)}</h3>
                <label class="amount">
                    <span>${esc(state.settings.currency || '$')}</span>
                    <input id="amountInput" type="text" inputmode="numeric" autocomplete="off" placeholder="0" data-amount>
                </label>
                ${chips(Math.min(options.from.value, state.settings.maxAmount || options.from.value))}
                <p class="note">${esc(options.from.label)}: <b>${money(options.from.value)}</b></p>
                <button class="primary" type="button" data-act="${options.action}">
                    ${icon(options.icon)}
                    <span>${esc(options.button)}</span>
                </button>
                ${options.extra || ''}
            </section>

            <section class="panel preview" data-from="${options.from.value}" data-to="${options.to.value}">
                <h3>İşlem sonrası</h3>
                <div class="flow">
                    <div class="flow-box">
                        <span>${esc(options.from.label)}</span>
                        <b id="flowFrom">${money(options.from.value)}</b>
                        <em id="flowFromDelta"></em>
                    </div>
                    <div class="flow-arrow">${icon('transfer')}</div>
                    <div class="flow-box">
                        <span>${esc(options.to.label)}</span>
                        <b id="flowTo">${money(options.to.value)}</b>
                        <em id="flowToDelta"></em>
                    </div>
                </div>
                <p class="note">${esc(options.hint)}</p>
            </section>
        </div>`;
}

function viewDeposit() {
    return flowView({
        title: 'Yatırılacak tutar',
        button: 'Para Yatır',
        action: 'deposit',
        icon: 'deposit',
        from: { label: 'Nakit', value: state.data.cash },
        to: { label: 'Banka', value: state.data.bank },
        hint: 'Üzerindeki nakit banka hesabına aktarılır.',
    });
}

function viewWithdraw() {
    return flowView({
        title: 'Çekilecek tutar',
        button: 'Para Çek',
        action: 'withdraw',
        icon: 'withdraw',
        from: { label: 'Banka', value: state.data.bank },
        to: { label: 'Nakit', value: state.data.cash },
        hint: 'Çektiğin tutar nakit olarak üzerine geçer.',
    });
}

function viewTransfer() {
    const fee = Number(state.settings.fee) || 0;
    return `
        <div class="split">
            <section class="panel form">
                <h3>Alıcı</h3>
                <label class="field">
                    <span>Oyuncu ID</span>
                    <input id="targetInput" type="text" inputmode="numeric" autocomplete="off" maxlength="6" placeholder="Örn. 12" data-digits>
                </label>
                <label class="amount">
                    <span>${esc(state.settings.currency || '$')}</span>
                    <input id="amountInput" type="text" inputmode="numeric" autocomplete="off" placeholder="0" data-amount>
                </label>
                <label class="field">
                    <span>Açıklama</span>
                    <input id="noteInput" type="text" autocomplete="off" maxlength="60" placeholder="İsteğe bağlı">
                </label>
                <button class="primary" type="button" data-act="transfer">
                    ${icon('transfer')}
                    <span>Gönder</span>
                </button>
            </section>

            <section class="panel preview" data-from="${state.data.bank}" data-fee="${fee}">
                <h3>Özet</h3>
                <dl class="summary">
                    <div><dt>Tutar</dt><dd id="sumAmount">${money(0)}</dd></div>
                    <div><dt>Komisyon${fee > 0 ? ` (%${fee})` : ''}</dt><dd id="sumFee">${money(0)}</dd></div>
                    <div class="summary-total"><dt>Hesaptan çıkacak</dt><dd id="sumTotal">${money(0)}</dd></div>
                    <div><dt>Kalan bakiye</dt><dd id="sumLeft">${money(state.data.bank)}</dd></div>
                </dl>
                <p class="note">Para yalnızca şu an oyunda olan oyunculara gönderilebilir.</p>
            </section>
        </div>`;
}

function filteredTransactions() {
    const term = state.historySearch;
    return (state.data.transactions || []).filter((tx) => {
        const meta = txMeta(tx);
        if (state.historyFilter === 'in' && meta.dir <= 0) return false;
        if (state.historyFilter === 'out' && meta.dir >= 0) return false;
        if (!term) return true;
        return `${meta.label} ${tx.description || ''}`.toLocaleLowerCase('tr-TR').includes(term);
    });
}

function renderHistoryList() {
    const list = $('historyList');
    if (!list) return;
    const items = filteredTransactions();
    list.innerHTML = items.length
        ? `<ul class="tx-list">${items.map(txRow).join('')}</ul>`
        : (state.data.transactions || []).length
            ? emptyState('İşlem bulunamadı', 'Aramana ya da filtrene uyan kayıt yok.')
            : emptyState('Henüz işlem yok', 'Hesap hareketlerin burada listelenecek.');
}

function viewHistory() {
    const filters = [['all', 'Tümü'], ['in', 'Gelen'], ['out', 'Giden']];
    const canClear = state.mode !== 'atm' && (state.data.transactions || []).length > 0;
    return `
        <section class="panel history">
            <div class="toolbar">
                <label class="search">
                    ${icon('search')}
                    <input id="historySearch" type="text" autocomplete="off" placeholder="İşlem ara" value="${esc(state.historySearch)}">
                </label>
                <div class="segment">
                    ${filters.map(([key, label]) => `<button type="button" class="segment-item${state.historyFilter === key ? ' is-active' : ''}" data-filter="${key}">${label}</button>`).join('')}
                </div>
                ${canClear ? `<button class="ghost ghost-danger" type="button" data-confirm="clearHistory" data-label="Geçmişi temizle">${icon('trash')}<span>Geçmişi temizle</span></button>` : ''}
            </div>
            <div class="history-list" id="historyList"></div>
        </section>`;
}

function viewSavings() {
    const savings = state.data.savings;
    if (!savings.active) {
        return `
            <section class="panel savings-empty">
                <span class="savings-mark">${icon('savings')}</span>
                <h3>Birikim hesabın yok</h3>
                <p>Paranı vadesiz hesabından ayırıp güvende tutmak için bir birikim hesabı aç.</p>
                <button class="primary" type="button" data-act="savingsOpen">
                    ${icon('savings')}
                    <span>Birikim Hesabı Aç</span>
                </button>
            </section>`;
    }

    const toSavings = state.savingsDir === 'in';
    const toggle = `
        <div class="segment segment-wide">
            <button type="button" class="segment-item${toSavings ? ' is-active' : ''}" data-dir="in">Vadesiz → Birikim</button>
            <button type="button" class="segment-item${toSavings ? '' : ' is-active'}" data-dir="out">Birikim → Vadesiz</button>
        </div>`;
    const extra = `<button class="ghost ghost-danger close-savings" type="button" data-confirm="savingsClose" data-label="Birikim hesabını kapat">${icon('trash')}<span>Birikim hesabını kapat</span></button>`;

    return toggle + flowView({
        title: 'Aktarılacak tutar',
        button: 'Aktar',
        action: toSavings ? 'savingsDeposit' : 'savingsWithdraw',
        icon: 'swap',
        from: toSavings ? { label: 'Vadesiz', value: state.data.bank } : { label: 'Birikim', value: savings.balance },
        to: toSavings ? { label: 'Birikim', value: savings.balance } : { label: 'Vadesiz', value: state.data.bank },
        hint: 'Hesabı kapatırsan içindeki tutar vadesiz hesabına geçer.',
        extra: extra,
    });
}

const VIEWS = {
    overview: viewOverview,
    deposit: viewDeposit,
    withdraw: viewWithdraw,
    transfer: viewTransfer,
    history: viewHistory,
    savings: viewSavings,
};

function render() {
    if (!state.data) return;
    if (!tabList().includes(state.tab)) {
        state.tab = tabList()[0];
    }
    disarm();
    renderNav();
    updateHeader();
    const view = $('view');
    view.className = `view view-${state.tab}`;
    view.innerHTML = VIEWS[state.tab]();
    view.classList.remove('is-entering');
    void view.offsetWidth;
    view.classList.add('is-entering');
    renderHistoryList();
    updatePreview();
    const first = view.querySelector('input');
    if (first && state.tab !== 'history') {
        first.focus();
    }
}

function readAmount() {
    const input = $('amountInput');
    if (!input) return 0;
    return parseInt(input.value.replace(/\D/g, ''), 10) || 0;
}

function setDelta(el, delta, invalid) {
    if (!el) return;
    if (!delta) {
        el.textContent = '';
        el.className = '';
        return;
    }
    el.textContent = invalid ? 'Yetersiz' : (delta > 0 ? '+' : '-') + money(Math.abs(delta));
    el.className = invalid ? 'is-bad' : delta > 0 ? 'is-up' : 'is-down';
}

function updatePreview() {
    const preview = document.querySelector('.preview');
    if (!preview) return;
    const amount = readAmount();
    const from = Number(preview.dataset.from) || 0;

    if (state.tab === 'transfer') {
        const fee = Math.floor(amount * (Number(preview.dataset.fee) || 0) / 100);
        const total = amount + fee;
        $('sumAmount').textContent = money(amount);
        $('sumFee').textContent = money(fee);
        $('sumTotal').textContent = money(total);
        const left = $('sumLeft');
        left.textContent = total > from ? 'Yetersiz' : money(from - total);
        left.classList.toggle('is-bad', total > from);
        return;
    }

    const to = Number(preview.dataset.to) || 0;
    const invalid = amount > from;
    $('flowFrom').textContent = money(invalid ? from : from - amount);
    $('flowTo').textContent = money(invalid ? to : to + amount);
    setDelta($('flowFromDelta'), -amount, invalid);
    setDelta($('flowToDelta'), invalid ? 0 : amount, false);
}

function disarm() {
    clearTimeout(state.armedTimer);
    if (state.armed && state.armed.isConnected) {
        state.armed.classList.remove('is-armed');
        state.armed.querySelector('span').textContent = state.armed.dataset.label;
    }
    state.armed = null;
}

function act(name, payload) {
    if (state.pending) return Promise.resolve(null);
    state.pending = true;
    $('view').classList.add('is-busy');
    return post('action', { name: name, payload: payload || {} }).then((result) => {
        state.pending = false;
        $('view').classList.remove('is-busy');
        if (!result) {
            toast('Sunucu yanıt vermedi', 'error');
            return null;
        }
        if (result.closed) {
            toast(result.message, 'error');
            hideAll();
            post('close');
            return result;
        }
        if (result.data) {
            state.data = result.data;
        }
        toast(result.message, result.ok ? 'success' : 'error');
        if (result.ok) {
            render();
        } else {
            updateHeader();
        }
        return result;
    });
}

function submit(action) {
    const amount = readAmount();
    if (action === 'savingsOpen') {
        return act('savingsOpen');
    }
    if (amount < 1) {
        toast('Bir tutar gir', 'error');
        return null;
    }
    if (action === 'transfer') {
        const target = parseInt($('targetInput').value, 10);
        if (!target || target < 1) {
            toast('Geçerli bir oyuncu ID gir', 'error');
            return null;
        }
        return act('transfer', { target: target, amount: amount, description: $('noteInput').value.trim() });
    }
    return act(action, { amount: amount });
}

function openBank(message) {
    state.mode = message.mode === 'atm' ? 'atm' : 'bank';
    state.data = message.data;
    state.settings = message.settings || {};
    state.tab = state.mode === 'atm' ? 'withdraw' : 'overview';
    state.historyFilter = 'all';
    state.historySearch = '';
    state.savingsDir = 'in';
    state.pending = false;
    state.shown = { bank: 0, cash: 0 };
    closePin();
    $('app').hidden = false;
    $('shell').hidden = false;
    render();
}

function hideAll() {
    $('app').hidden = true;
    $('shell').hidden = true;
    $('pinLayer').hidden = true;
    state.pin = null;
    state.data = null;
    state.pending = false;
    disarm();
}

function closeAll() {
    hideAll();
    post('close');
}

function renderPin() {
    const pin = state.pin;
    if (!pin) return;
    const setup = pin.purpose === 'setup';
    $('pinKicker').textContent = setup ? 'Kart güvenliği' : (pin.bankName || 'ATM');
    $('pinTitle').textContent = setup ? (pin.step === 1 ? 'Yeni PIN belirle' : 'PIN\'i tekrar gir') : 'PIN kodunu gir';
    $('pinHint').textContent = pin.hint || (setup ? 'ATM\'lerde kullanacağın 4 haneli kod.' : 'Kartına ait 4 haneli kodu tuşla.');
    $('pinHint').classList.toggle('is-bad', !!pin.bad);
    Array.from($('pinDots').children).forEach((dot, i) => {
        dot.classList.toggle('is-filled', i < pin.value.length);
    });
}

function openPin(purpose, bankName) {
    state.pin = { purpose: purpose, step: 1, value: '', first: '', hint: '', bad: false, busy: false, bankName: bankName };
    $('app').hidden = false;
    $('pinLayer').hidden = false;
    $('pinLayer').classList.toggle('is-standalone', purpose === 'atm');
    renderPin();
}

function closePin() {
    state.pin = null;
    $('pinLayer').hidden = true;
}

function shakePin(hint) {
    const pin = state.pin;
    if (!pin) return;
    pin.value = '';
    pin.hint = hint;
    pin.bad = true;
    const dots = $('pinDots');
    dots.classList.remove('is-shaking');
    void dots.offsetWidth;
    dots.classList.add('is-shaking');
    renderPin();
}

function completePin() {
    const pin = state.pin;
    if (pin.purpose === 'atm') {
        pin.busy = true;
        post('verifyPin', { pin: pin.value }).then((result) => {
            if (!state.pin) return;
            state.pin.busy = false;
            if (result && result.ok) {
                openBank(result);
                return;
            }
            const message = (result && result.message) || 'PIN doğrulanamadı';
            if (result && result.closed) {
                toast(message, 'error');
                setTimeout(closeAll, 1200);
                closePin();
                return;
            }
            shakePin(message);
        });
        return;
    }

    if (pin.step === 1) {
        pin.first = pin.value;
        pin.value = '';
        pin.step = 2;
        pin.hint = '';
        pin.bad = false;
        renderPin();
        return;
    }

    if (pin.value !== pin.first) {
        pin.step = 1;
        pin.first = '';
        shakePin('Kodlar eşleşmedi, baştan dene.');
        return;
    }

    const value = pin.value;
    closePin();
    act('setPin', { pin: value });
}

function pressPin(key) {
    const pin = state.pin;
    if (!pin || pin.busy) return;
    if (key === 'back') {
        pin.value = pin.value.slice(0, -1);
    } else if (key === 'clear') {
        pin.value = '';
    } else if (pin.value.length < 4) {
        pin.value += key;
        pin.hint = pin.bad ? '' : pin.hint;
        pin.bad = false;
    }
    renderPin();
    if (pin.value.length === 4) {
        setTimeout(() => {
            if (state.pin === pin && pin.value.length === 4 && !pin.busy) {
                completePin();
            }
        }, 160);
    }
}

$('pinKeys').innerHTML = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'back'].map((key) => {
    if (key === 'clear') return '<button type="button" class="pin-key pin-key-alt" data-key="clear">C</button>';
    if (key === 'back') return `<button type="button" class="pin-key pin-key-alt" data-key="back">${icon('back')}</button>`;
    return `<button type="button" class="pin-key" data-key="${key}">${key}</button>`;
}).join('');

$('pinKeys').addEventListener('click', (e) => {
    const key = e.target.closest('[data-key]');
    if (key) pressPin(key.dataset.key);
});

$('pinCancel').addEventListener('click', () => {
    if (state.pin && state.pin.purpose === 'atm') {
        closeAll();
    } else {
        closePin();
    }
});

$('pinBtn').addEventListener('click', () => openPin('setup'));
$('closeBtn').addEventListener('click', closeAll);

$('nav').addEventListener('click', (e) => {
    const item = e.target.closest('[data-tab]');
    if (!item || state.pending) return;
    state.tab = item.dataset.tab;
    render();
});

$('view').addEventListener('click', (e) => {
    const target = e.target.closest('[data-tab],[data-chip],[data-act],[data-filter],[data-dir],[data-confirm]');
    if (!target || state.pending) return;

    if (target.dataset.tab) {
        state.tab = target.dataset.tab;
        render();
    } else if (target.dataset.chip !== undefined) {
        const input = $('amountInput');
        const value = parseInt(target.dataset.chip, 10) || 0;
        input.value = value > 0 ? value.toLocaleString('tr-TR') : '';
        updatePreview();
        input.focus();
    } else if (target.dataset.act) {
        submit(target.dataset.act);
    } else if (target.dataset.filter) {
        state.historyFilter = target.dataset.filter;
        document.querySelectorAll('[data-filter]').forEach((button) => {
            button.classList.toggle('is-active', button === target);
        });
        renderHistoryList();
    } else if (target.dataset.dir) {
        state.savingsDir = target.dataset.dir;
        render();
    } else if (target.dataset.confirm) {
        if (state.armed === target) {
            const action = target.dataset.confirm;
            disarm();
            act(action);
            return;
        }
        disarm();
        state.armed = target;
        target.classList.add('is-armed');
        target.querySelector('span').textContent = 'Emin misin?';
        state.armedTimer = setTimeout(disarm, 4000);
    }
});

$('view').addEventListener('input', (e) => {
    const input = e.target;
    if (input.dataset.amount !== undefined) {
        const digits = input.value.replace(/\D/g, '').slice(0, 10);
        input.value = digits ? parseInt(digits, 10).toLocaleString('tr-TR') : '';
        updatePreview();
    } else if (input.dataset.digits !== undefined) {
        input.value = input.value.replace(/\D/g, '');
    } else if (input.id === 'historySearch') {
        state.historySearch = input.value.trim().toLocaleLowerCase('tr-TR');
        renderHistoryList();
    }
});

document.addEventListener('keydown', (e) => {
    if ($('app').hidden) return;

    if (state.pin) {
        if (/^[0-9]$/.test(e.key)) {
            pressPin(e.key);
        } else if (e.key === 'Backspace') {
            pressPin('back');
        } else if (e.key === 'Escape') {
            if (state.pin.purpose === 'atm') {
                closeAll();
            } else {
                closePin();
            }
        }
        e.preventDefault();
        return;
    }

    if (e.key === 'Escape') {
        closeAll();
    } else if (e.key === 'Enter' && e.target.tagName === 'INPUT') {
        const button = $('view').querySelector('[data-act]');
        if (button && !state.pending) {
            submit(button.dataset.act);
        }
    }
});

window.addEventListener('message', (event) => {
    const message = event.data || {};

    if (message.type === 'neon:auth') {
        if (!neonAuthorized
            && typeof message.key === 'string'
            && typeof message.nonce === 'string'
            && typeof message.resource === 'string'
            && message.key === String(neonHash(NEON_SECRET + message.nonce + message.resource))) {
            neonAuthorized = true;
            const queued = neonPending;
            neonPending = [];
            queued.forEach((pending) => window.postMessage(pending, '*'));
        }
        return;
    }

    if (message.type === 'open' || message.type === 'pin') {
        if (!neonAuthorized) {
            if (neonPending.length < 20) neonPending.push(message);
            neonRequestAuth();
            return;
        }
    }

    if (message.type === 'open') {
        openBank(message);
    } else if (message.type === 'pin') {
        hideAll();
        openPin('atm', message.bankName);
    } else if (message.type === 'close') {
        hideAll();
    }
});

neonRequestAuth();

const demo = {
    pin: '1234',
    data: null,
    settings: { bankName: 'Fleeca Bank', currency: '$', fee: 2, minTransfer: 1, maxAmount: 1000000, quickAmounts: [500, 1000, 5000, 10000], historyEnabled: true },
};

function demoSnapshot() {
    return JSON.parse(JSON.stringify(demo.data));
}

function demoLog(type, amount, description) {
    demo.data.transactions.unshift({ id: Date.now(), type: type, amount: amount, description: description || '', ts: Math.floor(Date.now() / 1000) });
    demo.data.history[demo.data.history.length - 1].balance = demo.data.bank;
}

function demoAction(name, payload) {
    const data = demo.data;
    const amount = Math.floor(Number(payload.amount) || 0);
    const fail = (message) => ({ ok: false, message: message, data: demoSnapshot() });
    const done = (message) => ({ ok: true, message: message, data: demoSnapshot() });

    if (name === 'deposit') {
        if (amount > data.cash) return fail('Üzerinde yeterli nakit yok');
        data.cash -= amount;
        data.bank += amount;
        demoLog('deposit', amount);
        return done(`${money(amount)} hesabına yatırıldı`);
    }
    if (name === 'withdraw') {
        if (amount > data.bank) return fail('Banka bakiyen yetersiz');
        data.bank -= amount;
        data.cash += amount;
        demoLog('withdrawal', amount);
        return done(`${money(amount)} hesabından çekildi`);
    }
    if (name === 'transfer') {
        const fee = Math.floor(amount * demo.settings.fee / 100);
        if (amount + fee > data.bank) return fail('Bakiyen komisyon dahil yetersiz');
        data.bank -= amount + fee;
        demoLog('transfer_out', amount, `Oyuncu ${payload.target}${payload.description ? ' · ' + payload.description : ''}`);
        if (fee > 0) demoLog('fee', fee);
        return done(`Oyuncu ${payload.target} gönderildi: ${money(amount)}`);
    }
    if (name === 'savingsOpen') {
        data.savings.active = true;
        return done('Birikim hesabın açıldı');
    }
    if (name === 'savingsDeposit') {
        if (amount > data.bank) return fail('Banka bakiyen yetersiz');
        data.bank -= amount;
        data.savings.balance += amount;
        demoLog('savings_deposit', amount);
        return done(`${money(amount)} birikime aktarıldı`);
    }
    if (name === 'savingsWithdraw') {
        if (amount > data.savings.balance) return fail('Birikim bakiyen yetersiz');
        data.savings.balance -= amount;
        data.bank += amount;
        demoLog('savings_withdrawal', amount);
        return done(`${money(amount)} vadesiz hesaba aktarıldı`);
    }
    if (name === 'savingsClose') {
        data.bank += data.savings.balance;
        data.savings.balance = 0;
        data.savings.active = false;
        return done('Birikim hesabın kapatıldı');
    }
    if (name === 'setPin') {
        demo.pin = payload.pin;
        data.hasPin = true;
        return done('PIN kaydedildi');
    }
    if (name === 'clearHistory') {
        data.transactions = [];
        return done('İşlem geçmişi temizlendi');
    }
    return fail('Bu işlem burada yapılamaz');
}

function demoPost(endpoint, body) {
    return new Promise((resolve) => {
        setTimeout(() => {
            if (endpoint === 'action') {
                resolve(demoAction(body.name, body.payload || {}));
            } else if (endpoint === 'verifyPin') {
                resolve(body.pin === demo.pin
                    ? { ok: true, mode: 'atm', data: demoSnapshot(), settings: demo.settings }
                    : { ok: false, message: 'PIN hatalı, kalan deneme: 4' });
            } else {
                resolve({});
            }
        }, 120);
    });
}

if (!isGame) {
    const now = Math.floor(Date.now() / 1000);
    const day = 86400;
    const dayString = (offset) => {
        const date = new Date((now - offset * day) * 1000);
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    };
    demo.data = {
        name: 'Berat Yıldız',
        bank: 284750,
        cash: 12400,
        card: '4821',
        hasPin: true,
        savings: { enabled: true, active: true, balance: 150000 },
        week: { income: 96500, expense: 41750 },
        history: [231000, 238500, 226000, 251400, 247900, 268200, 284750].map((balance, i) => ({ day: dayString(6 - i), balance: balance })),
        transactions: [
            { id: 9, type: 'deposit', amount: 18000, description: '', ts: now - 1800 },
            { id: 8, type: 'transfer_in', amount: 25000, description: 'Arda Kaya · araç satışı', ts: now - 7200 },
            { id: 7, type: 'withdrawal', amount: 5000, description: '', ts: now - day },
            { id: 6, type: 'transfer_out', amount: 12500, description: 'Mert Demir · kira', ts: now - day - 4000 },
            { id: 5, type: 'fee', amount: 250, description: 'Mert Demir', ts: now - day - 4000 },
            { id: 4, type: 'savings_deposit', amount: 20000, description: '', ts: now - 2 * day },
            { id: 3, type: 'deposit', amount: 32000, description: '', ts: now - 3 * day },
            { id: 2, type: 'withdrawal', amount: 4000, description: '', ts: now - 4 * day },
            { id: 1, type: 'transfer_in', amount: 21500, description: 'Selin Aksoy · borç', ts: now - 5 * day },
        ],
    };

    const params = new URLSearchParams(window.location.search);
    if (params.has('atm')) {
        openPin('atm', demo.settings.bankName);
    } else {
        openBank({ mode: 'bank', data: demoSnapshot(), settings: demo.settings });
        if (params.get('tab') && VIEWS[params.get('tab')]) {
            state.tab = params.get('tab');
            render();
        }
        if (params.has('pin')) {
            openPin('setup');
        }
    }
}
