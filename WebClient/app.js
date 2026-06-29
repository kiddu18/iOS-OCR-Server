let pipeline = [];
let accountRules = JSON.parse(localStorage.getItem('accountRules')) || [
    { keyword: 'OMV', account: '6022' },
    { keyword: 'PETROM', account: '6022' },
    { keyword: 'MOL ', account: '6022' },
    { keyword: 'LUKOIL', account: '6022' },
    { keyword: 'ENEL', account: '605' },
    { keyword: 'E.ON', account: '605' },
    { keyword: 'ENGIE', account: '605' },
    { keyword: 'CAFEA', account: '623' },
    { keyword: 'RESTAURANT', account: '623' },
    { keyword: 'FAN COURIER', account: '624' }
];

function saveRules() {
    localStorage.setItem('accountRules', JSON.stringify(accountRules));
    renderRules();
}

function renderRules() {
    const tbody = document.getElementById('rules-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    accountRules.forEach((rule, idx) => {
        tbody.innerHTML += `
            <tr>
                <td>${rule.keyword}</td>
                <td>${rule.account}</td>
                <td><button class="btn-text" style="color: var(--danger)" onclick="deleteRule(${idx})">Șterge</button></td>
            </tr>
        `;
    });
}

window.deleteRule = function(idx) {
    accountRules.splice(idx, 1);
    saveRules();
}

window.addAccountRule = function() {
    const kw = document.getElementById('rule-keyword').value.toUpperCase().trim();
    const acc = document.getElementById('rule-account').value.trim();
    if (kw && acc) {
        accountRules.push({ keyword: kw, account: acc });
        document.getElementById('rule-keyword').value = '';
        document.getElementById('rule-account').value = '';
        saveRules();
    }
}

// Tabs
window.switchTab = function(tabId) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
    document.getElementById(`tab-${tabId}`).classList.remove('hidden');
    document.querySelectorAll('nav a').forEach(el => el.classList.remove('active'));
    event.currentTarget.classList.add('active');
}

// Drag & Drop
const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');

['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
    dropZone.addEventListener(eventName, preventDefaults, false);
});
function preventDefaults(e) { e.preventDefault(); e.stopPropagation(); }
['dragenter', 'dragover'].forEach(eventName => { dropZone.addEventListener(eventName, () => dropZone.classList.add('dragover'), false); });
['dragleave', 'drop'].forEach(eventName => { dropZone.addEventListener(eventName, () => dropZone.classList.remove('dragover'), false); });

dropZone.addEventListener('drop', e => handleFiles(e.dataTransfer.files));
dropZone.addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', e => handleFiles(e.target.files));

function handleFiles(files) {
    Array.from(files).forEach(file => {
        if (!file.type.startsWith('image/')) return;
        const id = Date.now() + Math.random().toString(36).substr(2, 9);
        pipeline.push({ id, file, status: 'pending', name: file.name, data: null, url: URL.createObjectURL(file) });
    });
    renderPipeline();
    processNext();
}

function suggestAccount(companyName, fileType) {
    const text = (companyName || '').toUpperCase();
    for (let rule of accountRules) {
        if (text.includes(rule.keyword)) return rule.account;
    }
    // Simple fallback if no rule matches
    return fileType === 'Bon Fiscal' ? '602' : '371';
}

function renderPipeline() {
    const tbody = document.getElementById('pipeline-body');
    if (pipeline.length === 0) {
        tbody.innerHTML = `<tr id="empty-row"><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 40px;">Niciun document în așteptare. Încarcă fișiere pentru a începe.</td></tr>`;
        return;
    }
    
    tbody.innerHTML = '';
    pipeline.forEach((item, index) => {
        let statusHtml = '';
        if (item.status === 'pending') statusHtml = `<span class="status-badge status-pending"><i class="ph ph-hourglass"></i> Așteptare</span>`;
        if (item.status === 'processing') statusHtml = `<span class="status-badge status-processing"><i class="ph ph-spinner ph-spin"></i> Procesare</span>`;
        if (item.status === 'done') {
            const hasWarnings = item.data.globalRequiresManualVerification;
            statusHtml = hasWarnings 
                ? `<span class="status-badge status-warn" title="Necesită Atenție"><i class="ph ph-warning"></i> Atenție</span>` 
                : `<span class="status-badge status-ok"><i class="ph ph-check-circle"></i> Validat</span>`;
        }
        if (item.status === 'error') statusHtml = `<span class="status-badge status-err"><i class="ph ph-x-circle"></i> Eroare</span>`;

        const d = item.data || {};
        
        // Editable fields if done
        const typeHtml = item.status === 'done' ? `<input class="inline-input" value="${d.documentType || ''}" onchange="updateItem('${item.id}', 'documentType', this.value)">` : '-';
        const docHtml = item.status === 'done' ? `<div style="font-size: 0.8rem">Serie: ${d.documentSeries || '-'}<br>Nr: ${d.documentNumber || '-'}<br>Data: ${d.documentDate || '-'}</div>` : '-';
        const cuiHtml = item.status === 'done' ? `<input class="inline-input" value="${d.cui || ''}" onchange="updateItem('${item.id}', 'cui', this.value)" title="${d.companyName || ''}">` : '-';
        const totalHtml = item.status === 'done' ? `<input class="inline-input" value="${d.totalAmount || ''}" onchange="updateItem('${item.id}', 'totalAmount', this.value)">` : '-';
        const vatHtml = item.status === 'done' ? `<input class="inline-input" value="${d.vatAmount || ''}" onchange="updateItem('${item.id}', 'vatAmount', this.value)">` : '-';
        const accHtml = item.status === 'done' ? `<input class="inline-input" value="${d.suggestedAccount || ''}" onchange="updateItem('${item.id}', 'suggestedAccount', this.value)">` : '-';

        tbody.innerHTML += `
            <tr>
                <td>${statusHtml}</td>
                <td><a href="#" onclick="viewImage('${item.id}')" style="color:var(--accent)">${item.name}</a></td>
                <td>${typeHtml}</td>
                <td>${docHtml}</td>
                <td>${cuiHtml}</td>
                <td>${totalHtml}</td>
                <td>${vatHtml}</td>
                <td>${accHtml}</td>
                <td><button class="btn-text" onclick="removePipelineItem('${item.id}')" style="color:var(--danger)">Șterge</button></td>
            </tr>
        `;
    });
}

