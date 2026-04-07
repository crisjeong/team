/* ═══════════════════════════════════════════════════════════════
   JPRM — Dashboard JavaScript (WebSocket + Chart.js)
   ═══════════════════════════════════════════════════════════════ */

// ── State ──────────────────────────────────────────────────────
const state = {
    processes: {},          // id → ProcessInfo
    selectedProcessId: null,
    ws: null,
    charts: {},
    alerts: [],
    maxChartPoints: 120     // 2분 분량 (1초 간격)
};

// ── Formatters ─────────────────────────────────────────────────
function formatBytes(bytes) {
    if (bytes < 0) return 'N/A';
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}

function formatMB(bytes) {
    if (bytes < 0) return '--';
    return (bytes / (1024 * 1024)).toFixed(0);
}

function formatCpu(pct) {
    if (pct < 0) return '--';
    return pct.toFixed(1);
}

function formatTime(isoString) {
    if (!isoString) return '--';
    const d = new Date(isoString);
    return d.toLocaleTimeString();
}

function formatDuration(startIso) {
    if (!startIso) return '--';
    const diff = Date.now() - new Date(startIso).getTime();
    const s = Math.floor(diff / 1000);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
}

// ── Init ───────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    loadSystemInfo();
    loadProcesses();
    connectWebSocket();
    initCharts();

    // 주기적으로 프로세스 목록 새로고침 (3초)
    setInterval(refreshProcessCards, 3000);
    // 주기적으로 duration 업데이트 (1초)
    setInterval(updateDurations, 1000);
});

// ── System Info ────────────────────────────────────────────────
async function loadSystemInfo() {
    try {
        const res = await fetch('/api/system');
        const info = await res.json();
        const badge = document.getElementById('systemBadge');
        badge.textContent = `${info.cpuCores} Cores · ${info.totalMemoryMB} MB · JDK ${info.jdkVersion}`;
    } catch (e) {
        console.error('Failed to load system info:', e);
    }
}

// ── WebSocket ──────────────────────────────────────────────────
function connectWebSocket() {
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${location.host}/ws/metrics`;

    state.ws = new WebSocket(wsUrl);

    state.ws.onopen = () => {
        updateConnectionStatus(true);
        console.log('WebSocket connected');
    };

    state.ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'metric') {
                handleMetricUpdate(msg.processId, msg.data);
            } else if (msg.type === 'status') {
                handleStatusUpdate(msg.processId, msg.status);
            } else if (msg.type === 'alert') {
                handleAlertEvent(msg.processId, msg.events);
            }
        } catch (e) {
            console.error('WS message parse error:', e);
        }
    };

    state.ws.onclose = () => {
        updateConnectionStatus(false);
        console.log('WebSocket disconnected, reconnecting in 3s...');
        setTimeout(connectWebSocket, 3000);
    };

    state.ws.onerror = () => {
        updateConnectionStatus(false);
    };
}

function updateConnectionStatus(connected) {
    const el = document.getElementById('connectionStatus');
    if (connected) {
        el.innerHTML = '<span class="status-dot connected"></span><span>Connected</span>';
    } else {
        el.innerHTML = '<span class="status-dot disconnected"></span><span>Disconnected</span>';
    }
}

// ── Process Loading ────────────────────────────────────────────
async function loadProcesses() {
    try {
        const res = await fetch('/api/processes');
        const list = await res.json();
        list.forEach(p => { state.processes[p.id] = p; });
        renderProcessCards();
        updateProcessSelector();
    } catch (e) {
        console.error('Failed to load processes:', e);
    }
}

// ── Metric Handler ─────────────────────────────────────────────
function handleMetricUpdate(processId, data) {
    // 프로세스 정보 업데이트
    if (state.processes[processId]) {
        state.processes[processId].latestSnapshot = data;
    }

    // 선택된 프로세스의 차트 업데이트
    if (processId === state.selectedProcessId) {
        updateChartsWithData(data);
        updateCurrentValues(data);
    }

    // 카드 메트릭 업데이트
    updateCardMetrics(processId, data);
}

function handleStatusUpdate(processId, status) {
    if (state.processes[processId]) {
        state.processes[processId].status = status;
    }
    refreshProcessCards();
}

// ── Process Cards ──────────────────────────────────────────────
function renderProcessCards() {
    const container = document.getElementById('processCards');
    const empty = document.getElementById('emptyState');
    const entries = Object.values(state.processes);
    const count = document.getElementById('processCount');
    count.textContent = entries.length;

    if (entries.length === 0) {
        container.innerHTML = '';
        container.appendChild(createEmptyState());
        document.getElementById('chartsSection').style.display = 'none';
        return;
    }

    container.innerHTML = entries.map(p => createCardHtml(p)).join('');
    document.getElementById('chartsSection').style.display = 'block';
}

function createEmptyState() {
    const div = document.createElement('div');
    div.className = 'empty-state';
    div.id = 'emptyState';
    div.innerHTML = `
        <div class="empty-icon">🚀</div>
        <h3>No processes monitored</h3>
        <p>Click "Add JAR" to start monitoring a Java process</p>
    `;
    return div;
}

function createCardHtml(p) {
    const statusClass = (p.status || 'RUNNING').toLowerCase();
    const isSelected = p.id === state.selectedProcessId;
    const snap = p.latestSnapshot;
    const cpu = snap ? formatCpu(snap.cpuPercent) : '--';
    const rss = snap ? formatMB(snap.rssBytes) : '--';
    const heap = snap && snap.heapUsed >= 0 ? formatMB(snap.heapUsed) : '--';
    const heapMax = snap && snap.heapMax >= 0 ? formatMB(snap.heapMax) : '--';
    const cpuWidth = snap && snap.cpuPercent >= 0 ? Math.min(snap.cpuPercent, 100) : 0;
    const heapPct = snap && snap.heapMax > 0 ? (snap.heapUsed / snap.heapMax * 100) : 0;
    const cpuBarClass = cpuWidth > 90 ? 'warning' : 'cpu';

    return `
        <div class="process-card ${statusClass} ${isSelected ? 'selected' : ''}"
             onclick="selectProcess('${p.id}')" id="card-${p.id}">
            <div class="card-header">
                <div class="card-title">
                    <span class="card-status-dot ${statusClass}"></span>
                    <span class="card-label">${escapeHtml(p.label || 'Unknown')}</span>
                </div>
                <span class="card-pid">PID ${p.pid}</span>
            </div>
            <div class="card-metrics">
                <div class="metric-item">
                    <span class="metric-label">CPU</span>
                    <span class="metric-value cpu" id="cpu-${p.id}">${cpu}%</span>
                    <div class="metric-bar"><div class="metric-bar-fill ${cpuBarClass}" style="width:${cpuWidth}%"></div></div>
                </div>
                <div class="metric-item">
                    <span class="metric-label">RSS Memory</span>
                    <span class="metric-value memory" id="rss-${p.id}">${rss} MB</span>
                </div>
                <div class="metric-item">
                    <span class="metric-label">JVM Heap</span>
                    <span class="metric-value heap" id="heap-${p.id}">${heap} / ${heapMax} MB</span>
                    <div class="metric-bar"><div class="metric-bar-fill memory" style="width:${heapPct}%"></div></div>
                </div>
                <div class="metric-item">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value gc" id="uptime-${p.id}" data-start="${p.startTime || ''}">${formatDuration(p.startTime)}</span>
                </div>
            </div>
            <div class="card-footer">
                ${p.status === 'RUNNING' 
                    ? `<button class="btn btn-danger btn-sm" onclick="event.stopPropagation(); stopProcess('${p.id}')">Stop</button>`
                    : `<span style="font-size:11px;color:var(--text-muted)">Exit: ${p.exitCode}</span>`}
                <button class="btn btn-secondary btn-sm" onclick="event.stopPropagation(); exportReport('${p.id}', 'json')">📄 JSON</button>
            </div>
        </div>
    `;
}

function updateCardMetrics(processId, data) {
    const cpuEl = document.getElementById(`cpu-${processId}`);
    const rssEl = document.getElementById(`rss-${processId}`);
    const heapEl = document.getElementById(`heap-${processId}`);

    if (cpuEl) cpuEl.textContent = formatCpu(data.cpuPercent) + '%';
    if (rssEl) rssEl.textContent = formatMB(data.rssBytes) + ' MB';
    if (heapEl && data.heapUsed >= 0) {
        heapEl.textContent = `${formatMB(data.heapUsed)} / ${formatMB(data.heapMax)} MB`;
    }
}

function refreshProcessCards() {
    loadProcesses();
}

function updateDurations() {
    document.querySelectorAll('[id^="uptime-"]').forEach(el => {
        const start = el.getAttribute('data-start');
        if (start) el.textContent = formatDuration(start);
    });
}

// ── Process Selection ──────────────────────────────────────────
function selectProcess(id) {
    state.selectedProcessId = id;

    // 카드 하이라이트
    document.querySelectorAll('.process-card').forEach(c => c.classList.remove('selected'));
    const card = document.getElementById(`card-${id}`);
    if (card) card.classList.add('selected');

    // 셀렉트 박스 업데이트
    document.getElementById('selectedProcess').value = id;

    // 차트 초기화 → 히스토리 로드
    resetCharts();
    loadHistory(id);
}

function onProcessSelect() {
    const id = document.getElementById('selectedProcess').value;
    if (id) selectProcess(id);
}

function updateProcessSelector() {
    const select = document.getElementById('selectedProcess');
    const current = select.value;
    select.innerHTML = '<option value="">Select a process...</option>';
    Object.values(state.processes).forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = `${p.label} (PID:${p.pid})`;
        select.appendChild(opt);
    });
    if (current && state.processes[current]) {
        select.value = current;
    }
}

// ── Charts ─────────────────────────────────────────────────────
function initCharts() {
    const defaultOpts = {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 300 },
        scales: {
            x: {
                type: 'time',
                time: { unit: 'second', displayFormats: { second: 'HH:mm:ss' } },
                grid: { color: 'rgba(148,163,184,0.06)' },
                ticks: { color: '#64748b', font: { size: 10, family: "'JetBrains Mono'" }, maxTicksLimit: 8 }
            },
            y: {
                beginAtZero: true,
                grid: { color: 'rgba(148,163,184,0.06)' },
                ticks: { color: '#64748b', font: { size: 10, family: "'JetBrains Mono'" } }
            }
        },
        plugins: {
            legend: { display: false },
            tooltip: {
                backgroundColor: '#1a2235',
                borderColor: 'rgba(59,130,246,0.3)',
                borderWidth: 1,
                titleFont: { family: "'Inter'" },
                bodyFont: { family: "'JetBrains Mono'", size: 12 }
            }
        },
        elements: {
            point: { radius: 0, hoverRadius: 4 },
            line: { tension: 0.3, borderWidth: 2 }
        }
    };

    // CPU Chart
    state.charts.cpu = new Chart(document.getElementById('cpuChart'), {
        type: 'line',
        data: {
            datasets: [{
                label: 'CPU %',
                data: [],
                borderColor: '#06b6d4',
                backgroundColor: 'rgba(6,182,212,0.1)',
                fill: true
            }]
        },
        options: { ...defaultOpts, scales: { ...defaultOpts.scales, y: { ...defaultOpts.scales.y, max: 100, ticks: { ...defaultOpts.scales.y.ticks, callback: v => v + '%' } } } }
    });

    // RSS Chart
    state.charts.rss = new Chart(document.getElementById('rssChart'), {
        type: 'line',
        data: {
            datasets: [{
                label: 'RSS (MB)',
                data: [],
                borderColor: '#8b5cf6',
                backgroundColor: 'rgba(139,92,246,0.1)',
                fill: true
            }]
        },
        options: { ...defaultOpts, scales: { ...defaultOpts.scales, y: { ...defaultOpts.scales.y, ticks: { ...defaultOpts.scales.y.ticks, callback: v => v + ' MB' } } } }
    });

    // Heap Chart
    state.charts.heap = new Chart(document.getElementById('heapChart'), {
        type: 'line',
        data: {
            datasets: [
                { label: 'Heap Used', data: [], borderColor: '#3b82f6', backgroundColor: 'rgba(59,130,246,0.1)', fill: true },
                { label: 'Heap Max', data: [], borderColor: '#64748b', borderDash: [5, 5], fill: false, borderWidth: 1 }
            ]
        },
        options: { ...defaultOpts, plugins: { ...defaultOpts.plugins, legend: { display: true, labels: { color: '#94a3b8', font: { size: 11 } } } }, scales: { ...defaultOpts.scales, y: { ...defaultOpts.scales.y, ticks: { ...defaultOpts.scales.y.ticks, callback: v => v + ' MB' } } } }
    });

    // GC Chart
    state.charts.gc = new Chart(document.getElementById('gcChart'), {
        type: 'line',
        data: {
            datasets: [
                { label: 'GC Count', data: [], borderColor: '#f59e0b', yAxisID: 'y' },
                { label: 'Threads', data: [], borderColor: '#10b981', yAxisID: 'y1' }
            ]
        },
        options: {
            ...defaultOpts,
            plugins: { ...defaultOpts.plugins, legend: { display: true, labels: { color: '#94a3b8', font: { size: 11 } } } },
            scales: {
                ...defaultOpts.scales,
                y: { ...defaultOpts.scales.y, position: 'left', title: { display: true, text: 'GC', color: '#64748b' } },
                y1: { ...defaultOpts.scales.y, position: 'right', grid: { drawOnChartArea: false }, title: { display: true, text: 'Threads', color: '#64748b' } }
            }
        }
    });

    // 차트 높이 설정 — Chart.js responsive 모드에서는 부모 컨테이너의 height가 필수
    document.querySelectorAll('.chart-card').forEach(card => {
        card.style.position = 'relative';
        card.style.height = '280px';
    });
}

function resetCharts() {
    Object.values(state.charts).forEach(chart => {
        chart.data.datasets.forEach(ds => { ds.data = []; });
        chart.update('none');
    });
}

async function loadHistory(processId) {
    try {
        const res = await fetch(`/api/processes/${processId}/metrics`);
        const series = await res.json();
        series.forEach(snap => updateChartsWithData(snap));
    } catch (e) {
        console.error('Failed to load history:', e);
    }
}

function parseTimestamp(ts) {
    if (!ts) return new Date();
    // ISO-8601 string or epoch seconds (number)
    if (typeof ts === 'string') return new Date(ts);
    if (typeof ts === 'number') {
        // epoch seconds (< 1e12) vs epoch millis (>= 1e12)
        return ts < 1e12 ? new Date(ts * 1000) : new Date(ts);
    }
    // { epochSecond, nano } object format from Jackson/Instant
    if (ts.epochSecond !== undefined) return new Date(ts.epochSecond * 1000);
    return new Date();
}

function updateChartsWithData(data) {
    const ts = parseTimestamp(data.timestamp);

    // CPU
    addDataPoint(state.charts.cpu, 0, ts, data.cpuPercent >= 0 ? data.cpuPercent : 0);

    // RSS
    addDataPoint(state.charts.rss, 0, ts, data.rssBytes >= 0 ? data.rssBytes / (1024 * 1024) : 0);

    // Heap
    if (data.heapUsed >= 0) {
        addDataPoint(state.charts.heap, 0, ts, data.heapUsed / (1024 * 1024));
        addDataPoint(state.charts.heap, 1, ts, data.heapMax / (1024 * 1024));
    }

    // GC & Threads
    if (data.gcCount >= 0) {
        addDataPoint(state.charts.gc, 0, ts, data.gcCount);
    }
    if (data.threadCount >= 0) {
        addDataPoint(state.charts.gc, 1, ts, data.threadCount);
    }

    // 차트 업데이트 (quiet mode for smooth transition)
    Object.values(state.charts).forEach(chart => chart.update());
}

function addDataPoint(chart, datasetIdx, time, value) {
    const ds = chart.data.datasets[datasetIdx];
    ds.data.push({ x: time, y: value });
    while (ds.data.length > state.maxChartPoints) {
        ds.data.shift();
    }
}

function updateCurrentValues(data) {
    document.getElementById('cpuValue').textContent = formatCpu(data.cpuPercent) + '%';
    document.getElementById('rssValue').textContent = formatMB(data.rssBytes) + ' MB';
    if (data.heapUsed >= 0) {
        document.getElementById('heapValue').textContent = `${formatMB(data.heapUsed)} / ${formatMB(data.heapMax)} MB`;
    }
    if (data.gcCount >= 0) {
        document.getElementById('gcValue').textContent = `GC:${data.gcCount} T:${data.threadCount}`;
    }
}

// ── API Actions ────────────────────────────────────────────────
async function submitRun() {
    const jarPath = document.getElementById('jarPath').value.trim();
    if (!jarPath) { alert('JAR path is required'); return; }

    const body = {
        jarPath: jarPath,
        jvmOpts: document.getElementById('jvmOpts').value.trim() || null,
        args: document.getElementById('appArgs').value.trim() || null,
        label: document.getElementById('processLabel').value.trim() || null
    };

    try {
        const res = await fetch('/api/processes/run', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        if (!res.ok) throw new Error('Launch failed');
        const info = await res.json();
        state.processes[info.id] = info;
        renderProcessCards();
        updateProcessSelector();
        hideModal('runModal');
        selectProcess(info.id);
        // 입력 초기화
        document.getElementById('jarPath').value = '';
        document.getElementById('jvmOpts').value = '';
        document.getElementById('appArgs').value = '';
        document.getElementById('processLabel').value = '';
    } catch (e) {
        alert('Failed to launch JAR: ' + e.message);
    }
}

async function submitAttach() {
    const pid = parseInt(document.getElementById('attachPid').value);
    if (!pid || pid <= 0) { alert('Valid PID is required'); return; }

    const body = {
        pid: pid,
        label: document.getElementById('attachLabel').value.trim() || null
    };

    try {
        const res = await fetch('/api/processes/attach', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        if (!res.ok) throw new Error('Attach failed');
        const info = await res.json();
        state.processes[info.id] = info;
        renderProcessCards();
        updateProcessSelector();
        hideModal('attachModal');
        selectProcess(info.id);
        document.getElementById('attachPid').value = '';
        document.getElementById('attachLabel').value = '';
    } catch (e) {
        alert('Failed to attach: ' + e.message);
    }
}

async function stopProcess(processId) {
    if (!confirm('Stop this process?')) return;
    try {
        await fetch(`/api/processes/${processId}/stop`, { method: 'POST' });
        loadProcesses();
    } catch (e) {
        alert('Failed to stop process');
    }
}

async function exportReport(processId, format) {
    try {
        const res = await fetch(`/api/processes/${processId}/report?format=${format}`);
        if (!res.ok) throw new Error('Export failed');
        const blob = await res.blob();
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `jprm-report-${processId}.${format}`;
        a.click();
        URL.revokeObjectURL(url);
    } catch (e) {
        // 리포트 API 미구현 시 메트릭 JSON 다운로드
        const res = await fetch(`/api/processes/${processId}/metrics`);
        const data = await res.json();
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `jprm-metrics-${processId}.json`;
        a.click();
        URL.revokeObjectURL(url);
    }
}

// ── Modal ──────────────────────────────────────────────────────
function showModal(id) {
    document.getElementById(id).classList.add('active');
}

function hideModal(id) {
    document.getElementById(id).classList.remove('active');
}

// ── Util ───────────────────────────────────────────────────────
function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

// ── Alerts ─────────────────────────────────────────────────────
function handleAlertEvent(processId, events) {
    const proc = state.processes[processId];
    const label = proc ? proc.label : processId;

    events.forEach(evt => {
        const alert = {
            time: new Date(),
            processId,
            label,
            metricType: evt.metricType,
            actualValue: evt.actualValue,
            thresholdValue: evt.thresholdValue
        };
        state.alerts.unshift(alert);
    });

    // 최대 50개
    if (state.alerts.length > 50) state.alerts.length = 50;
    renderAlerts();
}

function renderAlerts() {
    const section = document.getElementById('alertsSection');
    const list = document.getElementById('alertsList');
    const count = document.getElementById('alertCount');

    if (state.alerts.length === 0) {
        section.style.display = 'none';
        return;
    }

    section.style.display = 'block';
    count.textContent = state.alerts.length;

    list.innerHTML = state.alerts.map(a => {
        const unit = a.metricType === 'RSS' ? ' MB' : '%';
        const time = a.time.toLocaleTimeString();
        const severity = a.actualValue > a.thresholdValue * 1.2 ? 'critical' : 'warning';
        return `
            <div class="alert-item ${severity}">
                <span class="alert-time">${time}</span>
                <span class="alert-label">${escapeHtml(a.label)}</span>
                <span class="alert-type">${a.metricType}</span>
                <span class="alert-value">${a.actualValue.toFixed(1)}${unit}</span>
                <span class="alert-threshold">/ ${a.thresholdValue.toFixed(1)}${unit}</span>
            </div>
        `;
    }).join('');
}

function clearAlerts() {
    state.alerts = [];
    renderAlerts();
}

// ── Settings ───────────────────────────────────────────────────
async function openSettings() {
    try {
        const [threshRes, notifyRes] = await Promise.all([
            fetch('/api/config/threshold'),
            fetch('/api/config/notification')
        ]);
        const threshold = await threshRes.json();
        const notification = await notifyRes.json();

        document.getElementById('cfgCpuPercent').value = threshold.cpuPercent;
        document.getElementById('cfgHeapPercent').value = threshold.heapPercent;
        document.getElementById('cfgRssMb').value = threshold.rssMb;

        document.getElementById('cfgNotifyEnabled').checked = notification.enabled;
        document.getElementById('cfgEmailEnabled').checked = notification.email.enabled;
        document.getElementById('cfgEmailTo').value = notification.email.to.join(', ');
        document.getElementById('cfgCooldown').value = notification.cooldownSeconds;

        showModal('settingsModal');
    } catch (e) {
        alert('Failed to load settings: ' + e.message);
    }
}

async function saveSettings() {
    try {
        // Save threshold
        await fetch('/api/config/threshold', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                cpuPercent: parseFloat(document.getElementById('cfgCpuPercent').value),
                heapPercent: parseFloat(document.getElementById('cfgHeapPercent').value),
                rssMb: parseInt(document.getElementById('cfgRssMb').value) || 0
            })
        });

        // Save notification
        const emailTo = document.getElementById('cfgEmailTo').value
            .split(',').map(s => s.trim()).filter(s => s.length > 0);

        await fetch('/api/config/notification', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                enabled: document.getElementById('cfgNotifyEnabled').checked,
                cooldownSeconds: parseInt(document.getElementById('cfgCooldown').value),
                email: {
                    enabled: document.getElementById('cfgEmailEnabled').checked,
                    to: emailTo
                }
            })
        });

        hideModal('settingsModal');
    } catch (e) {
        alert('Failed to save settings: ' + e.message);
    }
}