window.updateItem = function(id, field, value) {
    const item = pipeline.find(x => x.id === id);
    if (item && item.data) {
        item.data[field] = value;
    }
}

window.removePipelineItem = function(id) {
    pipeline = pipeline.filter(x => x.id !== id);
    renderPipeline();
}

window.viewImage = function(id) {
    const item = pipeline.find(x => x.id === id);
    if (item) {
        document.getElementById('modal-img').src = item.url;
        const warnDiv = document.getElementById('modal-warnings');
        warnDiv.innerHTML = '';
        if (item.data && item.data.fiscalWarnings && item.data.fiscalWarnings.length > 0) {
            warnDiv.innerHTML = `<strong>Alerte Fiscale:</strong><br>` + item.data.fiscalWarnings.join('<br>');
        }
        document.getElementById('image-modal').classList.remove('hidden');
    }
}

window.closeModal = function() {
    document.getElementById('image-modal').classList.add('hidden');
}

let isProcessing = false;

async function processNext() {
    if (isProcessing) return;
    const nextItem = pipeline.find(x => x.status === 'pending');
    if (!nextItem) return;

    isProcessing = true;
    nextItem.status = 'processing';
    renderPipeline();

    const formData = new FormData();
    formData.append('file', nextItem.file);
    const buyerCuiInput = document.getElementById('buyer-cui');
    if (buyerCuiInput && buyerCuiInput.value.trim() !== "") {
        formData.append('buyer_cui', buyerCuiInput.value.trim());
    }

    const baseUrl = document.getElementById('server-ip').value.replace(/\/$/, "");

    try {
        const response = await fetch(`${baseUrl}/upload`, { method: 'POST', headers: { 'Accept': 'application/json' }, body: formData });
        if (!response.ok) throw new Error('Network error');
        const data = await response.json();
        
        if (data.success && data.accounting_data) {
            nextItem.data = data.accounting_data;
            nextItem.data.suggestedAccount = suggestAccount(nextItem.data.companyName, nextItem.data.documentType);
            nextItem.status = 'done';
        } else {
            nextItem.status = 'error';
        }
    } catch (e) {
        nextItem.status = 'error';
    }

    isProcessing = false;
    renderPipeline();
    processNext(); // loop to next item
}

// Export Excel Bulk
document.getElementById('export-bulk-btn').addEventListener('click', () => {
    const doneItems = pipeline.filter(x => x.status === 'done' && x.data);
    if (doneItems.length === 0) {
        alert("Nu ai documente procesate complet pentru a genera Excel-ul.");
        return;
    }

    // Varianta A: Construire dupa header-ele configurate
    const mapping = {};
    document.querySelectorAll('.export-col').forEach(input => {
        mapping[input.dataset.key] = input.value;
    });

    const rows = doneItems.map(item => {
        const d = item.data;
        return {
            [mapping.filename]: item.name,
            [mapping.type]: d.documentType || '',
            [mapping.series]: d.documentSeries || '',
            [mapping.number]: d.documentNumber || '',
            [mapping.date]: d.documentDate || '',
            [mapping.cui]: d.cui || '',
            [mapping.company]: d.companyName || '',
            [mapping.total]: d.totalAmount || '',
            [mapping.base]: d.baseAmount || '',
            [mapping.vat]: d.vatAmount || '',
            [mapping.account]: d.suggestedAccount || ''
        };
    });

    const worksheet = XLSX.utils.json_to_sheet(rows);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, "Export OCR");
    
    // Genereaza numele fisierului Excel
    const d = new Date();
    const dateStr = `${d.getFullYear()}-${d.getMonth()+1}-${d.getDate()}`;
    XLSX.writeFile(workbook, `export_contabilitate_${dateStr}.xlsx`);
});

// Init
renderRules();
