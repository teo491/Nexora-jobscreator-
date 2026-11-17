/* =============================================================================
   Nexora Jobs Creator - NUI application
   -----------------------------------------------------------------------------
   Three independent UIs live in this file:

     1. the creator  (openCreator / closeCreator)
     2. the boss menu (openBoss / closeBoss)
     3. generic in-world dialogs (dialog / dialogClose) used as the ox_lib
        fallback for menus, inputs, confirms

   Nothing here is trusted by the server: every save goes through
   `creator:request` -> a server callback that re-validates the payload.
   ========================================================================== */

(function () {
    'use strict';

    /* =====================================================================
       RESOURCE / TRANSPORT
       ===================================================================== */

    const RESOURCE = (function () {
        if (typeof window.GetParentResourceName === 'function') {
            try { return window.GetParentResourceName(); } catch (e) { /* ignore */ }
        }
        const host = window.location.hostname;
        if (host && host !== 'localhost' && host !== '127.0.0.1' && host !== '') return host;
        return 'nexora_jobscreator';
    })();

    async function nui(name, data) {
        try {
            const response = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            });
            return await response.json();
        } catch (err) {
            console.error('[nexora] nui call failed', name, err);
            return { ok: false, error: 'the client did not answer' };
        }
    }

    /** Call a whitelisted server endpoint through the client. */
    async function request(endpoint, payload) {
        const result = await nui('creator:request', { endpoint, payload: payload || {} });
        if (!result || result.ok !== true) {
            return { ok: false, error: (result && result.error) || 'unknown error' };
        }
        return { ok: true, data: result.data };
    }

    /* =====================================================================
       SMALL HELPERS
       ===================================================================== */

    const $ = (selector, root) => (root || document).querySelector(selector);
    const $$ = (selector, root) => Array.from((root || document).querySelectorAll(selector));

    function esc(value) {
        if (value === null || value === undefined) return '';
        return String(value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    }

    function getPath(object, path) {
        if (!object || !path) return undefined;
        return path.split('.').reduce((acc, key) => (acc === null || acc === undefined ? undefined : acc[key]), object);
    }

    function setPath(object, path, value) {
        const parts = path.split('.');
        let target = object;
        for (let i = 0; i < parts.length - 1; i += 1) {
            if (typeof target[parts[i]] !== 'object' || target[parts[i]] === null) target[parts[i]] = {};
            target = target[parts[i]];
        }
        target[parts[parts.length - 1]] = value;
    }

    const num = (value, fallback) => {
        const parsed = parseFloat(value);
        return Number.isFinite(parsed) ? parsed : (fallback === undefined ? 0 : fallback);
    };

    const money = (value) => '$' + Math.floor(num(value, 0)).toLocaleString('en-US');

    const slug = (value) => String(value || '').toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_]/g, '').replace(/_+/g, '_');

    function rgbToHex(color) {
        const clamp = (v) => Math.max(0, Math.min(255, Math.round(num(v, 0))));
        const hex = (v) => clamp(v).toString(16).padStart(2, '0');
        return `#${hex(color && color.r)}${hex(color && color.g)}${hex(color && color.b)}`;
    }

    function hexToRgb(hex) {
        const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(String(hex || ''));
        if (!match) return { r: 0, g: 155, b: 255 };
        return { r: parseInt(match[1], 16), g: parseInt(match[2], 16), b: parseInt(match[3], 16) };
    }

    /* =====================================================================
       ICONS
       Inline stroke icons - no icon font, no network request, and they inherit
       the current text colour so every state works without extra CSS.
       ===================================================================== */

    const ICONS = {
        dashboard: '<rect x="3" y="3" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="2"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2"/>',
        jobs: '<rect x="2.5" y="7" width="19" height="13.5" rx="2.5"/><path d="M8.5 7V5.5a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2V7"/><path d="M2.5 12.5h19"/>',
        grades: '<circle cx="12" cy="8.5" r="5"/><path d="M8.3 12.7 7 21l5-2.6L17 21l-1.3-8.3"/>',
        markers: '<path d="M20 10.5c0 6-8 11.5-8 11.5s-8-5.5-8-11.5a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10.5" r="2.8"/>',
        boss: '<path d="M16.5 21v-1.8a4 4 0 0 0-4-4h-5a4 4 0 0 0-4 4V21"/><circle cx="10" cy="7" r="3.8"/><path d="M19 8.5 20.5 10l3-3"/>',
        stashes: '<path d="m21 8.5-9-5-9 5v7l9 5 9-5Z"/><path d="m3 8.5 9 5 9-5"/><path d="M12 13.5V21"/>',
        garages: '<path d="M3 21V9l9-5.5L21 9v12"/><path d="M7 21v-7.5h10V21"/><path d="M7 17.5h10"/>',
        vehicles: '<path d="m4.5 13 1.7-4.6A2.5 2.5 0 0 1 8.5 6.8h7a2.5 2.5 0 0 1 2.3 1.6L19.5 13"/><rect x="3" y="13" width="18" height="5" rx="1.8"/><path d="M6.5 18v1.8M17.5 18v1.8"/><circle cx="7.5" cy="15.5" r=".9"/><circle cx="16.5" cy="15.5" r=".9"/>',
        settings: '<path d="M4 7h16M4 12.5h16M4 18h16"/><circle cx="9" cy="7" r="2.2"/><circle cx="15" cy="12.5" r="2.2"/><circle cx="8" cy="18" r="2.2"/>',

        plus: '<path d="M12 5.5v13M5.5 12h13"/>',
        edit: '<path d="M12.5 20H21"/><path d="M16.2 3.8a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4Z"/>',
        trash: '<path d="M3.5 6.5h17"/><path d="M9 6.5v-2h6v2"/><path d="M18.5 6.5V19a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2V6.5"/><path d="M10 11v6M14 11v6"/>',
        copy: '<rect x="9" y="9" width="12" height="12" rx="2.5"/><path d="M5.5 15H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v.5"/>',
        refresh: '<path d="M20.5 12a8.5 8.5 0 1 1-2.5-6"/><path d="M20.5 3.5v6h-6"/>',
        close: '<path d="M18 6 6 18M6 6l12 12"/>',
        search: '<circle cx="11" cy="11" r="7"/><path d="m20.5 20.5-4.2-4.2"/>',
        check: '<path d="m5 12.5 4.8 4.8L19 8"/>',
        alert: '<path d="M12 8.5v4.5M12 17h.01"/><circle cx="12" cy="12" r="9"/>',
        info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
        up: '<path d="m6 14 6-6 6 6"/>',
        right: '<path d="m9.5 5.5 6.5 6.5-6.5 6.5"/>',
        pin: '<path d="M12 21v-7"/><path d="M8 3h8l-1 6 3 3H6l3-3Z"/>',
        target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3"/><path d="M12 1.5v3M12 19.5v3M1.5 12h3M19.5 12h3"/>',
        eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="3"/>',
        money: '<rect x="2.5" y="6" width="19" height="12" rx="2.5"/><circle cx="12" cy="12" r="2.8"/><path d="M6 10v4M18 10v4"/>',
        receipt: '<path d="M5.5 3h13v18l-2.2-1.6-2.1 1.6-2.2-1.6L9.8 21l-2.1-1.6L5.5 21Z"/><path d="M9 8.5h6M9 12.5h6"/>',
        users: '<path d="M16 21v-1.8a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4V21"/><circle cx="9" cy="7" r="3.8"/><path d="M22 21v-1.8a4 4 0 0 0-3-3.85"/><path d="M16 3.3a4 4 0 0 1 0 7.4"/>',
        userPlus: '<path d="M15 21v-1.8a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4V21"/><circle cx="8.5" cy="7" r="3.8"/><path d="M19 8v6M22 11h-6"/>',
        clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5.3l3.2 2"/>',
        save: '<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2Z"/><path d="M17 21v-8H7v8M7 3v5h7"/>',
        layers: '<path d="m12 3 9 5-9 5-9-5Z"/><path d="m3 13 9 5 9-5"/>',
        bolt: '<path d="M13 3 5 13.5h6l-1 7.5 8-10.5h-6Z"/>',
        shield: '<path d="M12 3 4.5 6v6c0 4.8 3.2 8.2 7.5 9 4.3-.8 7.5-4.2 7.5-9V6Z"/>',
        wrench: '<path d="M14.5 6a4.5 4.5 0 0 0 5.9 5.9L21 11l-8 8-1-1-6.5 2.5L8 14l-1-1 8-8Z"/>',
        door: '<path d="M4 21h16"/><path d="M6.5 21V4.5a1.5 1.5 0 0 1 1.5-1.5h8a1.5 1.5 0 0 1 1.5 1.5V21"/><circle cx="14.5" cy="12.5" r="1"/>',
        box: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M3 11.5h18"/><path d="M12 7V3"/>',
        craft: '<path d="M11 4 4 11l3 3 7-7Z"/><path d="m14 14 6 6"/><path d="m16.5 3.5 4 4-2.5 2.5-4-4Z"/>',
        shop: '<path d="M4 8.5h16l-1 11.5H5Z"/><path d="M8.5 8.5V6a3.5 3.5 0 0 1 7 0v2.5"/>',
        shirt: '<path d="M8 3 4 5.5l1.5 4L8 8.5V21h8V8.5l2.5 1L20 5.5 16 3a4 4 0 0 1-8 0Z"/>',
        gun: '<path d="M3 8.5h13l2 4h3v3h-4l-2 3h-4l-1-3H6l-3-3Z"/>',
        swap: '<path d="M7 4 3.5 7.5 7 11"/><path d="M3.5 7.5H17a3.5 3.5 0 0 1 0 7H7"/><path d="m10.5 11-3.5 3.5L10.5 18"/>',
        star: '<path d="m12 3.5 2.7 5.5 6 .9-4.3 4.2 1 6-5.4-2.8L6.6 20l1-6L3.3 9.9l6-.9Z"/>',
        database: '<ellipse cx="12" cy="5.5" rx="8" ry="3"/><path d="M4 5.5v13c0 1.7 3.6 3 8 3s8-1.3 8-3v-13"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
    };

    /** Map a FontAwesome-ish class (what the Lua side sends) to a local icon. */
    function mapIcon(fa) {
        const key = String(fa || '').toLowerCase();
        const table = [
            ['car', 'vehicles'], ['truck', 'vehicles'], ['warehouse', 'garages'],
            ['box', 'stashes'], ['archive', 'stashes'], ['shirt', 'shirt'],
            ['hammer', 'craft'], ['wrench', 'wrench'], ['screwdriver', 'craft'],
            ['cart', 'shop'], ['shop', 'shop'], ['gun', 'gun'],
            ['clock', 'clock'], ['user-tie', 'boss'], ['users', 'users'], ['user', 'users'],
            ['briefcase', 'jobs'], ['rotate', 'refresh'], ['right-left', 'swap'],
            ['layer', 'layers'], ['star', 'star'], ['shield', 'shield'],
            ['location', 'markers'], ['map', 'markers'], ['sliders', 'settings'], ['gear', 'settings'],
        ];
        for (const [needle, name] of table) {
            if (key.includes(needle)) return name;
        }
        return 'right';
    }

    /** Inline SVG icon. */
    function ico(name, size) {
        const path = ICONS[name];
        if (!path) return '';
        const dimension = size ? ` width="${size}" height="${size}"` : '';
        return `<svg viewBox="0 0 24 24"${dimension} fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
    }

    const TOAST_ICON = { success: 'check', error: 'alert', warn: 'alert' };

    function toast(message, kind, title) {
        const host = $('#toasts');
        if (!host) return;

        const node = document.createElement('div');
        node.className = `toast ${kind || ''}`;
        node.innerHTML = `
            <div class="toast-ico">${ico(TOAST_ICON[kind] || 'info')}</div>
            <div class="toast-text">
                ${title ? `<strong>${esc(title)}</strong>` : ''}
                <span>${esc(message)}</span>
            </div>`;
        host.appendChild(node);

        setTimeout(() => {
            node.style.transition = 'opacity .25s, transform .25s';
            node.style.opacity = '0';
            node.style.transform = 'translateX(16px)';
            setTimeout(() => node.remove(), 260);
        }, 4200);
    }

    /* =====================================================================
       STATE
       ===================================================================== */

    const state = {
        open: false,
        data: null,            // the full creator dataset from the server
        section: 'dashboard',
        jobFilter: '',
        kindFilter: '',
        jobScope: '',          // selected job for the per-job sections
        drawer: null,          // { title, schema, values, onSave }
        placementToken: 0,
        placementResolve: null,
        boss: null,
        bossTab: 'employees',
        dialogToken: null,
    };

    /* =====================================================================
       FORM ENGINE
       Fields are declared once per entity and reused for create + edit.
       ===================================================================== */

    function fieldInput(field, values) {
        const path = field.name;
        const raw = getPath(values, path);
        const kind = field.type || 'text';
        const common = `data-path="${esc(path)}" data-kind="${esc(kind)}"`;

        switch (kind) {
            case 'checkbox': {
                const checked = raw === true || raw === 1 ? 'checked' : '';
                return `<label class="switch"><input type="checkbox" ${common} ${checked}><span class="track"></span><span>${esc(field.on || 'Enabled')}</span></label>`;
            }
            case 'number': {
                const value = raw === undefined || raw === null ? (field.default !== undefined ? field.default : '') : raw;
                return `<input class="input" type="number" ${common}
                    ${field.min !== undefined ? `min="${field.min}"` : ''}
                    ${field.max !== undefined ? `max="${field.max}"` : ''}
                    step="${field.step || 1}" value="${esc(value)}"
                    placeholder="${esc(field.placeholder || '')}">`;
            }
            case 'select': {
                const current = raw === undefined || raw === null ? field.default : raw;
                const options = (typeof field.options === 'function' ? field.options() : field.options) || [];
                const body = options.map((option) => {
                    const value = option.value !== undefined ? option.value : option;
                    const label = option.label !== undefined ? option.label : option;
                    const selected = String(value) === String(current) ? 'selected' : '';
                    return `<option value="${esc(value)}" ${selected}>${esc(label)}</option>`;
                }).join('');
                return `<select class="select" ${common} data-numeric="${field.numeric ? '1' : '0'}">${body}</select>`;
            }
            case 'textarea':
                return `<textarea class="textarea" ${common} rows="${field.rows || 3}" placeholder="${esc(field.placeholder || '')}">${esc(raw || '')}</textarea>`;
            case 'color': {
                const color = raw && typeof raw === 'object' ? raw : { r: 0, g: 155, b: 255, a: 140 };
                return `<div class="form-row two">
                    <input class="input" type="color" data-path="${esc(path)}" data-kind="color" value="${rgbToHex(color)}">
                    <div class="field">
                        <label>Alpha (${esc(color.a === undefined ? 140 : color.a)})</label>
                        <input class="input" type="range" min="0" max="255" value="${esc(color.a === undefined ? 140 : color.a)}"
                            data-path="${esc(path)}.a" data-kind="number">
                    </div>
                </div>`;
            }
            case 'multi': {
                const selected = Array.isArray(raw) ? raw.map(String) : [];
                const options = (typeof field.options === 'function' ? field.options() : field.options) || [];
                const body = options.map((option) => {
                    const value = option.value !== undefined ? option.value : option;
                    const label = option.label !== undefined ? option.label : option;
                    const on = selected.includes(String(value));
                    return `<label class="check ${on ? 'on' : ''}">
                        <input type="checkbox" value="${esc(value)}" ${on ? 'checked' : ''}>${esc(label)}
                    </label>`;
                }).join('');
                return `<div class="checks" data-multi="${esc(path)}" data-multi-kind="${field.numeric ? 'number' : 'string'}">${body}</div>`;
            }
            case 'coords': {
                const coords = raw && typeof raw === 'object' ? raw : { x: 0, y: 0, z: 0 };
                const headingPath = field.headingName || 'heading';
                const heading = getPath(values, headingPath);
                return `<div>
                    <div class="coords-grid">
                        <input class="input" type="number" step="0.001" placeholder="X" data-path="${esc(path)}.x" data-kind="number" value="${esc(coords.x)}">
                        <input class="input" type="number" step="0.001" placeholder="Y" data-path="${esc(path)}.y" data-kind="number" value="${esc(coords.y)}">
                        <input class="input" type="number" step="0.001" placeholder="Z" data-path="${esc(path)}.z" data-kind="number" value="${esc(coords.z)}">
                        <input class="input" type="number" step="0.01" placeholder="Heading" data-path="${esc(headingPath)}" data-kind="number" value="${esc(heading === undefined ? 0 : heading)}">
                    </div>
                    <div class="coords-actions">
                        <button type="button" class="btn btn-sm" data-act="use-position" data-target="${esc(path)}" data-heading="${esc(headingPath)}">${ico('target')}Use my position</button>
                        <button type="button" class="btn btn-sm btn-primary" data-act="place-world" data-target="${esc(path)}" data-heading="${esc(headingPath)}">${ico('pin')}Place in world</button>
                    </div>
                </div>`;
            }
            case 'list':
                return renderList(field, raw);
            case 'static':
                return `<div class="mono">${esc(raw === undefined ? (field.default || '') : raw)}</div>`;
            case 'blip-sprite': {
                const value = raw === undefined || raw === null ? 1 : raw;
                const sprites = (state.data && state.data.definitions.blipSprites) || [];
                const options = sprites.map((sprite) =>
                    `<option value="${sprite.value}" ${Number(sprite.value) === Number(value) ? 'selected' : ''}>${esc(sprite.value)} - ${esc(sprite.label)}</option>`).join('');
                return `<div class="form-row two">
                    <select class="select" data-act="sprite-pick">${options}</select>
                    <input class="input" type="number" min="1" max="850" ${common} value="${esc(value)}" placeholder="Sprite id">
                </div>`;
            }
            case 'blip-color': {
                const value = raw === undefined || raw === null ? 0 : Number(raw);
                const palette = (state.data && state.data.definitions.blipColors) || {};
                const swatches = Object.keys(palette).sort((a, b) => Number(a) - Number(b)).map((id) =>
                    `<div class="swatch ${Number(id) === value ? 'on' : ''}" style="background:${esc(palette[id])}"
                        title="Blip colour ${esc(id)}" data-act="blip-color" data-value="${esc(id)}"></div>`).join('');
                return `<div>
                    <input class="input" type="number" min="0" max="85" ${common} value="${value}">
                    <div class="swatches" style="margin-top:8px">${swatches}</div>
                </div>`;
            }
            default: {
                const value = raw === undefined || raw === null ? (field.default !== undefined ? field.default : '') : raw;
                return `<input class="input" type="${field.password ? 'password' : 'text'}" ${common}
                    value="${esc(value)}" placeholder="${esc(field.placeholder || '')}"
                    ${field.readonly ? 'readonly' : ''} maxlength="${field.maxlength || 128}">`;
            }
        }
    }

    function renderList(field, rows) {
        const columns = field.columns || [];
        const template = columns.map((column) => column.width || '1fr').join(' ') + ' 76px';
        const list = Array.isArray(rows) ? rows : [];

        const header = `<div class="list-row" style="grid-template-columns:${template};background:transparent;border:0;padding:0 10px 2px">
            ${columns.map((column) => `<span class="list-head">${esc(column.label)}</span>`).join('')}
            <span></span>
        </div>`;

        const body = list.map((row, index) => renderListRow(field, row, index, template)).join('');

        return `<div data-list="${esc(field.name)}" data-list-template="${esc(template)}">
            ${columns.length ? header : ''}
            <div class="list-rows" data-list-body>${body}</div>
            ${list.length ? '' : `<p class="help" style="padding:10px 2px">Nothing here yet &mdash; add your first ${esc(field.itemLabel || 'row')}.</p>`}
            <button type="button" class="btn btn-sm" style="margin-top:10px" data-act="list-add">${ico('plus')}Add ${esc(field.itemLabel || 'row')}</button>
        </div>`;
    }

    function renderListRow(field, row, index, template) {
        const columns = field.columns || [];
        return `<div class="list-row" data-list-row data-index="${index}" style="grid-template-columns:${template}">
            ${columns.map((column) => fieldInput({ ...column, name: column.name }, row || {})).join('')}
            <div class="row-actions">
                <button type="button" class="btn btn-sm btn-icon" data-act="list-up" title="Move up">${ico('up')}</button>
                <button type="button" class="btn btn-sm btn-icon btn-danger" data-act="list-del" title="Remove">${ico('trash')}</button>
            </div>
        </div>`;
    }

    function renderForm(schema, values) {
        return schema.map((group) => {
            if (group.group) {
                return `<fieldset class="fieldset" style="margin-bottom:14px">
                    <legend>${esc(group.group)}</legend>
                    ${renderForm(group.fields, values)}
                </fieldset>`;
            }

            if (group.row) {
                const cls = group.row === 2 ? 'two' : group.row === 3 ? 'three' : 'four';
                return `<div class="form-row ${cls}">${group.fields.map((field) => wrapField(field, values)).join('')}</div>`;
            }

            if (group.html) {
                return typeof group.html === 'function' ? group.html(values) : group.html;
            }

            return wrapField(group, values);
        }).join('');
    }

    function wrapField(field, values) {
        if (field.when && !field.when(values)) return '';
        return `<div class="field" data-field="${esc(field.name || '')}">
            ${field.label ? `<label>${esc(field.label)}</label>` : ''}
            ${fieldInput(field, values)}
            ${field.help ? `<span class="help">${esc(field.help)}</span>` : ''}
        </div>`;
    }

    function readInput(input) {
        const kind = input.dataset.kind || 'text';
        if (kind === 'checkbox') return input.checked;
        if (kind === 'number') {
            if (input.value === '') return null;
            return num(input.value, 0);
        }
        if (kind === 'color') return hexToRgb(input.value);
        if (input.tagName === 'SELECT' && input.dataset.numeric === '1') return num(input.value, 0);
        return input.value;
    }

    function readForm(root) {
        const out = {};

        $$('[data-path]', root).forEach((input) => {
            if (input.closest('[data-list-row]')) return;
            const kind = input.dataset.kind;
            const path = input.dataset.path;

            if (kind === 'color') {
                const rgb = hexToRgb(input.value);
                const existing = getPath(out, path) || {};
                setPath(out, path, { ...existing, ...rgb });
                return;
            }
            // `<path>.a` alpha inputs merge into the same object
            setPath(out, path, readInput(input));
        });

        $$('[data-multi]', root).forEach((group) => {
            const numeric = group.dataset.multiKind === 'number';
            const values = $$('input:checked', group).map((input) => (numeric ? num(input.value, 0) : input.value));
            setPath(out, group.dataset.multi, values);
        });

        $$('[data-list]', root).forEach((listEl) => {
            const rows = $$('[data-list-row]', listEl).map((rowEl) => {
                const row = {};
                $$('[data-path]', rowEl).forEach((input) => {
                    if (input.dataset.kind === 'color') {
                        const rgb = hexToRgb(input.value);
                        const existing = getPath(row, input.dataset.path) || {};
                        setPath(row, input.dataset.path, { ...existing, ...rgb });
                        return;
                    }
                    setPath(row, input.dataset.path, readInput(input));
                });
                $$('[data-multi]', rowEl).forEach((group) => {
                    const numeric = group.dataset.multiKind === 'number';
                    setPath(row, group.dataset.multi, $$('input:checked', group).map((i) => (numeric ? num(i.value, 0) : i.value)));
                });
                return row;
            });
            setPath(out, listEl.dataset.list, rows);
        });

        return out;
    }

    /* =====================================================================
       DRAWER
       ===================================================================== */

    const TAB_ICONS = {
        'General': 'info', 'Position': 'target', 'Access': 'shield', 'Marker': 'pin', 'Blip': 'markers',
        'Off duty restrictions': 'clock', 'Presentation': 'star', 'Spawn point': 'target',
        'Return point': 'swap', 'Behaviour': 'settings', 'Grade access': 'grades', 'Appearance': 'star',
        'Features': 'layers', 'Teleport destination': 'swap', 'Duty point': 'clock', 'Outfits': 'shirt',
        'Shop items': 'shop', 'Armory items': 'gun', 'Recipes': 'craft', 'Custom interaction': 'star',
        'Garage link': 'garages',
    };

    /** Split a schema into drawer tabs: every top level group becomes one. */
    function drawerTabs(schema) {
        const tabs = [];
        const general = [];

        (schema || []).forEach((entry) => {
            if (entry.group) {
                tabs.push({ label: entry.group, entries: entry.fields || [], icon: TAB_ICONS[entry.group] || 'info' });
            } else {
                general.push(entry);
            }
        });

        if (general.length) tabs.unshift({ label: 'General', entries: general, icon: 'info' });
        return tabs.length ? tabs : [{ label: 'General', entries: schema || [], icon: 'info' }];
    }

    /** Renders every pane up front - hidden inputs are still read on save. */
    function renderDrawerBody(schema, values) {
        const tabs = drawerTabs(schema);

        $('#drawer-tabs').innerHTML = tabs.length > 1
            ? tabs.map((tab, index) =>
                `<div class="drawer-tab ${index === 0 ? 'active' : ''}" data-drawer-tab="${index}">${ico(tab.icon)}${esc(tab.label)}</div>`).join('')
            : '';

        $('#drawer-body').innerHTML = `<div class="form" id="drawer-form">${tabs.map((tab, index) => `
            <div class="drawer-pane ${index === 0 ? '' : 'hidden'}" data-pane="${index}">
                ${renderForm(tab.entries, values)}
            </div>`).join('')}</div>`;

        $('#drawer-body').scrollTop = 0;
        refreshPreviews();
    }

    function openDrawer({ title, subtitle, schema, values, onSave, saveLabel, footLeft }) {
        state.drawer = { schema, values: JSON.parse(JSON.stringify(values || {})), onSave };

        $('#drawer-title').textContent = title;
        $('#drawer-sub').textContent = subtitle || '';
        $('#drawer-foot-left').innerHTML = footLeft || '';
        $('#drawer-save').innerHTML = `${ico('check')}${esc(saveLabel || 'Save')}`;
        $('#drawer').classList.remove('hidden');

        renderDrawerBody(schema, state.drawer.values);
    }

    function closeDrawer() {
        $('#drawer').classList.add('hidden');
        $('#drawer-body').innerHTML = '';
        $('#drawer-tabs').innerHTML = '';
        state.drawer = null;
        nui('creator:clearPreview', {});
    }

    async function submitDrawer() {
        if (!state.drawer) return;

        const form = $('#drawer-form');
        const payload = readForm(form);
        const button = $('#drawer-save');
        const label = button.innerHTML;

        button.disabled = true;
        button.innerHTML = '<span class="spinner" style="width:14px;height:14px"></span>Saving';

        try {
            const ok = await state.drawer.onSave(payload, state.drawer.values);
            if (ok !== false) {
                closeDrawer();
                await refresh();
            }
        } finally {
            button.disabled = false;
            button.innerHTML = label;
        }
    }

    /* =====================================================================
       CONFIRM
       ===================================================================== */

    function confirmDialog(title, message, confirmLabel) {
        return new Promise((resolve) => {
            const modal = $('#confirm');
            $('#confirm-title').textContent = title;
            $('#confirm-message').textContent = message;
            $('#confirm-ok').textContent = confirmLabel || 'Confirm';
            modal.classList.remove('hidden');

            const finish = (value) => {
                modal.classList.add('hidden');
                $('#confirm-ok').onclick = null;
                $('#confirm-cancel').onclick = null;
                resolve(value);
            };

            $('#confirm-ok').onclick = () => finish(true);
            $('#confirm-cancel').onclick = () => finish(false);
        });
    }

    /** Text prompt (window.prompt is not reliable inside CEF). */
    function promptDialog(title, label, defaultValue) {
        return new Promise((resolve) => {
            const modal = $('#dialog');
            $('#dialog-title').textContent = title;
            $('#dialog-body').innerHTML = `<div class="dialog-fields">
                <div class="field">
                    <label>${esc(label)}</label>
                    <input class="input" id="prompt-input" value="${esc(defaultValue || '')}">
                </div>
            </div>`;
            $('#dialog-actions').innerHTML = `
                <button class="btn btn-ghost" id="prompt-cancel">Cancel</button>
                <button class="btn btn-primary" id="prompt-ok">Confirm</button>`;
            modal.classList.remove('hidden');

            const input = $('#prompt-input');
            input.focus();
            input.select();

            const finish = (value) => {
                modal.classList.add('hidden');
                $('#dialog-body').innerHTML = '';
                $('#dialog-actions').innerHTML = '';
                resolve(value);
            };

            $('#prompt-ok').onclick = () => finish(input.value);
            $('#prompt-cancel').onclick = () => finish(null);
            input.onkeydown = (event) => {
                if (event.key === 'Enter') finish(input.value);
                if (event.key === 'Escape') finish(null);
            };
        });
    }

    /* =====================================================================
       DATA ACCESS HELPERS
       ===================================================================== */

    const jobs = () => (state.data && state.data.jobs) || [];
    const definitions = () => (state.data && state.data.definitions) || {};

    const jobByName = (name) => jobs().find((job) => job.name === name);

    function scopedJob() {
        if (state.jobScope) {
            const found = jobByName(state.jobScope);
            if (found) return found;
        }
        return jobs()[0] || null;
    }

    function allLocations() {
        const out = [];
        jobs().forEach((job) => (job.locations || []).forEach((location) => out.push({ ...location, jobLabel: job.label })));
        return out;
    }

    function gradeOptions(job) {
        return ((job && job.grades) || []).map((grade) => ({ value: grade.grade, label: `${grade.grade} - ${grade.label}` }));
    }

    function locationOptions(job, kinds) {
        const list = ((job && job.locations) || []).filter((location) => !kinds || kinds.includes(location.kind));
        return [{ value: '', label: 'Not linked to a location' }]
            .concat(list.map((location) => ({ value: location.id, label: `#${location.id} ${location.label} (${location.kind})` })));
    }

    function kindOptions() {
        return (definitions().locationKinds || []).map((kind) => ({ value: kind.value, label: kind.label }));
    }

    /* =====================================================================
       SHARED SCHEMA PARTS
       ===================================================================== */

    function markerGroup() {
        return {
            group: 'Marker',
            fields: [
                { name: 'marker.enabled', label: 'Show a marker', type: 'checkbox', on: 'Draw this marker in the world' },
                {
                    row: 2,
                    fields: [
                        { name: 'marker.type', label: 'Marker type', type: 'select', numeric: true, options: () => (definitions().markerTypes || []).map((m) => ({ value: m.value, label: m.label })) },
                        { name: 'marker.color', label: 'Colour', type: 'color' },
                    ],
                },
                {
                    row: 3,
                    fields: [
                        { name: 'marker.size.x', label: 'Size X', type: 'number', step: 0.05, default: 1 },
                        { name: 'marker.size.y', label: 'Size Y', type: 'number', step: 0.05, default: 1 },
                        { name: 'marker.size.z', label: 'Size Z', type: 'number', step: 0.05, default: 0.5 },
                    ],
                },
                {
                    row: 3,
                    fields: [
                        { name: 'marker.rotation.x', label: 'Rotation X', type: 'number', step: 1, default: 0 },
                        { name: 'marker.rotation.y', label: 'Rotation Y', type: 'number', step: 1, default: 0 },
                        { name: 'marker.rotation.z', label: 'Rotation Z', type: 'number', step: 1, default: 0 },
                    ],
                },
                {
                    row: 2,
                    fields: [
                        { name: 'marker.drawDistance', label: 'Draw distance (m)', type: 'number', step: 1, min: 1, max: 200, default: 20 },
                        { name: 'marker.interactDistance', label: 'Interaction distance (m)', type: 'number', step: 0.1, min: 0.5, max: 6, default: 1.8 },
                    ],
                },
                {
                    row: 3,
                    fields: [
                        { name: 'marker.bobUpAndDown', label: 'Bob', type: 'checkbox', on: 'Bob up and down' },
                        { name: 'marker.faceCamera', label: 'Face camera', type: 'checkbox', on: 'Always face the camera' },
                        { name: 'marker.rotate', label: 'Rotate', type: 'checkbox', on: 'Spin slowly' },
                    ],
                },
                { html: () => `<div class="preview-wrap"><div class="marker-preview" id="marker-preview"><div class="marker-shape" id="marker-shape"></div></div>
                    <div class="blip-info">Live preview of the marker colour, size and shape.<br>Use <b>Place in world</b> to see it in game.</div></div>` },
            ],
        };
    }

    function blipGroup() {
        return {
            group: 'Blip',
            fields: [
                { name: 'blip.enabled', label: 'Show a blip', type: 'checkbox', on: 'Put this location on the map' },
                {
                    row: 2,
                    fields: [
                        { name: 'blip.label', label: 'Blip name', type: 'text', placeholder: 'Shown on the map' },
                        { name: 'blip.sprite', label: 'Sprite', type: 'blip-sprite' },
                    ],
                },
                { name: 'blip.color', label: 'Blip colour', type: 'blip-color' },
                {
                    row: 3,
                    fields: [
                        { name: 'blip.scale', label: 'Scale', type: 'number', step: 0.05, min: 0.1, max: 2, default: 0.8 },
                        { name: 'blip.alpha', label: 'Alpha', type: 'number', step: 5, min: 0, max: 255, default: 255 },
                        { name: 'blip.display', label: 'Display', type: 'select', numeric: true, options: () => (definitions().blipDisplay || []).map((d) => ({ value: d.value, label: d.label })) },
                    ],
                },
                {
                    row: 2,
                    fields: [
                        { name: 'blip.shortRange', label: 'Short range', type: 'checkbox', on: 'Only show when nearby' },
                        { name: 'blip.category', label: 'Category', type: 'number', min: 0, max: 11, default: 0, help: 'GTA blip category (0 = default)' },
                    ],
                },
                { html: () => `<div class="preview-wrap">
                    <div class="blip-preview">
                        <div class="blip-dot" id="blip-dot">1</div>
                        <div class="blip-info" id="blip-info"></div>
                    </div>
                    <button type="button" class="btn btn-sm" style="margin-left:auto" data-act="preview-blip">${ico('eye')}Preview on the map</button>
                </div>` },
            ],
        };
    }

    function accessGroup(job) {
        return {
            group: 'Access',
            fields: [
                {
                    row: 2,
                    fields: [
                        { name: 'access.grade', label: 'Minimum grade', type: 'select', numeric: true, options: () => gradeOptions(job) },
                        { name: 'access.style', label: 'Interaction style', type: 'select', options: () => (definitions().interactionStyles || []).map((s) => ({ value: s.value, label: s.label })) },
                    ],
                },
                {
                    row: 2,
                    fields: [
                        { name: 'access.item', label: 'Required item', type: 'text', placeholder: 'optional, e.g. police_badge' },
                        { name: 'access.permission', label: 'Required grade permission', type: 'select', options: () => [{ value: '', label: 'None' }].concat((definitions().bossPermissions || []).map((p) => ({ value: p.value, label: p.label }))) },
                    ],
                },
                { name: 'access.duty', label: 'Duty', type: 'checkbox', on: 'Player must be on duty' },
            ],
        };
    }

    /* =====================================================================
       PREVIEWS
       ===================================================================== */

    function refreshPreviews() {
        const form = $('#drawer-form');
        if (!form) return;

        const shape = $('#marker-shape');
        if (shape) {
            const values = readForm(form);
            const color = (values.marker && values.marker.color) || { r: 0, g: 155, b: 255, a: 140 };
            const size = (values.marker && values.marker.size) || { x: 1, y: 1, z: 0.5 };
            const type = num(values.marker && values.marker.type, 1);

            const width = Math.max(10, Math.min(90, num(size.x, 1) * 34));
            const height = Math.max(10, Math.min(90, num(size.y, 1) * 34));
            const alpha = Math.max(0.08, Math.min(1, num(color.a, 140) / 255));

            shape.style.width = `${width}px`;
            shape.style.height = `${height}px`;
            shape.style.background = `rgba(${num(color.r, 0)},${num(color.g, 155)},${num(color.b, 255)},${alpha})`;
            shape.style.border = `1px solid rgba(255,255,255,0.35)`;

            if (type === 29) {
                shape.style.borderRadius = '4px';
            } else if ([28, 36, 27, 9, 6, 7, 25].includes(type)) {
                shape.style.borderRadius = '50%';
            } else if ([2, 3, 4, 5, 43, 21, 0].includes(type)) {
                shape.style.borderRadius = '50% 50% 4px 4px';
            } else {
                shape.style.borderRadius = '50% / 22%';
            }
        }

        const dot = $('#blip-dot');
        if (dot) {
            const values = readForm(form);
            const blip = values.blip || {};
            const palette = definitions().blipColors || {};
            const hex = palette[String(num(blip.color, 0))] || '#ffffff';
            const scale = Math.max(0.4, Math.min(1.6, num(blip.scale, 0.8)));

            dot.style.background = hex;
            dot.style.width = `${Math.round(30 * scale + 12)}px`;
            dot.style.height = `${Math.round(30 * scale + 12)}px`;
            dot.style.opacity = String(Math.max(0.25, num(blip.alpha, 255) / 255));
            dot.textContent = String(num(blip.sprite, 1));

            const info = $('#blip-info');
            if (info) {
                info.innerHTML = `<b>${esc(blip.label || '(no name)')}</b><br>
                    sprite ${esc(num(blip.sprite, 1))} &middot; colour ${esc(num(blip.color, 0))} &middot; scale ${esc(scale.toFixed(2))}<br>
                    ${blip.shortRange ? 'short range' : 'always visible'} &middot; display ${esc(num(blip.display, 4))}`;
            }
        }
    }

    /* =====================================================================
       NAVIGATION
       ===================================================================== */

    const SECTION_META = {
        dashboard: { title: 'Dashboard', sub: 'Everything on this server at a glance', icon: 'dashboard' },
        jobs:      { title: 'Jobs', sub: 'Create, edit, duplicate and remove jobs', icon: 'jobs' },
        grades:    { title: 'Grades', sub: 'Rank ladder, salaries and boss permissions', icon: 'grades' },
        markers:   { title: 'Markers & Locations', sub: 'Every interaction point in the world', icon: 'markers' },
        boss:      { title: 'Boss Menus', sub: 'Management offices and the features they expose', icon: 'boss' },
        stashes:   { title: 'Stashes', sub: 'Job storage, slots, weight and access rules', icon: 'stashes' },
        garages:   { title: 'Garages', sub: 'Spawn points, return points and plates', icon: 'garages' },
        vehicles:  { title: 'Vehicles', sub: 'Which vehicle each grade may take out', icon: 'vehicles' },
        settings:  { title: 'Settings', sub: 'Runtime configuration stored in the database', icon: 'settings' },
    };

    const NAV_GROUPS = [
        { label: 'Overview', ids: ['dashboard'] },
        { label: 'Structure', ids: ['jobs', 'grades'] },
        { label: 'World', ids: ['markers', 'boss', 'stashes', 'garages', 'vehicles'] },
        { label: 'System', ids: ['settings'] },
    ];

    function navCounts() {
        return {
            jobs: jobs().length,
            markers: allLocations().length,
            stashes: jobs().reduce((total, job) => total + (job.stashes || []).length, 0),
            garages: jobs().reduce((total, job) => total + (job.garages || []).length, 0),
            vehicles: jobs().reduce((total, job) => total + (job.garages || []).reduce((sum, garage) => sum + (garage.vehicles || []).length, 0), 0),
            boss: jobs().reduce((total, job) => total + (job.boss || []).length, 0),
            grades: jobs().reduce((total, job) => total + (job.grades || []).length, 0),
        };
    }

    function renderNav() {
        const available = {};
        (definitions().sections || []).forEach((section) => { available[section.id] = section.label; });
        const counts = navCounts();

        $('#nav').innerHTML = NAV_GROUPS.map((group) => {
            const items = group.ids.filter((id) => available[id]);
            if (!items.length) return '';

            return `<div class="nav-group">${esc(group.label)}</div>` + items.map((id) => {
                const meta = SECTION_META[id] || {};
                return `
                <div class="nav-item ${state.section === id ? 'active' : ''}" data-section="${esc(id)}" title="${esc(available[id])}">
                    ${ico(meta.icon || 'dashboard')}
                    <span class="label">${esc(available[id])}</span>
                    ${counts[id] !== undefined ? `<span class="count">${counts[id]}</span>` : ''}
                </div>`;
            }).join('');
        }).join('');

        const env = state.data || {};
        $('#env').innerHTML = [
            ['Framework', env.framework],
            ['Inventory', env.inventory],
            ['Target', env.client && env.client.target],
            ['Database', env.database],
            ['ox_lib', env.oxlib ? 'loaded' : 'not loaded'],
        ].map(([key, value]) => `
            <div class="row">
                <span class="dot ${value && value !== 'none' && value !== 'not loaded' ? 'green' : 'amber'}"></span>
                <b>${esc(key)}</b><span>${esc(value || 'none')}</span>
            </div>`).join('');

        $('#brand-version').textContent = `v${env.version || '1.0.0'}`;
    }

    function jobScopeSelect() {
        const current = scopedJob();
        const options = jobs().map((job) =>
            `<option value="${esc(job.name)}" ${current && current.name === job.name ? 'selected' : ''}>${esc(job.label)}</option>`).join('');

        return `<select class="select" style="max-width:260px" data-act="job-scope" title="Job">${options}</select>`;
    }

    function searchBox(placeholder) {
        return `<div class="search">
            ${ico('search')}
            <input class="input" placeholder="${esc(placeholder || 'Search...')}" data-act="filter-jobs" value="${esc(state.jobFilter)}">
        </div>`;
    }

    /* =====================================================================
       SECTION RENDERERS
       ===================================================================== */

    function render() {
        const meta = SECTION_META[state.section] || SECTION_META.dashboard;
        $('#section-title').innerHTML = `${ico(meta.icon || 'dashboard')}${esc(meta.title)}`;
        $('#section-sub').textContent = meta.sub;

        renderNav();

        const renderers = {
            dashboard: renderDashboard,
            jobs: renderJobs,
            grades: renderGrades,
            markers: renderMarkers,
            boss: renderBossMenus,
            stashes: renderStashes,
            garages: renderGarages,
            vehicles: renderVehicles,
            settings: renderSettings,
        };

        (renderers[state.section] || renderDashboard)();
    }

    /** Accent colour for a job card, if the admin set one. */
    function jobAccent(job) {
        const colour = job && job.meta && job.meta.color;
        if (typeof colour === 'string' && /^#[0-9a-f]{3,8}$/i.test(colour.trim())) {
            return ` style="--card-accent:${colour.trim()}"`;
        }
        return '';
    }

    function jobCard(job, compact) {
        return `
        <div class="card accent hoverable"${jobAccent(job)}>
            <div class="card-head">
                <div style="min-width:0">
                    <div class="card-title">
                        <span class="dot ${job.enabled ? 'green' : 'red'}"></span>${esc(job.label)}
                    </div>
                    <div class="card-sub">${esc(job.name)} &middot; ${esc(job.type)}</div>
                </div>
                ${compact ? `<span class="chip">${esc(job.type)}</span>` : `
                <label class="switch" title="Enable or disable this job">
                    <input type="checkbox" ${job.enabled ? 'checked' : ''} data-act="toggle-job" data-job="${esc(job.name)}">
                    <span class="track"></span>
                </label>`}
            </div>

            <div class="metrics">
                <div class="metric"><b>${(job.grades || []).length}</b><span>Grades</span></div>
                <div class="metric"><b>${(job.locations || []).length}</b><span>Locations</span></div>
                <div class="metric"><b>${(job.garages || []).length}</b><span>Garages</span></div>
                <div class="metric"><b>${(job.stashes || []).length}</b><span>Stashes</span></div>
                ${compact ? '' : `<div class="metric"><b>${(job.boss || []).length}</b><span>Offices</span></div>`}
            </div>

            ${compact ? '' : `
            <div class="card-meta">
                ${job.whitelisted ? `<span class="chip amber">${ico('shield')}whitelisted</span>` : ''}
                ${job.use_duty ? `<span class="chip on">${ico('clock')}duty</span>` : '<span class="chip">no duty</span>'}
                <span class="chip">${ico('grades')}starts at grade ${esc(job.default_grade)}</span>
            </div>`}

            <div class="card-actions">
                <button class="btn btn-sm btn-primary" data-act="edit-job" data-job="${esc(job.name)}">${ico('edit')}Edit</button>
                <button class="btn btn-sm" data-act="goto-grades" data-job="${esc(job.name)}">${ico('grades')}Grades</button>
                <button class="btn btn-sm" data-act="goto-locations" data-job="${esc(job.name)}">${ico('markers')}Locations</button>
                ${compact ? '' : `
                <button class="btn btn-sm btn-icon" title="Rename" data-act="rename-job" data-job="${esc(job.name)}">${ico('edit')}</button>
                <button class="btn btn-sm btn-icon" title="Duplicate" data-act="duplicate-job" data-job="${esc(job.name)}">${ico('copy')}</button>
                <button class="btn btn-sm btn-icon btn-danger" title="Delete" data-act="delete-job" data-job="${esc(job.name)}">${ico('trash')}</button>`}
            </div>
        </div>`;
    }

    function renderDashboard() {
        const stats = (state.data && state.data.stats) || {};
        const enabled = jobs().filter((job) => job.enabled).length;

        $('#topbar-actions').innerHTML = `
            <button class="btn" data-act="reload">${ico('refresh')}Reload</button>
            <button class="btn btn-primary" data-act="new-job">${ico('plus')}New job</button>`;
        $('#toolbar').innerHTML = '';

        const tiles = [
            { label: 'Jobs', value: stats.jobs || 0, hint: `${enabled} enabled`, icon: 'jobs' },
            { label: 'Grades', value: stats.grades || 0, hint: 'across all jobs', icon: 'grades' },
            { label: 'Locations', value: stats.locations || 0, hint: 'markers, zones and points', icon: 'markers' },
            { label: 'Stashes', value: stats.stashes || 0, hint: `via ${state.data.inventory}`, icon: 'stashes' },
            { label: 'Garages', value: stats.garages || 0, hint: 'with vehicle lists', icon: 'garages' },
            { label: 'Players', value: stats.players || 0, hint: 'online right now', icon: 'users' },
        ];

        $('#view').innerHTML = `
            <div class="grid cols-4">${tiles.map((tile) => `
                <div class="stat">
                    <div class="stat-top">
                        <div class="label">${esc(tile.label)}</div>
                        <div class="ico">${ico(tile.icon)}</div>
                    </div>
                    <div class="value">${esc(tile.value)}</div>
                    <div class="hint">${esc(tile.hint || '')}</div>
                </div>`).join('')}</div>

            <div class="section-label">Jobs</div>
            ${jobs().length
                ? `<div class="grid cols-3">${jobs().slice(0, 6).map((job) => jobCard(job, true)).join('')}</div>`
                : emptyState('No jobs yet', 'Create your first job and place its locations in the world.', 'jobs')}

            <div class="section-label">Environment</div>
            <div class="panel">
                <div class="panel-body">
                    <div class="card-meta" style="margin-top:0">
                        <span class="chip on">${ico('bolt')}${esc(state.data.framework)}</span>
                        <span class="chip">${ico('box')}${esc(state.data.inventory)}</span>
                        <span class="chip">${ico('target')}${esc((state.data.client || {}).target || 'none')}</span>
                        <span class="chip">${ico('database')}${esc(state.data.database)}</span>
                        <span class="chip ${state.data.oxlib ? 'green' : ''}">${ico('layers')}ox_lib ${state.data.oxlib ? 'loaded' : 'not loaded'}</span>
                    </div>
                    <p class="help" style="margin-top:14px">
                        Every change is written to MySQL and pushed to players live &mdash; no restart needed.
                    </p>
                </div>
            </div>`;
    }

    function emptyState(title, message, icon) {
        return `<div class="empty">
            <div class="empty-ico">${ico(icon || 'info')}</div>
            <strong>${esc(title)}</strong>
            <span>${esc(message)}</span>
        </div>`;
    }

    function renderJobs() {
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-job">${ico('plus')}New job</button>`;
        $('#toolbar').innerHTML = `
            ${searchBox('Search jobs...')}
            <span class="chip">${jobs().length} total</span>
            <span class="chip green">${jobs().filter((job) => job.enabled).length} enabled</span>`;

        const filter = state.jobFilter.toLowerCase();
        const list = jobs().filter((job) =>
            !filter || job.name.toLowerCase().includes(filter) || (job.label || '').toLowerCase().includes(filter));

        if (!list.length) {
            $('#view').innerHTML = emptyState('Nothing found', 'No job matches that search.', 'search');
            return;
        }

        $('#view').innerHTML = `<div class="grid cols-2">${list.map((job) => jobCard(job, false)).join('')}</div>`;
    }

    function renderGrades() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = jobs().length
            ? `<button class="btn btn-primary" data-act="edit-grades">${ico('edit')}Edit ladder</button>` : '';
        $('#toolbar').innerHTML = jobs().length ? jobScopeSelect() : '';

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job before building its rank ladder.', 'jobs');
            return;
        }

        const ladder = job.grades || [];
        const top = ladder[ladder.length - 1];

        const rows = ladder.map((grade) => `
            <tr>
                <td><span class="chip ${grade.is_boss ? 'on' : ''}">${esc(grade.grade)}</span></td>
                <td>
                    <div class="t-main">${esc(grade.label)}</div>
                    <div class="t-sub mono">${esc(grade.name)}</div>
                </td>
                <td class="mono">${money(grade.salary)}</td>
                <td>${grade.is_boss ? `<span class="chip green">${ico('star')}boss</span>` : ''}</td>
                <td>${(grade.permissions || []).map((permission) => `<span class="chip">${esc(permission)}</span>`).join(' ') || '<span class="help">none</span>'}</td>
            </tr>`).join('');

        $('#view').innerHTML = `
            <div class="grid cols-4" style="margin-bottom:18px">
                <div class="stat">
                    <div class="stat-top"><div class="label">Ranks</div><div class="ico">${ico('grades')}</div></div>
                    <div class="value">${ladder.length}</div>
                    <div class="hint">grade 0 to ${Math.max(ladder.length - 1, 0)}</div>
                </div>
                <div class="stat">
                    <div class="stat-top"><div class="label">Top rank</div><div class="ico">${ico('star')}</div></div>
                    <div class="value" style="font-size:20px">${esc(top ? top.label : '-')}</div>
                    <div class="hint">${top && top.is_boss ? 'has every boss permission' : 'not marked as boss'}</div>
                </div>
                <div class="stat">
                    <div class="stat-top"><div class="label">Top salary</div><div class="ico">${ico('money')}</div></div>
                    <div class="value">${money(top ? top.salary : 0)}</div>
                    <div class="hint">per pay cycle</div>
                </div>
                <div class="stat">
                    <div class="stat-top"><div class="label">Hired at</div><div class="ico">${ico('userPlus')}</div></div>
                    <div class="value">${esc(job.default_grade)}</div>
                    <div class="hint">default grade on hire</div>
                </div>
            </div>

            <div class="panel">
                <div class="panel-head">
                    <div>
                        <h3>${ico('grades')}${esc(job.label)}</h3>
                        <div class="sub">Reorder, rename and set permissions in the ladder editor</div>
                    </div>
                    <button class="btn btn-sm btn-primary" data-act="edit-grades">${ico('edit')}Edit ladder</button>
                </div>
                <table class="table">
                    <thead><tr><th style="width:60px">#</th><th>Rank</th><th style="width:120px">Salary</th><th style="width:90px">Boss</th><th>Permissions</th></tr></thead>
                    <tbody>${rows || '<tr><td colspan="5" class="help" style="padding:20px">No grades yet.</td></tr>'}</tbody>
                </table>
            </div>`;
    }

    const KIND_ICON = {
        duty: 'clock', boss: 'boss', management: 'boss', stash: 'stashes', garage: 'garages',
        vehicle_spawn: 'vehicles', vehicle_return: 'swap', clothing: 'shirt', shop: 'shop',
        armory: 'gun', crafting: 'craft', teleport: 'swap', custom: 'star',
    };

    function renderMarkers() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-location">${ico('plus')}New location</button>`;
        $('#toolbar').innerHTML = `
            ${jobs().length ? jobScopeSelect() : ''}
            <select class="select" style="max-width:220px" data-act="filter-kind">
                <option value="">All types</option>
                ${kindOptions().map((kind) => `<option value="${esc(kind.value)}" ${state.kindFilter === kind.value ? 'selected' : ''}>${esc(kind.label)}</option>`).join('')}
            </select>
            ${searchBox('Search locations...')}`;

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job before adding locations.', 'jobs');
            return;
        }

        const filter = state.jobFilter.toLowerCase();
        const list = (job.locations || []).filter((location) => {
            if (state.kindFilter && location.kind !== state.kindFilter) return false;
            if (!filter) return true;
            return (location.label || '').toLowerCase().includes(filter) || location.kind.includes(filter);
        });

        if (!list.length) {
            $('#view').innerHTML = emptyState(
                'No locations here yet',
                'Add one, pick its type, then press "Place in world" to drop it exactly where you are standing.',
                'markers');
            return;
        }

        $('#view').innerHTML = `
            <div class="panel">
                <div class="panel-head">
                    <div>
                        <h3>${ico('markers')}${esc(job.label)}</h3>
                        <div class="sub">${list.length} location${list.length === 1 ? '' : 's'}${state.kindFilter ? ` of type ${esc(state.kindFilter)}` : ''}</div>
                    </div>
                </div>
                <table class="table">
                    <thead>
                        <tr>
                            <th style="width:58px">ID</th><th style="width:170px">Type</th><th>Label</th>
                            <th style="width:190px">Coordinates</th><th>Access</th>
                            <th style="width:110px">Marker</th><th style="width:90px">Blip</th><th></th>
                        </tr>
                    </thead>
                    <tbody>${list.map((location) => {
                        const access = location.access || {};
                        return `
                        <tr>
                            <td class="mono">${esc(location.id)}</td>
                            <td><span class="chip">${ico(KIND_ICON[location.kind] || 'star')}${esc(location.kind)}</span></td>
                            <td>
                                <div class="t-main">${esc(location.label)}</div>
                                ${location.enabled ? '' : '<div class="t-sub"><span class="chip red">disabled</span></div>'}
                            </td>
                            <td class="mono">${num(location.coords.x).toFixed(1)}, ${num(location.coords.y).toFixed(1)}, ${num(location.coords.z).toFixed(1)}</td>
                            <td>
                                <span class="chip">grade ${esc(access.grade || 0)}</span>
                                ${access.duty ? `<span class="chip amber">${ico('clock')}duty</span>` : ''}
                                ${access.item ? `<span class="chip">${ico('box')}${esc(access.item)}</span>` : ''}
                            </td>
                            <td>${(location.marker || {}).enabled ? `<span class="chip on">type ${esc(location.marker.type)}</span>` : '<span class="help">off</span>'}</td>
                            <td>${(location.blip || {}).enabled ? `<span class="chip on">${ico('pin')}${esc(location.blip.sprite)}</span>` : '<span class="help">off</span>'}</td>
                            <td class="actions">
                                <button class="btn btn-sm btn-icon" title="Teleport here" data-act="tp-location" data-id="${esc(location.id)}">${ico('target')}</button>
                                <button class="btn btn-sm btn-primary" data-act="edit-location" data-id="${esc(location.id)}">${ico('edit')}Edit</button>
                                <button class="btn btn-sm btn-icon btn-danger" title="Delete" data-act="delete-location" data-id="${esc(location.id)}">${ico('trash')}</button>
                            </td>
                        </tr>`;
                    }).join('')}</tbody>
                </table>
            </div>`;
    }

    function renderBossMenus() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-boss">${ico('plus')}New boss menu</button>`;
        $('#toolbar').innerHTML = jobs().length ? jobScopeSelect() : '';

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job first.', 'jobs');
            return;
        }

        const list = job.boss || [];
        if (!list.length) {
            $('#view').innerHTML = emptyState(
                'No management office yet',
                'Add a boss menu, choose which features it exposes, then link it to a boss location.',
                'boss');
            return;
        }

        $('#view').innerHTML = `<div class="grid cols-2">${list.map((boss) => {
            const features = Object.keys(boss.features || {}).filter((key) => boss.features[key]);
            return `
            <div class="card accent hoverable"${jobAccent(job)}>
                <div class="card-head">
                    <div>
                        <div class="card-title">${ico('boss')}${esc(boss.label)}</div>
                        <div class="card-sub">#${esc(boss.id)} &middot; linked to location ${esc(boss.location_id || 'none')}</div>
                    </div>
                    <span class="chip">min grade ${esc(boss.required_grade)}</span>
                </div>
                <div class="card-meta">
                    ${features.length
                        ? features.map((feature) => `<span class="chip on">${esc(feature)}</span>`).join('')
                        : '<span class="help">no features enabled</span>'}
                </div>
                <div class="card-actions">
                    <button class="btn btn-sm btn-primary" data-act="edit-boss" data-id="${esc(boss.id)}">${ico('edit')}Edit</button>
                    <button class="btn btn-sm btn-icon btn-danger" title="Delete" data-act="delete-boss" data-id="${esc(boss.id)}">${ico('trash')}</button>
                </div>
            </div>`;
        }).join('')}</div>`;
    }

    function renderStashes() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-stash">${ico('plus')}New stash</button>`;
        $('#toolbar').innerHTML = jobs().length ? jobScopeSelect() : '';

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job first.', 'jobs');
            return;
        }

        const list = job.stashes || [];
        if (!list.length) {
            $('#view').innerHTML = emptyState(
                'No storage yet',
                'Add a stash, set its slots and weight, then link it to a stash location in the world.',
                'stashes');
            return;
        }

        $('#view').innerHTML = `
            <div class="panel">
                <div class="panel-head">
                    <div>
                        <h3>${ico('stashes')}${esc(job.label)}</h3>
                        <div class="sub">Served by ${esc(state.data.inventory)}</div>
                    </div>
                </div>
                <table class="table">
                    <thead>
                        <tr>
                            <th style="width:58px">ID</th><th>Stash</th><th style="width:150px">Type</th>
                            <th style="width:90px">Slots</th><th style="width:100px">Weight</th>
                            <th>Access</th><th style="width:90px">Location</th><th></th>
                        </tr>
                    </thead>
                    <tbody>${list.map((stash) => `
                        <tr>
                            <td class="mono">${esc(stash.id)}</td>
                            <td>
                                <div class="t-main">${esc(stash.label)}</div>
                                <div class="t-sub mono">${esc(stash.stash_id)}</div>
                            </td>
                            <td><span class="chip">${esc(stash.owner_type)}</span></td>
                            <td class="mono">${esc(stash.slots)}</td>
                            <td class="mono">${(num(stash.weight) / 1000).toFixed(0)} kg</td>
                            <td>
                                <span class="chip">grade ${esc(stash.required_grade)}</span>
                                ${stash.required_item ? `<span class="chip">${ico('box')}${esc(stash.required_item)}</span>` : ''}
                                ${stash.password ? `<span class="chip amber">${ico('shield')}code</span>` : ''}
                            </td>
                            <td class="mono">${esc(stash.location_id || '-')}</td>
                            <td class="actions">
                                <button class="btn btn-sm btn-primary" data-act="edit-stash" data-id="${esc(stash.id)}">${ico('edit')}Edit</button>
                                <button class="btn btn-sm btn-icon btn-danger" title="Delete" data-act="delete-stash" data-id="${esc(stash.id)}">${ico('trash')}</button>
                            </td>
                        </tr>`).join('')}</tbody>
                </table>
            </div>`;
    }

    function renderGarages() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-garage">${ico('plus')}New garage</button>`;
        $('#toolbar').innerHTML = jobs().length ? jobScopeSelect() : '';

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job first.', 'jobs');
            return;
        }

        const list = job.garages || [];
        if (!list.length) {
            $('#view').innerHTML = emptyState(
                'No garages yet',
                'Place a spawn point, add a return point, then fill the garage with vehicles.',
                'garages');
            return;
        }

        $('#view').innerHTML = `<div class="grid cols-2">${list.map((garage) => `
            <div class="card accent hoverable"${jobAccent(job)}>
                <div class="card-head">
                    <div>
                        <div class="card-title">${ico('garages')}${esc(garage.label)}</div>
                        <div class="card-sub">${esc(garage.name)} &middot; plate ${esc(garage.plate_prefix)}</div>
                    </div>
                    <span class="chip on">${ico('vehicles')}${(garage.vehicles || []).length}</span>
                </div>

                <div class="metrics">
                    <div class="metric"><b class="mono" style="font-size:12.5px">${num(garage.spawn.x).toFixed(1)}, ${num(garage.spawn.y).toFixed(1)}</b><span>Spawn</span></div>
                    <div class="metric"><b class="mono" style="font-size:12.5px">${garage.return_point ? `${num(garage.return_point.x).toFixed(1)}, ${num(garage.return_point.y).toFixed(1)}` : 'at garage'}</b><span>Return</span></div>
                    <div class="metric"><b>${num(garage.spawn_heading).toFixed(0)}&deg;</b><span>Heading</span></div>
                    <div class="metric"><b>${esc(garage.required_grade)}</b><span>Min grade</span></div>
                </div>

                <div class="card-actions">
                    <button class="btn btn-sm btn-primary" data-act="edit-garage" data-id="${esc(garage.id)}">${ico('edit')}Edit</button>
                    <button class="btn btn-sm" data-act="garage-vehicles" data-id="${esc(garage.id)}">${ico('vehicles')}Vehicles</button>
                    <button class="btn btn-sm btn-icon" title="Teleport to the spawn point" data-act="tp-coords" data-coords="${esc(JSON.stringify(garage.spawn))}">${ico('target')}</button>
                    <button class="btn btn-sm btn-icon btn-danger" title="Delete" data-act="delete-garage" data-id="${esc(garage.id)}">${ico('trash')}</button>
                </div>
            </div>`).join('')}</div>`;
    }

    function renderVehicles() {
        const job = scopedJob();
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="new-vehicle">${ico('plus')}Add vehicle</button>`;
        $('#toolbar').innerHTML = `
            ${jobs().length ? jobScopeSelect() : ''}
            ${searchBox('Search models...')}`;

        if (!job) {
            $('#view').innerHTML = emptyState('No jobs yet', 'Create a job first.', 'jobs');
            return;
        }

        const filter = state.jobFilter.toLowerCase();
        const rows = [];
        (job.garages || []).forEach((garage) => {
            (garage.vehicles || []).forEach((vehicle) => {
                if (filter && !String(vehicle.model).toLowerCase().includes(filter) && !String(vehicle.label).toLowerCase().includes(filter)) return;
                rows.push({ garage, vehicle });
            });
        });

        if (!rows.length) {
            $('#view').innerHTML = emptyState(
                'No vehicles yet',
                'Add vehicles to a garage and restrict each one to the ranks that may take it out.',
                'vehicles');
            return;
        }

        $('#view').innerHTML = `
            <div class="panel">
                <div class="panel-head">
                    <div>
                        <h3>${ico('vehicles')}${esc(job.label)}</h3>
                        <div class="sub">${rows.length} vehicle${rows.length === 1 ? '' : 's'} across ${(job.garages || []).length} garage${(job.garages || []).length === 1 ? '' : 's'}</div>
                    </div>
                </div>
                <table class="table">
                    <thead>
                        <tr>
                            <th>Vehicle</th><th style="width:180px">Garage</th><th style="width:140px">Category</th>
                            <th>Allowed ranks</th><th style="width:90px">Livery</th><th style="width:110px">Price</th><th></th>
                        </tr>
                    </thead>
                    <tbody>${rows.map(({ garage, vehicle }) => `
                        <tr>
                            <td>
                                <div class="t-main">${esc(vehicle.label)}</div>
                                <div class="t-sub mono">${esc(vehicle.model)}</div>
                            </td>
                            <td>${esc(garage.label)}</td>
                            <td><span class="chip">${esc(vehicle.category)}</span></td>
                            <td>${(vehicle.grades || []).length
                                ? (vehicle.grades || []).map((grade) => `<span class="chip on">${esc(grade)}</span>`).join('')
                                : `<span class="chip">grade ${esc(vehicle.min_grade)}+</span>`}</td>
                            <td class="mono">${num(vehicle.livery) >= 0 ? esc(vehicle.livery) : '-'}</td>
                            <td>${num(vehicle.price) > 0 ? `<span class="mono">${money(vehicle.price)}</span>` : '<span class="help">free</span>'}</td>
                            <td class="actions">
                                <button class="btn btn-sm btn-primary" data-act="edit-vehicle" data-id="${esc(vehicle.id)}" data-garage="${esc(garage.id)}">${ico('edit')}Edit</button>
                                <button class="btn btn-sm btn-icon btn-danger" title="Remove" data-act="delete-vehicle" data-id="${esc(vehicle.id)}">${ico('trash')}</button>
                            </td>
                        </tr>`).join('')}</tbody>
                </table>
            </div>`;
    }

    function renderSettings() {
        const settings = (state.data && state.data.settings) || {};
        $('#topbar-actions').innerHTML = `<button class="btn btn-primary" data-act="save-settings">${ico('save')}Save settings</button>`;
        $('#toolbar').innerHTML = `<span class="chip">${ico('database')}stored in nexora_settings</span>`;

        const groups = [
            {
                title: 'World',
                fields: [
                    { key: 'UseBlips', label: 'Blips', type: 'bool' },
                    { key: 'UseMarkers', label: 'Markers', type: 'bool' },
                    { key: 'UseTarget', label: 'Target systems', type: 'bool' },
                    { key: 'Use3DText', label: '3D labels', type: 'bool' },
                    { key: 'UseOxLib', label: 'Use ox_lib when present', type: 'bool' },
                    { key: 'UseOxLibZones', label: 'Prefer ox_lib zones', type: 'bool' },
                    { key: 'World.gridSize', label: 'Streaming grid size (m)', type: 'number' },
                    { key: 'World.scanInterval', label: 'Proximity scan interval (ms)', type: 'number' },
                    { key: 'World.maxDrawDistance', label: 'Max marker draw distance (m)', type: 'number' },
                    { key: 'Interaction.key', label: 'Interaction key (control id)', type: 'number' },
                    { key: 'Interaction.helpText', label: 'Show the native key prompt', type: 'bool' },
                ],
            },
            {
                title: 'Duty',
                fields: [
                    { key: 'Duty.enabled', label: 'Duty system', type: 'bool' },
                    { key: 'Duty.autoDutyZones', label: 'Auto clock in/out in duty zones', type: 'bool' },
                    { key: 'Duty.autoDutyOnJoin', label: 'Clock in on join', type: 'bool' },
                    { key: 'Duty.offDutyBlipHide', label: 'Hide own job blips while off duty', type: 'bool' },
                ],
            },
            {
                title: 'Salary',
                fields: [
                    { key: 'Salary.enabled', label: 'Pay salaries from this resource', type: 'bool' },
                    { key: 'Salary.interval', label: 'Interval (minutes)', type: 'number' },
                    { key: 'Salary.requireDuty', label: 'Only pay while on duty', type: 'bool' },
                    { key: 'Salary.source', label: 'Source (society / government)', type: 'text' },
                ],
            },
            {
                title: 'Garages',
                fields: [
                    { key: 'Garages.maxActivePerPlayer', label: 'Max job vehicles per player (0 = unlimited)', type: 'number' },
                    { key: 'Garages.deleteOnReturn', label: 'Delete on return', type: 'bool' },
                    { key: 'Garages.giveKeys', label: 'Give keys', type: 'bool' },
                    { key: 'Garages.warpIntoVehicle', label: 'Warp the player in', type: 'bool' },
                    { key: 'Garages.persistVehicles', label: 'Remember spawned vehicles', type: 'bool' },
                ],
            },
            {
                title: 'Security & debug',
                fields: [
                    { key: 'Security.validateDistance', label: 'Require the player to stand at a location', type: 'bool' },
                    { key: 'Security.logActions', label: 'Write an audit log', type: 'bool' },
                    { key: 'Debug', label: 'Verbose console logging', type: 'bool' },
                    { key: 'SeedExampleJobs', label: 'Seed example jobs on first start', type: 'bool' },
                ],
            },
        ];

        const groupIcon = {
            'World': 'markers', 'Duty': 'clock', 'Salary': 'money',
            'Garages': 'garages', 'Security & debug': 'shield',
        };

        $('#view').innerHTML = `
            <div id="settings-form" class="grid cols-2">${groups.map((group) => `
                <div class="panel">
                    <div class="panel-head"><h3>${ico(groupIcon[group.title] || 'settings')}${esc(group.title)}</h3></div>
                    <div class="panel-body" style="display:flex;flex-direction:column;gap:14px">
                        ${group.fields.map((field) => {
                            const value = settings[field.key];
                            if (field.type === 'bool') {
                                return `<div class="field inline">
                                    <label>${esc(field.label)}</label>
                                    <label class="switch"><input type="checkbox" data-setting="${esc(field.key)}" data-type="bool" ${value ? 'checked' : ''}><span class="track"></span></label>
                                </div>`;
                            }
                            return `<div class="field">
                                <label>${esc(field.label)}</label>
                                <input class="input" type="${field.type === 'number' ? 'number' : 'text'}" data-setting="${esc(field.key)}" data-type="${esc(field.type)}" value="${esc(value === undefined || value === null ? '' : value)}">
                            </div>`;
                        }).join('')}
                    </div>
                </div>`).join('')}
            </div>
            <p class="help" style="margin-top:16px">
                These values override <span class="mono">config.lua</span> at runtime and survive a restart.
                Anything not listed here is still edited in the config file.
            </p>`;
    }

    /* =====================================================================
       EDITORS
       ===================================================================== */

    function jobSchema(isNew) {
        return [
            {
                row: 2,
                fields: [
                    { name: 'name', label: 'Job name (unique, a-z/0-9/_)', type: 'text', readonly: !isNew, placeholder: 'police', maxlength: 50 },
                    { name: 'label', label: 'Display name', type: 'text', placeholder: 'Los Santos Police Department' },
                ],
            },
            {
                row: 2,
                fields: [
                    { name: 'type', label: 'Job type', type: 'select', options: () => (definitions().jobTypes || []).map((t) => ({ value: t.value, label: t.label })) },
                    { name: 'default_grade', label: 'Default grade on hire', type: 'number', min: 0, default: 0 },
                ],
            },
            {
                row: 3,
                fields: [
                    { name: 'enabled', label: 'Enabled', type: 'checkbox', on: 'Job is active' },
                    { name: 'whitelisted', label: 'Whitelisted', type: 'checkbox', on: 'Boss approval only' },
                    { name: 'use_duty', label: 'Duty', type: 'checkbox', on: 'Use the duty system' },
                ],
            },
            {
                group: 'Off duty restrictions',
                fields: [
                    {
                        row: 3,
                        fields: [
                            { name: 'offduty.blockVehicles', label: 'Vehicles', type: 'checkbox', on: 'Blocked off duty' },
                            { name: 'offduty.blockStash', label: 'Stashes', type: 'checkbox', on: 'Blocked off duty' },
                            { name: 'offduty.blockBoss', label: 'Boss menu', type: 'checkbox', on: 'Blocked off duty' },
                        ],
                    },
                    {
                        row: 3,
                        fields: [
                            { name: 'offduty.blockShops', label: 'Shops', type: 'checkbox', on: 'Blocked off duty' },
                            { name: 'offduty.blockCrafting', label: 'Crafting', type: 'checkbox', on: 'Blocked off duty' },
                            { name: 'offduty.blockSalary', label: 'Salary', type: 'checkbox', on: 'No pay off duty' },
                        ],
                    },
                ],
            },
            {
                group: 'Presentation',
                fields: [
                    { name: 'meta.description', label: 'Description', type: 'textarea', rows: 2 },
                    {
                        row: 2,
                        fields: [
                            { name: 'meta.color', label: 'Accent colour (hex)', type: 'text', placeholder: '#3b82f6' },
                            { name: 'meta.icon', label: 'Icon class', type: 'text', placeholder: 'fa-solid fa-shield-halved' },
                        ],
                    },
                ],
            },
        ];
    }

    function editJob(name) {
        const isNew = !name;
        const job = name ? jobByName(name) : {
            name: '', label: '', type: 'none', enabled: true, whitelisted: false, use_duty: true, default_grade: 0,
            offduty: { blockVehicles: true, blockStash: false, blockBoss: false, blockShops: false, blockCrafting: true, blockSalary: true },
            meta: {},
            grades: [{ grade: 0, name: 'employee', label: 'Employee', salary: 50, is_boss: false, permissions: [] },
                     { grade: 1, name: 'boss', label: 'Boss', salary: 100, is_boss: true, permissions: [] }],
        };

        openDrawer({
            title: isNew ? 'New job' : `Edit ${job.label}`,
            subtitle: isNew ? 'A new job starts with an Employee and a Boss grade' : job.name,
            schema: jobSchema(isNew),
            values: job,
            onSave: async (payload) => {
                payload.name = slug(payload.name || job.name);
                if (!payload.name || payload.name.length < 2) {
                    toast('The job name needs at least 2 characters (a-z, 0-9, _).', 'error');
                    return false;
                }
                if (!payload.label) {
                    toast('Give the job a display name.', 'error');
                    return false;
                }
                if (isNew) payload.grades = job.grades;

                const result = await request('creator:saveJob', { job: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast(isNew ? 'Job created.' : 'Job updated.', 'success');
                state.jobScope = payload.name;
                return true;
            },
        });
    }

    function editGrades(name) {
        const job = jobByName(name) || scopedJob();
        if (!job) return;

        const schema = [
            {
                html: () => `<div class="help" style="margin-bottom:10px">
                    Grades are renumbered from 0 in the order shown. Grade 0 is the lowest rank.
                    Mark the top rank as <b>boss</b> so it gets every boss menu permission.
                </div>`,
            },
            {
                name: 'grades',
                type: 'list',
                itemLabel: 'grade',
                columns: [
                    { name: 'label', label: 'Label', type: 'text', width: '1.3fr' },
                    { name: 'name', label: 'Internal name', type: 'text', width: '1fr' },
                    { name: 'salary', label: 'Salary', type: 'number', width: '0.7fr', min: 0, default: 0 },
                    { name: 'is_boss', label: 'Boss', type: 'checkbox', width: '0.6fr', on: '' },
                    { name: 'permissions', label: 'Permissions', type: 'multi', width: '2.4fr', options: () => (definitions().bossPermissions || []).map((p) => ({ value: p.value, label: p.label })) },
                ],
            },
        ];

        openDrawer({
            title: `Grades - ${job.label}`,
            subtitle: 'Drag-free ordering: use the up arrow to move a grade',
            schema,
            values: { grades: JSON.parse(JSON.stringify(job.grades || [])) },
            onSave: async (payload) => {
                const grades = (payload.grades || []).filter((grade) => grade.label);
                if (!grades.length) {
                    toast('A job needs at least one grade.', 'error');
                    return false;
                }
                grades.forEach((grade, index) => { grade.grade = index; });

                const result = await request('creator:saveGrades', { name: job.name, grades });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast('Grades saved.', 'success');
                return true;
            },
        });
    }

    function kindDataSchema(kind, job) {
        switch (kind) {
            case 'teleport':
                return [{
                    group: 'Teleport destination',
                    fields: [
                        { name: 'data.target', label: 'Destination', type: 'coords', headingName: 'data.target_heading' },
                        { name: 'data.two_way', label: 'Two way', type: 'checkbox', on: 'Also create the return interaction' },
                    ],
                }];
            case 'duty':
                return [{
                    group: 'Duty point',
                    fields: [{ name: 'data.auto', label: 'Automatic', type: 'checkbox', on: 'Toggle duty by walking into the zone' }],
                }];
            case 'clothing':
                return [{
                    group: 'Outfits',
                    fields: [
                        { name: 'data.mode', label: 'Mode', type: 'select', options: [{ value: 'menu', label: 'Clothing menu only' }, { value: 'outfits', label: 'Job outfits only' }, { value: 'both', label: 'Both' }] },
                        {
                            name: 'data.outfits', type: 'list', itemLabel: 'outfit',
                            columns: [
                                { name: 'name', label: 'Outfit name', type: 'text', width: '2fr' },
                                { name: 'grade', label: 'Min grade', type: 'number', width: '1fr', min: 0, default: 0 },
                            ],
                        },
                    ],
                }];
            case 'shop':
            case 'armory':
                return [{
                    group: kind === 'armory' ? 'Armory items' : 'Shop items',
                    fields: [
                        { name: 'data.free', label: 'Free', type: 'checkbox', on: 'Items cost nothing' },
                        {
                            name: 'data.items', type: 'list', itemLabel: 'item',
                            columns: [
                                { name: 'name', label: 'Item name', type: 'text', width: '1.4fr' },
                                { name: 'label', label: 'Label', type: 'text', width: '1.4fr' },
                                { name: 'price', label: 'Price', type: 'number', width: '0.8fr', min: 0, default: 0 },
                                { name: 'count', label: 'Max qty', type: 'number', width: '0.8fr', min: 1, default: 1 },
                                { name: 'grade', label: 'Grade', type: 'number', width: '0.7fr', min: 0, default: 0 },
                            ],
                        },
                    ],
                }];
            case 'crafting':
                return [{
                    group: 'Recipes',
                    fields: [
                        {
                            name: 'data.recipes', type: 'list', itemLabel: 'recipe',
                            columns: [
                                { name: 'item', label: 'Result item', type: 'text', width: '1.2fr' },
                                { name: 'label', label: 'Label', type: 'text', width: '1.2fr' },
                                { name: 'amount', label: 'Qty', type: 'number', width: '0.6fr', min: 1, default: 1 },
                                { name: 'duration', label: 'Duration (ms)', type: 'number', width: '1fr', min: 500, default: 5000 },
                                { name: 'grade', label: 'Grade', type: 'number', width: '0.6fr', min: 0, default: 0 },
                            ],
                        },
                        {
                            html: () => `<div class="help">Ingredients use the compact form <span class="mono">item:amount, item:amount</span> on each recipe row below.</div>`,
                        },
                        {
                            name: 'data.ingredientsText', label: 'Ingredients per recipe (one line per recipe)', type: 'textarea', rows: 4,
                            help: 'Line 1 belongs to recipe 1. Example: metalscrap:5, plastic:3',
                        },
                    ],
                }];
            case 'custom':
                return [{
                    group: 'Custom interaction',
                    fields: [
                        { name: 'data.event', label: 'Event name', type: 'text', placeholder: 'myresource:doSomething' },
                        { name: 'data.server_event', label: 'Server event', type: 'checkbox', on: 'Trigger it on the server instead of the client' },
                    ],
                }];
            case 'stash':
                return [{
                    html: () => `<div class="help">A stash record is created automatically for this location. Tune slots, weight and the access code in the <b>Stashes</b> section.</div>`,
                }];
            case 'boss':
                return [{
                    html: () => `<div class="help">A boss menu record is created automatically for this location. Pick which features it exposes in the <b>Boss Menus</b> section.</div>`,
                }];
            case 'garage':
            case 'vehicle_spawn':
            case 'vehicle_return':
                return [{
                    group: 'Garage link',
                    fields: [{
                        name: 'data.garage', label: 'Garage', type: 'select',
                        options: () => [{ value: '', label: 'First garage of this job' }].concat(((job && job.garages) || []).map((garage) => ({ value: garage.name, label: garage.label }))),
                    }],
                }];
            default:
                return [];
        }
    }

    function serialiseIngredients(recipes) {
        return (recipes || []).map((recipe) =>
            (recipe.ingredients || []).map((ingredient) => `${ingredient.item}:${ingredient.amount}`).join(', ')).join('\n');
    }

    function parseIngredients(text, recipes) {
        const lines = String(text || '').split(/\r?\n/);
        (recipes || []).forEach((recipe, index) => {
            const line = lines[index] || '';
            recipe.ingredients = line.split(',').map((part) => {
                const [item, amount] = part.split(':').map((value) => String(value || '').trim());
                if (!item) return null;
                return { item, amount: Math.max(1, parseInt(amount, 10) || 1) };
            }).filter(Boolean);
        });
        return recipes;
    }

    function editLocation(id) {
        const job = scopedJob();
        if (!job) return;

        const isNew = !id;
        const existing = isNew ? null : (job.locations || []).find((location) => String(location.id) === String(id));
        const defaults = definitions().defaults || {};

        const values = existing ? JSON.parse(JSON.stringify(existing)) : {
            job_name: job.name,
            kind: 'duty',
            label: '',
            coords: { x: 0, y: 0, z: 0 },
            heading: 0,
            marker: JSON.parse(JSON.stringify(defaults.marker || {})),
            blip: JSON.parse(JSON.stringify(defaults.blip || {})),
            access: JSON.parse(JSON.stringify(defaults.access || {})),
            data: {},
            enabled: true,
        };

        if (values.kind === 'crafting') {
            values.data = values.data || {};
            values.data.ingredientsText = serialiseIngredients(values.data.recipes);
        }

        const kind = values.kind;

        const schema = [
            {
                row: 2,
                fields: [
                    { name: 'kind', label: 'Location type', type: 'select', options: kindOptions() },
                    { name: 'label', label: 'Label', type: 'text', placeholder: 'Clock in / out' },
                ],
            },
            { name: 'enabled', label: 'Enabled', type: 'checkbox', on: 'Active in the world' },
            {
                group: 'Position',
                fields: [{ name: 'coords', label: 'Coordinates', type: 'coords', headingName: 'heading' }],
            },
            accessGroup(job),
            markerGroup(),
            blipGroup(),
            ...kindDataSchema(kind, job),
        ];

        openDrawer({
            title: isNew ? 'New location' : `Edit location #${id}`,
            subtitle: `${job.label} - changing the type reopens the editor with the matching options`,
            schema,
            values,
            saveLabel: isNew ? 'Create' : 'Save',
            footLeft: isNew ? '' : `<button class="btn btn-sm" data-act="tp-location" data-id="${esc(id)}">Teleport here</button>`,
            onSave: async (payload) => {
                payload.job_name = job.name;
                if (!isNew) payload.id = existing.id;

                if (payload.kind === 'crafting' && payload.data) {
                    payload.data.recipes = parseIngredients(payload.data.ingredientsText, payload.data.recipes || []);
                    delete payload.data.ingredientsText;
                }
                if (payload.access && payload.access.permission === '') delete payload.access.permission;
                if (payload.access && payload.access.item === '') delete payload.access.item;

                const coords = payload.coords || {};
                if (!num(coords.x) && !num(coords.y) && !num(coords.z)) {
                    toast('Set the coordinates first - use "Use my position" or "Place in world".', 'error');
                    return false;
                }

                const result = await request('creator:saveLocation', { location: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast(isNew ? 'Location created.' : 'Location saved.', 'success');
                return true;
            },
        });

        // Changing the type rebuilds the editor so kind specific fields appear.
        bindKindChange(job, isNew, existing);
    }

    function bindKindChange(job, isNew, existing) {
        const kindSelect = $('#drawer-form [data-path="kind"]');
        if (!kindSelect) return;
        kindSelect.addEventListener('change', () => {
            const current = readForm($('#drawer-form'));
            current.kind = kindSelect.value;
            if (!isNew && existing) current.id = existing.id;
            state.drawer.values = current;

            const newSchema = [
                { row: 2, fields: [
                    { name: 'kind', label: 'Location type', type: 'select', options: kindOptions() },
                    { name: 'label', label: 'Label', type: 'text' },
                ] },
                { name: 'enabled', label: 'Enabled', type: 'checkbox', on: 'Active in the world' },
                { group: 'Position', fields: [{ name: 'coords', label: 'Coordinates', type: 'coords', headingName: 'heading' }] },
                accessGroup(job),
                markerGroup(),
                blipGroup(),
                ...kindDataSchema(kindSelect.value, job),
            ];
            state.drawer.schema = newSchema;
            renderDrawerBody(newSchema, current);
            bindKindChange(job, isNew, existing);
        }, { once: true });
    }

    function editStash(id) {
        const job = scopedJob();
        if (!job) return;

        const isNew = !id;
        const existing = isNew ? null : (job.stashes || []).find((stash) => String(stash.id) === String(id));

        const values = existing ? JSON.parse(JSON.stringify(existing)) : {
            job_name: job.name, label: '', stash_id: '', slots: 50, weight: 100000,
            access_distance: 2.0, owner_type: 'job', required_grade: 0, location_id: '',
        };

        const schema = [
            {
                row: 2,
                fields: [
                    { name: 'label', label: 'Label', type: 'text', placeholder: 'Evidence Locker' },
                    { name: 'stash_id', label: 'Stash id (leave empty to generate)', type: 'text', placeholder: 'police_evidence' },
                ],
            },
            {
                row: 2,
                fields: [
                    { name: 'owner_type', label: 'Stash type', type: 'select', options: () => (definitions().stashTypes || []).map((t) => ({ value: t.value, label: t.label })) },
                    { name: 'location_id', label: 'Linked location', type: 'select', numeric: true, options: () => locationOptions(job, ['stash']) },
                ],
            },
            {
                row: 3,
                fields: [
                    { name: 'slots', label: 'Slots', type: 'number', min: 1, max: 500, default: 50 },
                    { name: 'weight', label: 'Max weight (grams)', type: 'number', min: 1000, step: 1000, default: 100000 },
                    { name: 'access_distance', label: 'Access distance (m)', type: 'number', step: 0.1, min: 0.5, max: 6, default: 2 },
                ],
            },
            {
                group: 'Access',
                fields: [
                    {
                        row: 3,
                        fields: [
                            { name: 'required_grade', label: 'Minimum grade', type: 'select', numeric: true, options: () => gradeOptions(job) },
                            { name: 'required_item', label: 'Required item', type: 'text', placeholder: 'optional' },
                            { name: 'required_permission', label: 'Required permission', type: 'select', options: () => [{ value: '', label: 'None' }].concat((definitions().bossPermissions || []).map((p) => ({ value: p.value, label: p.label }))) },
                        ],
                    },
                    { name: 'password', label: 'Access code (optional)', type: 'text', placeholder: 'leave empty for no code' },
                ],
            },
        ];

        openDrawer({
            title: isNew ? 'New stash' : `Edit ${existing.label}`,
            subtitle: job.label,
            schema,
            values,
            onSave: async (payload) => {
                payload.job_name = job.name;
                if (!isNew) payload.id = existing.id;
                if (!payload.label) {
                    toast('Give the stash a label.', 'error');
                    return false;
                }
                if (payload.location_id === '' || payload.location_id === null) delete payload.location_id;
                if (!payload.password) delete payload.password;
                if (!payload.required_item) delete payload.required_item;
                if (!payload.required_permission) delete payload.required_permission;

                const result = await request('creator:saveStash', { stash: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast('Stash saved.', 'success');
                return true;
            },
        });
    }

    function editGarage(id) {
        const job = scopedJob();
        if (!job) return;

        const isNew = !id;
        const existing = isNew ? null : (job.garages || []).find((garage) => String(garage.id) === String(id));

        const values = existing ? JSON.parse(JSON.stringify(existing)) : {
            job_name: job.name, name: '', label: '',
            spawn: { x: 0, y: 0, z: 0 }, spawn_heading: 0,
            return_point: null, return_heading: 0,
            required_grade: 0, plate_prefix: 'JOB',
            settings: { warp: true, keys: true, fuel: 100, categories: true },
        };

        const schema = [
            {
                row: 2,
                fields: [
                    { name: 'label', label: 'Label', type: 'text', placeholder: 'Mission Row Motor Pool' },
                    { name: 'name', label: 'Internal name', type: 'text', placeholder: 'mission_row' },
                ],
            },
            {
                row: 2,
                fields: [
                    { name: 'required_grade', label: 'Minimum grade', type: 'select', numeric: true, options: () => gradeOptions(job) },
                    { name: 'plate_prefix', label: 'Plate prefix', type: 'text', maxlength: 6, placeholder: 'LSPD' },
                ],
            },
            { name: 'location_id', label: 'Linked location', type: 'select', numeric: true, options: () => locationOptions(job, ['garage', 'vehicle_spawn']) },
            { group: 'Spawn point', fields: [{ name: 'spawn', label: 'Where vehicles appear', type: 'coords', headingName: 'spawn_heading' }] },
            { group: 'Return point', fields: [{ name: 'return_point', label: 'Where vehicles are returned (optional)', type: 'coords', headingName: 'return_heading' }] },
            {
                group: 'Behaviour',
                fields: [
                    {
                        row: 2,
                        fields: [
                            { name: 'settings.warp', label: 'Warp', type: 'checkbox', on: 'Put the player in the driver seat' },
                            { name: 'settings.keys', label: 'Keys', type: 'checkbox', on: 'Hand over the keys' },
                        ],
                    },
                    {
                        row: 2,
                        fields: [
                            { name: 'settings.fuel', label: 'Fuel level', type: 'number', min: 0, max: 100, default: 100 },
                            { name: 'settings.categories', label: 'Categories', type: 'checkbox', on: 'Group the vehicle list by category' },
                        ],
                    },
                ],
            },
        ];

        openDrawer({
            title: isNew ? 'New garage' : `Edit ${existing.label}`,
            subtitle: job.label,
            schema,
            values,
            onSave: async (payload) => {
                payload.job_name = job.name;
                if (!isNew) payload.id = existing.id;
                payload.name = slug(payload.name || payload.label);

                if (!payload.label || !payload.name) {
                    toast('A garage needs a label and an internal name.', 'error');
                    return false;
                }
                const spawn = payload.spawn || {};
                if (!num(spawn.x) && !num(spawn.y) && !num(spawn.z)) {
                    toast('Set the spawn point first.', 'error');
                    return false;
                }
                const returnPoint = payload.return_point || {};
                if (!num(returnPoint.x) && !num(returnPoint.y) && !num(returnPoint.z)) {
                    payload.return_point = null;
                }
                if (payload.location_id === '' || payload.location_id === null) delete payload.location_id;

                const result = await request('creator:saveGarage', { garage: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast('Garage saved.', 'success');
                return true;
            },
        });
    }

    function editVehicle(vehicleId, garageId) {
        const job = scopedJob();
        if (!job) return;

        const garages = job.garages || [];
        if (!garages.length) {
            toast('Create a garage first.', 'error');
            return;
        }

        let existing = null;
        garages.forEach((garage) => {
            (garage.vehicles || []).forEach((vehicle) => {
                if (String(vehicle.id) === String(vehicleId)) existing = { ...vehicle, garage_id: garage.id };
            });
        });

        const values = existing || {
            garage_id: garageId || garages[0].id,
            model: '', label: '', category: 'patrol', min_grade: 0, grades: [], livery: -1, price: 0,
            colors: {}, extras: {},
        };

        const schema = [
            {
                row: 2,
                fields: [
                    { name: 'model', label: 'Spawn name', type: 'text', placeholder: 'police3' },
                    { name: 'label', label: 'Display name', type: 'text', placeholder: 'Interceptor' },
                ],
            },
            {
                row: 3,
                fields: [
                    { name: 'garage_id', label: 'Garage', type: 'select', numeric: true, options: () => garages.map((garage) => ({ value: garage.id, label: garage.label })) },
                    { name: 'category', label: 'Category', type: 'select', options: () => (definitions().vehicleCategories || []).map((c) => ({ value: c, label: c })) },
                    { name: 'price', label: 'Price (0 = free)', type: 'number', min: 0, default: 0 },
                ],
            },
            {
                group: 'Grade access',
                fields: [
                    { name: 'min_grade', label: 'Minimum grade', type: 'select', numeric: true, options: () => gradeOptions(job) },
                    {
                        name: 'grades', label: 'Or allow only these exact grades', type: 'multi', numeric: true,
                        options: () => gradeOptions(job),
                        help: 'Leave all unticked to use the minimum grade instead.',
                    },
                ],
            },
            {
                group: 'Appearance',
                fields: [
                    {
                        row: 3,
                        fields: [
                            { name: 'livery', label: 'Livery (-1 = default)', type: 'number', min: -1, max: 64, default: -1 },
                            { name: 'colors.primary', label: 'Primary colour id', type: 'number', min: 0, max: 160 },
                            { name: 'colors.secondary', label: 'Secondary colour id', type: 'number', min: 0, max: 160 },
                        ],
                    },
                    {
                        name: 'extrasText', label: 'Extras', type: 'text', placeholder: '1,3,5 (extras to switch on)',
                        help: 'Comma separated extra ids. Everything else stays off.',
                    },
                ],
            },
        ];

        if (existing && existing.extras) {
            values.extrasText = Object.keys(existing.extras).filter((key) => existing.extras[key]).join(',');
        }

        openDrawer({
            title: existing ? `Edit ${existing.label}` : 'Add vehicle',
            subtitle: job.label,
            schema,
            values,
            onSave: async (payload) => {
                if (existing) payload.id = existing.id;
                payload.model = slug(payload.model);
                if (!payload.model) {
                    toast('Enter the vehicle spawn name.', 'error');
                    return false;
                }
                if (!payload.label) payload.label = payload.model;

                payload.extras = {};
                String(payload.extrasText || '').split(',').forEach((part) => {
                    const id = parseInt(String(part).trim(), 10);
                    if (id >= 1 && id <= 20) payload.extras[String(id)] = true;
                });
                delete payload.extrasText;

                const result = await request('creator:saveVehicle', { vehicle: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast('Vehicle saved.', 'success');
                return true;
            },
        });
    }

    function editBoss(id) {
        const job = scopedJob();
        if (!job) return;

        const isNew = !id;
        const existing = isNew ? null : (job.boss || []).find((boss) => String(boss.id) === String(id));

        const featureDefaults = {};
        (definitions().bossFeatures || []).forEach((feature) => { featureDefaults[feature.value] = feature.default; });

        const values = existing ? JSON.parse(JSON.stringify(existing)) : {
            job_name: job.name, label: 'Boss Menu', required_grade: 0, location_id: '', features: featureDefaults,
        };

        const schema = [
            {
                row: 2,
                fields: [
                    { name: 'label', label: 'Label', type: 'text', placeholder: 'Chief Office' },
                    { name: 'required_grade', label: 'Minimum grade', type: 'select', numeric: true, options: () => gradeOptions(job) },
                ],
            },
            { name: 'location_id', label: 'Linked location', type: 'select', numeric: true, options: () => locationOptions(job, ['boss', 'management']) },
            {
                group: 'Features',
                fields: (definitions().bossFeatures || []).map((feature) => ({
                    name: `features.${feature.value}`, label: feature.label, type: 'checkbox', on: 'Enabled',
                })),
            },
        ];

        openDrawer({
            title: isNew ? 'New boss menu' : `Edit ${existing.label}`,
            subtitle: job.label,
            schema,
            values,
            onSave: async (payload) => {
                payload.job_name = job.name;
                if (!isNew) payload.id = existing.id;
                if (payload.location_id === '' || payload.location_id === null) delete payload.location_id;

                const result = await request('creator:saveBossMenu', { boss: payload });
                if (!result.ok) {
                    toast(result.error, 'error', 'Could not save');
                    return false;
                }
                toast('Boss menu saved.', 'success');
                return true;
            },
        });
    }

    /* =====================================================================
       ACTIONS
       ===================================================================== */

    async function refresh() {
        const result = await request('creator:open', {});
        if (!result.ok) {
            toast(result.error, 'error', 'Could not refresh');
            return;
        }
        const client = state.data && state.data.client;
        state.data = result.data;
        if (client) state.data.client = client;
        render();
    }

    async function handleAction(action, element) {
        const job = scopedJob();

        switch (action) {
            case 'reload': {
                const result = await request('creator:reload', {});
                if (result.ok) { toast('Reloaded from the database.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }
            case 'new-job': editJob(null); break;
            case 'edit-job': editJob(element.dataset.job); break;
            case 'goto-grades':
                state.jobScope = element.dataset.job; state.section = 'grades'; render(); break;
            case 'goto-locations':
                state.jobScope = element.dataset.job; state.section = 'markers'; render(); break;
            case 'edit-grades': editGrades(element.dataset.job || (job && job.name)); break;

            case 'toggle-job': {
                const result = await request('creator:toggleJob', { name: element.dataset.job, enabled: element.checked });
                if (result.ok) { toast(element.checked ? 'Job enabled.' : 'Job disabled.', 'success'); await refresh(); }
                else { toast(result.error, 'error'); element.checked = !element.checked; }
                break;
            }
            case 'rename-job': {
                const current = element.dataset.job;
                const value = await promptDialog('Rename job', 'New job name (a-z, 0-9, _)', current);
                if (!value) break;
                const result = await request('creator:renameJob', { name: current, newName: slug(value) });
                if (result.ok) { toast('Job renamed.', 'success'); state.jobScope = slug(value); await refresh(); }
                else toast(result.error, 'error');
                break;
            }
            case 'duplicate-job': {
                const current = element.dataset.job;
                const value = await promptDialog('Duplicate job', 'Name for the copy', `${current}_copy`);
                if (!value) break;
                const result = await request('creator:duplicateJob', { name: current, newName: slug(value) });
                if (result.ok) { toast('Job duplicated (disabled until you enable it).', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }
            case 'delete-job': {
                const name = element.dataset.job;
                const ok = await confirmDialog('Delete this job?',
                    `"${name}" and every grade, location, stash, garage and boss menu that belongs to it will be removed. This cannot be undone.`, 'Delete job');
                if (!ok) break;
                const result = await request('creator:deleteJob', { name });
                if (result.ok) { toast('Job deleted.', 'success'); state.jobScope = ''; await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'new-location': editLocation(null); break;
            case 'edit-location': editLocation(element.dataset.id); break;
            case 'delete-location': {
                const ok = await confirmDialog('Delete this location?', 'The marker, blip and interaction will be removed.', 'Delete');
                if (!ok) break;
                const result = await request('creator:deleteLocation', { id: parseInt(element.dataset.id, 10) });
                if (result.ok) { toast('Location deleted.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }
            case 'tp-location': {
                const location = (job && (job.locations || []).find((entry) => String(entry.id) === String(element.dataset.id)));
                if (!location) break;
                await nui('creator:teleport', { coords: location.coords, heading: location.heading });
                break;
            }
            case 'tp-coords': {
                try {
                    const coords = JSON.parse(element.dataset.coords);
                    await nui('creator:teleport', { coords });
                } catch (e) { /* ignore */ }
                break;
            }

            case 'new-stash': editStash(null); break;
            case 'edit-stash': editStash(element.dataset.id); break;
            case 'delete-stash': {
                const ok = await confirmDialog('Delete this stash?', 'Items already inside stay in your inventory system.', 'Delete');
                if (!ok) break;
                const result = await request('creator:deleteStash', { id: parseInt(element.dataset.id, 10) });
                if (result.ok) { toast('Stash deleted.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'new-garage': editGarage(null); break;
            case 'edit-garage': editGarage(element.dataset.id); break;
            case 'garage-vehicles':
                state.section = 'vehicles'; render(); break;
            case 'delete-garage': {
                const ok = await confirmDialog('Delete this garage?', 'Its vehicle list will be removed too.', 'Delete');
                if (!ok) break;
                const result = await request('creator:deleteGarage', { id: parseInt(element.dataset.id, 10) });
                if (result.ok) { toast('Garage deleted.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'new-vehicle': editVehicle(null, null); break;
            case 'edit-vehicle': editVehicle(element.dataset.id, element.dataset.garage); break;
            case 'delete-vehicle': {
                const ok = await confirmDialog('Remove this vehicle?', 'Employees will no longer be able to take it out.', 'Remove');
                if (!ok) break;
                const result = await request('creator:deleteVehicle', { id: parseInt(element.dataset.id, 10) });
                if (result.ok) { toast('Vehicle removed.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'new-boss': editBoss(null); break;
            case 'edit-boss': editBoss(element.dataset.id); break;
            case 'delete-boss': {
                const ok = await confirmDialog('Delete this boss menu?', 'The management office will stop working.', 'Delete');
                if (!ok) break;
                const result = await request('creator:deleteBossMenu', { id: parseInt(element.dataset.id, 10) });
                if (result.ok) { toast('Boss menu deleted.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'save-settings': {
                const settings = {};
                $$('[data-setting]').forEach((input) => {
                    const key = input.dataset.setting;
                    if (input.dataset.type === 'bool') settings[key] = input.checked;
                    else if (input.dataset.type === 'number') settings[key] = num(input.value, 0);
                    else settings[key] = input.value;
                });
                const result = await request('creator:saveSettings', { settings });
                if (result.ok) { toast('Settings saved.', 'success'); await refresh(); }
                else toast(result.error, 'error');
                break;
            }

            case 'use-position': {
                const response = await nui('creator:getPosition', {});
                if (!response || !response.ok) break;
                applyCoords(element.dataset.target, element.dataset.heading, response.data.coords, response.data.heading);
                toast('Position captured.', 'success');
                break;
            }
            case 'place-world': {
                const form = $('#drawer-form');
                const values = readForm(form);
                state.placementToken += 1;
                const token = state.placementToken;
                state.placementTarget = { coords: element.dataset.target, heading: element.dataset.heading };

                await nui('creator:placement', {
                    token,
                    label: values.label || 'Place location',
                    radius: (values.marker && values.marker.interactDistance) || 1.8,
                    marker: values.marker,
                    blip: values.blip,
                });
                break;
            }
            case 'preview-blip': {
                const values = readForm($('#drawer-form'));
                await nui('creator:previewBlip', { blip: values.blip, coords: values.coords });
                toast('Blip preview placed for 12 seconds.', 'inform');
                break;
            }
            default: break;
        }
    }

    function applyCoords(coordsPath, headingPath, coords, heading) {
        const form = $('#drawer-form');
        if (!form) return;

        ['x', 'y', 'z'].forEach((axis) => {
            const input = $(`[data-path="${coordsPath}.${axis}"]`, form);
            if (input) input.value = coords[axis];
        });
        if (headingPath) {
            const input = $(`[data-path="${headingPath}"]`, form);
            if (input && heading !== undefined) input.value = heading;
        }
    }

    /* =====================================================================
       EVENT WIRING
       ===================================================================== */

    document.addEventListener('click', (event) => {
        const navItem = event.target.closest('[data-section]');
        if (navItem) {
            state.section = navItem.dataset.section;
            state.jobFilter = '';
            render();
            return;
        }

        if (event.target.closest('[data-close-drawer]')) {
            closeDrawer();
            return;
        }

        const drawerTab = event.target.closest('[data-drawer-tab]');
        if (drawerTab) {
            const index = drawerTab.dataset.drawerTab;
            $$('.drawer-tab').forEach((tab) => tab.classList.toggle('active', tab === drawerTab));
            $$('[data-pane]').forEach((pane) => pane.classList.toggle('hidden', pane.dataset.pane !== index));
            $('#drawer-body').scrollTop = 0;
            refreshPreviews();
            return;
        }

        // list rows
        const listButton = event.target.closest('[data-act="list-add"], [data-act="list-del"], [data-act="list-up"]');
        if (listButton) {
            event.preventDefault();
            handleListAction(listButton);
            return;
        }

        const swatch = event.target.closest('[data-act="blip-color"]');
        if (swatch) {
            const container = swatch.closest('.field') || swatch.parentElement.parentElement;
            const input = $('[data-path$="blip.color"]', container) || $('input[type="number"]', container);
            if (input) {
                input.value = swatch.dataset.value;
                $$('.swatch', container).forEach((node) => node.classList.remove('on'));
                swatch.classList.add('on');
                refreshPreviews();
            }
            return;
        }

        const action = event.target.closest('[data-act]');
        if (action) {
            const name = action.dataset.act;
            if (['filter-jobs', 'filter-kind', 'job-scope', 'sprite-pick', 'toggle-job'].includes(name)) return;
            event.preventDefault();
            handleAction(name, action);
        }
    });

    document.addEventListener('change', (event) => {
        const target = event.target;

        if (target.dataset.act === 'toggle-job') {
            handleAction('toggle-job', target);
            return;
        }
        if (target.dataset.act === 'job-scope') {
            state.jobScope = target.value;
            render();
            return;
        }
        if (target.dataset.act === 'filter-kind') {
            state.kindFilter = target.value;
            render();
            return;
        }
        if (target.dataset.act === 'sprite-pick') {
            const container = target.closest('.field') || target.parentElement;
            const input = $('input[type="number"]', container);
            if (input) { input.value = target.value; refreshPreviews(); }
            return;
        }
        if (target.closest('#drawer-form')) {
            // keep the "on" styling of multi checks in sync
            const check = target.closest('.check');
            if (check) check.classList.toggle('on', target.checked);
            refreshPreviews();
        }
    });

    document.addEventListener('input', (event) => {
        const target = event.target;
        if (target.dataset.act === 'filter-jobs') {
            const value = target.value;
            state.jobFilter = value;
            render();
            // the toolbar was re-rendered: restore the field and the caret
            const again = $('[data-act="filter-jobs"]');
            if (again) {
                again.value = value;
                again.focus();
                again.setSelectionRange(value.length, value.length);
            }
            return;
        }
        if (target.closest('#drawer-form')) refreshPreviews();
    });

    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;

        if (!$('#dialog').classList.contains('hidden')) { resolveDialog(null); return; }
        if (!$('#confirm').classList.contains('hidden')) { $('#confirm-cancel').click(); return; }
        if (!$('#drawer').classList.contains('hidden')) { closeDrawer(); return; }
        if (!$('#boss').classList.contains('hidden')) { closeBoss(); return; }
        if (state.open) closeCreator();
    });

    $('#btn-close').addEventListener('click', () => closeCreator());
    $('#drawer-save').addEventListener('click', () => submitDrawer());

    function handleListAction(button) {
        const listEl = button.closest('[data-list]');
        if (!listEl) return;

        const field = findListField(state.drawer && state.drawer.schema, listEl.dataset.list);
        const template = listEl.dataset.listTemplate;
        const body = $('[data-list-body]', listEl);

        if (button.dataset.act === 'list-add') {
            const index = $$('[data-list-row]', body).length;
            body.insertAdjacentHTML('beforeend', renderListRow(field || { columns: [] }, {}, index, template));
            return;
        }

        const row = button.closest('[data-list-row]');
        if (!row) return;

        if (button.dataset.act === 'list-del') {
            row.remove();
        } else if (button.dataset.act === 'list-up') {
            const previous = row.previousElementSibling;
            if (previous) body.insertBefore(row, previous);
        }
    }

    function findListField(schema, name) {
        if (!Array.isArray(schema)) return null;
        for (const entry of schema) {
            if (entry.name === name && entry.type === 'list') return entry;
            if (entry.fields) {
                const found = findListField(entry.fields, name);
                if (found) return found;
            }
        }
        return null;
    }

    /* =====================================================================
       OPEN / CLOSE CREATOR
       ===================================================================== */

    const THEMES = ['azure', 'violet', 'emerald', 'amber', 'crimson', 'mono'];

    /** Tint the whole interface. Unknown names fall back to the default. */
    function applyTheme(theme) {
        const name = String(theme || '').toLowerCase();
        document.documentElement.dataset.theme = THEMES.includes(name) ? name : 'azure';
    }

    function openCreator(dataset) {
        state.data = dataset;
        state.open = true;
        if (dataset.client && dataset.client.theme) applyTheme(dataset.client.theme);
        state.section = 'dashboard';
        state.jobScope = (dataset.jobs && dataset.jobs[0] && dataset.jobs[0].name) || '';
        $('#creator').classList.remove('hidden');
        render();
    }

    function closeCreator() {
        if (!state.open) return;
        state.open = false;
        $('#creator').classList.add('hidden');
        closeDrawer();
        nui('creator:close', {});
    }

    /* =====================================================================
       BOSS MENU
       ===================================================================== */

    const BOSS_TABS = [
        { id: 'employees', label: 'Employees', feature: 'employees', icon: 'users' },
        { id: 'hire', label: 'Hire', feature: 'hire', icon: 'userPlus' },
        { id: 'grades', label: 'Grades & salaries', feature: 'salary', icon: 'grades' },
        { id: 'funds', label: 'Funds', feature: 'funds', icon: 'money' },
        { id: 'transactions', label: 'Transactions', feature: 'transactions', icon: 'receipt' },
    ];

    function openBoss(data) {
        state.boss = data;
        state.bossTab = 'employees';
        $('#boss').classList.remove('hidden');
        renderBoss();
    }

    function closeBoss() {
        if (!state.boss) return;
        state.boss = null;
        $('#boss').classList.add('hidden');
        nui('boss:close', {});
    }

    async function bossRequest(endpoint, payload) {
        const result = await nui('boss:request', { endpoint, payload: payload || {} });
        if (!result || result.ok !== true) {
            toast((result && result.error) || 'unknown error', 'error');
            return null;
        }
        const inner = result.data;
        if (inner && inner.ok === false) {
            toast(inner.error || 'unknown error', 'error');
            return null;
        }
        return (inner && inner.data) || inner || {};
    }

    function renderBoss() {
        const data = state.boss;
        if (!data) return;

        $('#boss-title').textContent = data.label || 'Boss Menu';
        $('#boss-sub').textContent = `${(data.job && data.job.label) || ''} - ${(data.employees || []).length} employees`;
        $('#boss-balance').textContent = money(data.balance);

        const features = data.features || {};
        const tabs = BOSS_TABS.filter((tab) => features[tab.feature] !== false);

        $('#boss-tabs').innerHTML = tabs.map((tab) => `
            <div class="boss-tab ${state.bossTab === tab.id ? 'active' : ''}" data-boss-tab="${esc(tab.id)}">
                ${ico(tab.icon)}${esc(tab.label)}
            </div>`).join('');

        const renderers = {
            employees: renderBossEmployees,
            hire: renderBossHire,
            grades: renderBossGrades,
            funds: renderBossFunds,
            transactions: renderBossTransactions,
        };
        (renderers[state.bossTab] || renderBossEmployees)();
    }

    function renderBossEmployees() {
        const data = state.boss;
        const permissions = data.permissions || {};
        const features = data.features || {};

        const rows = (data.employees || []).map((employee) => {
            const initials = String(employee.name || '?').split(' ').map((part) => part[0]).join('').slice(0, 2).toUpperCase();
            const ops = [];

            if (features.promote !== false && permissions.promote) {
                ops.push(`<button class="btn btn-sm" data-boss-act="promote" data-id="${esc(employee.identifier)}">${ico('up')}Promote</button>`);
            }
            if (features.promote !== false && permissions.demote) {
                ops.push(`<button class="btn btn-sm" data-boss-act="demote" data-id="${esc(employee.identifier)}" style="transform:none"><span style="display:flex;transform:rotate(180deg)">${ico('up')}</span>Demote</button>`);
            }
            if (features.grades !== false && permissions.manage_grades) {
                const options = (data.grades || []).map((grade) =>
                    `<option value="${grade.grade}" ${grade.grade === employee.grade ? 'selected' : ''}>${esc(grade.label)}</option>`).join('');
                ops.push(`<select class="select" style="width:150px" data-boss-act="setGrade" data-id="${esc(employee.identifier)}">${options}</select>`);
            }
            if (features.duty && permissions.toggle_duty && employee.online) {
                ops.push(`<button class="btn btn-sm" data-boss-act="duty" data-target="${esc(employee.source)}" data-state="${employee.onDuty ? '0' : '1'}">${employee.onDuty ? 'Off duty' : 'On duty'}</button>`);
            }
            if (features.fire !== false && permissions.fire) {
                ops.push(`<button class="btn btn-sm btn-danger" data-boss-act="fire" data-id="${esc(employee.identifier)}">${ico('close')}Fire</button>`);
            }

            return `<div class="employee">
                <div class="avatar ${employee.online ? '' : 'offline'}">${esc(initials)}</div>
                <div class="who">
                    <strong>${esc(employee.name)}</strong>
                    <small>
                        <span class="dot ${employee.online ? 'green' : 'red'}"></span>
                        ${esc(employee.gradeLabel)} &middot; grade ${esc(employee.grade)}
                        ${employee.onDuty ? '&middot; <span style="color:#6ee7b7">on duty</span>' : ''}
                    </small>
                </div>
                <div class="ops">${ops.join('')}</div>
            </div>`;
        }).join('');

        $('#boss-body').innerHTML = rows || emptyState('No employees yet', 'Hire someone standing next to you from the Hire tab.', 'users');
    }

    async function renderBossHire() {
        $('#boss-body').innerHTML = `<div class="help">Looking for players nearby...</div>`;
        const data = await bossRequest('boss:nearbyPlayers', {});
        if (!data) {
            $('#boss-body').innerHTML = `<div class="empty"><strong>Could not look around</strong>You may not have permission to hire.</div>`;
            return;
        }

        const list = Array.isArray(data) ? data : [];
        const grades = (state.boss.grades || []).map((grade) => `<option value="${grade.grade}">${esc(grade.label)}</option>`).join('');

        $('#boss-body').innerHTML = `
            <p class="help" style="margin-bottom:14px">Only players standing next to you can be hired.</p>
            ${list.length ? list.map((player) => `
                <div class="employee">
                    <div class="avatar">${esc(String(player.name || '?').slice(0, 2).toUpperCase())}</div>
                    <div class="who">
                        <strong>${esc(player.name)}</strong>
                        <small>${player.job ? esc(player.job) : 'unemployed'}</small>
                    </div>
                    <div class="ops">
                        <select class="select" data-hire-grade="${esc(player.source)}">${grades}</select>
                        <button class="btn btn-sm btn-success" data-boss-act="hire" data-target="${esc(player.source)}">${ico('userPlus')}Hire</button>
                    </div>
                </div>`).join('') : emptyState('Nobody nearby', 'Ask the person you want to hire to stand next to you, then refresh.', 'users')}
            <button class="btn btn-sm" style="margin-top:14px" data-boss-act="refresh-hire">${ico('refresh')}Refresh</button>`;
    }

    function renderBossGrades() {
        const data = state.boss;
        const canEdit = (data.permissions || {}).manage_salary && (data.features || {}).salary !== false;

        $('#boss-body').innerHTML = `
            <div class="panel">
                <div class="panel-head"><h3>${ico('grades')}Rank ladder</h3></div>
                <table class="table">
                    <thead><tr><th style="width:60px">#</th><th>Rank</th><th style="width:170px">Salary</th><th style="width:90px">Boss</th>${canEdit ? '<th style="width:100px"></th>' : ''}</tr></thead>
                    <tbody>${(data.grades || []).map((grade) => `
                        <tr>
                            <td><span class="chip ${grade.is_boss ? 'on' : ''}">${esc(grade.grade)}</span></td>
                            <td class="t-main">${esc(grade.label)}</td>
                            <td>${canEdit
                                ? `<input class="input" style="width:140px" type="number" min="0" value="${esc(grade.salary)}" data-salary="${esc(grade.grade)}">`
                                : `<span class="mono">${money(grade.salary)}</span>`}</td>
                            <td>${grade.is_boss ? `<span class="chip green">${ico('star')}boss</span>` : ''}</td>
                            ${canEdit ? `<td class="actions"><button class="btn btn-sm btn-primary" data-boss-act="salary" data-grade="${esc(grade.grade)}">${ico('check')}Save</button></td>` : ''}
                        </tr>`).join('')}</tbody>
                </table>
            </div>`;
    }

    function renderBossFunds() {
        const data = state.boss;
        const permissions = data.permissions || {};
        const features = data.features || {};

        const canDeposit = features.deposit !== false && permissions.deposit;
        const canWithdraw = features.withdraw !== false && permissions.withdraw;

        $('#boss-body').innerHTML = `
            <div class="stat" style="margin-bottom:18px">
                <div class="stat-top">
                    <div class="label">Society account</div>
                    <div class="ico">${ico('money')}</div>
                </div>
                <div class="value" style="color:#6ee7b7">${money(data.balance)}</div>
                <div class="hint">${esc((data.job && data.job.label) || '')}</div>
            </div>

            <div class="grid cols-2">
                ${canDeposit ? `
                <div class="panel">
                    <div class="panel-head"><h3>${ico('up')}Deposit</h3></div>
                    <div class="panel-body">
                        <p class="help" style="margin-bottom:14px">Move money from your own pocket into the society account.</p>
                        <div class="form-row two">
                            <div class="field"><label>Amount</label><input class="input" type="number" min="1" placeholder="0" id="deposit-amount"></div>
                            <div class="field"><label>From</label><select class="select" id="deposit-account"><option value="cash">Cash</option><option value="bank">Bank</option></select></div>
                        </div>
                        <button class="btn btn-primary btn-block" style="margin-top:14px" data-boss-act="deposit">${ico('up')}Deposit</button>
                    </div>
                </div>` : ''}

                ${canWithdraw ? `
                <div class="panel">
                    <div class="panel-head"><h3><span style="display:flex;transform:rotate(180deg)">${ico('up')}</span>Withdraw</h3></div>
                    <div class="panel-body">
                        <p class="help" style="margin-bottom:14px">Take money out of the society account.</p>
                        <div class="form-row two">
                            <div class="field"><label>Amount</label><input class="input" type="number" min="1" placeholder="0" id="withdraw-amount"></div>
                            <div class="field"><label>To</label><select class="select" id="withdraw-account"><option value="cash">Cash</option><option value="bank">Bank</option></select></div>
                        </div>
                        <button class="btn btn-primary btn-block" style="margin-top:14px" data-boss-act="withdraw">${ico('money')}Withdraw</button>
                    </div>
                </div>` : ''}
            </div>

            ${!canDeposit && !canWithdraw ? emptyState('View only', 'Your rank can see the balance but cannot move money.', 'shield') : ''}`;
    }

    function renderBossTransactions() {
        const list = state.boss.transactions || [];
        $('#boss-body').innerHTML = list.length ? list.map((tx) => {
            const incoming = ['deposit', 'purchase'].includes(tx.kind);
            return `<div class="tx">
                <div class="tx-ico ${incoming ? 'in' : 'out'}">
                    ${incoming ? ico('up') : `<span style="display:flex;transform:rotate(180deg)">${ico('up')}</span>`}
                </div>
                <div class="tx-main">
                    <strong>${esc(tx.kind)}</strong>
                    <small>${esc(tx.actor_name || 'system')}${tx.note ? ` &middot; ${esc(tx.note)}` : ''} &middot; ${esc(tx.created_at || '')}</small>
                </div>
                <div class="amount ${incoming ? 'in' : 'out'}">${incoming ? '+' : '-'}${money(Math.abs(num(tx.amount)))}</div>
            </div>`;
        }).join('') : emptyState('No transactions yet', 'Deposits, withdrawals, salaries and shop purchases all show up here.', 'receipt');
    }

    document.addEventListener('click', async (event) => {
        const tab = event.target.closest('[data-boss-tab]');
        if (tab) {
            state.bossTab = tab.dataset.bossTab;
            renderBoss();
            return;
        }

        const action = event.target.closest('[data-boss-act]');
        if (!action) return;

        const act = action.dataset.bossAct;

        if (act === 'refresh-hire') { renderBossHire(); return; }

        if (act === 'promote' || act === 'demote') {
            const result = await bossRequest(`boss:${act}`, { identifier: action.dataset.id });
            if (result) { state.boss.employees = result.employees || state.boss.employees; renderBoss(); }
            return;
        }
        if (act === 'fire') {
            const result = await bossRequest('boss:fire', { identifier: action.dataset.id });
            if (result) { state.boss.employees = result.employees || state.boss.employees; renderBoss(); }
            return;
        }
        if (act === 'hire') {
            const select = $(`[data-hire-grade="${action.dataset.target}"]`);
            const result = await bossRequest('boss:hire', {
                target: parseInt(action.dataset.target, 10),
                grade: select ? parseInt(select.value, 10) : 0,
            });
            if (result) {
                state.boss.employees = result.employees || state.boss.employees;
                state.bossTab = 'employees';
                renderBoss();
            }
            return;
        }
        if (act === 'duty') {
            const result = await bossRequest('boss:toggleDuty', {
                target: parseInt(action.dataset.target, 10),
                state: action.dataset.state === '1',
            });
            if (result) { state.boss.employees = result.employees || state.boss.employees; renderBoss(); }
            return;
        }
        if (act === 'salary') {
            const grade = parseInt(action.dataset.grade, 10);
            const input = $(`[data-salary="${grade}"]`);
            const result = await bossRequest('boss:setSalary', { grade, salary: input ? num(input.value, 0) : 0 });
            if (result) { state.boss.grades = result.grades || state.boss.grades; toast('Salary updated.', 'success'); renderBoss(); }
            return;
        }
        if (act === 'deposit' || act === 'withdraw') {
            const amountInput = $(`#${act}-amount`);
            const accountInput = $(`#${act}-account`);
            const amount = amountInput ? num(amountInput.value, 0) : 0;
            if (amount <= 0) { toast('Enter an amount.', 'error'); return; }

            const result = await bossRequest(`boss:${act}`, { amount, account: accountInput ? accountInput.value : 'cash' });
            if (result) {
                state.boss.balance = result.balance !== undefined ? result.balance : state.boss.balance;
                toast(act === 'deposit' ? 'Deposited.' : 'Withdrawn.', 'success');
                const funds = await bossRequest('boss:funds', {});
                if (funds) {
                    state.boss.balance = funds.balance;
                    state.boss.transactions = funds.transactions || state.boss.transactions;
                }
                renderBoss();
            }
            return;
        }
    });

    $('#boss-close').addEventListener('click', () => closeBoss());

    /* =====================================================================
       IN-WORLD DIALOGS (ox_lib fallback)
       ===================================================================== */

    function resolveDialog(value) {
        if (state.dialogToken === null) return;
        const token = state.dialogToken;
        state.dialogToken = null;
        $('#dialog').classList.add('hidden');
        $('#dialog-body').innerHTML = '';
        $('#dialog-actions').innerHTML = '';
        nui('dialog:result', { token, value });
    }

    function showDialog(token, kind, payload) {
        state.dialogToken = token;
        const modal = $('#dialog');
        $('#dialog-title').textContent = (payload && payload.title) || '';
        $('#dialog-actions').innerHTML = '';

        if (kind === 'menu') {
            $('#dialog-body').innerHTML = `<div class="dialog-list">${(payload.options || []).map((option) => `
                <button class="dialog-option" data-dialog-option="${option.index}" ${option.disabled ? 'disabled' : ''}>
                    <span class="opt-ico">${ico(mapIcon(option.icon))}</span>
                    <span class="opt-text">
                        <span>${esc(option.label)}</span>
                        ${option.description ? `<small>${esc(option.description)}</small>` : ''}
                    </span>
                    ${ico('right')}
                </button>`).join('')}</div>`;
            $('#dialog-actions').innerHTML = `<button class="btn btn-ghost" data-dialog-cancel>Close</button>`;
        } else if (kind === 'input') {
            $('#dialog-body').innerHTML = `<div class="dialog-fields">${(payload.fields || []).map((field) => {
                if (field.type === 'select') {
                    return `<div class="field"><label>${esc(field.label)}</label>
                        <select class="select" data-dialog-field="${esc(field.name)}">
                            ${(field.options || []).map((option) => `<option value="${esc(option.value)}">${esc(option.label)}</option>`).join('')}
                        </select></div>`;
                }
                if (field.type === 'checkbox') {
                    return `<div class="field inline"><label>${esc(field.label)}</label>
                        <label class="switch"><input type="checkbox" data-dialog-field="${esc(field.name)}" data-dialog-type="checkbox" ${field.default ? 'checked' : ''}><span class="track"></span></label></div>`;
                }
                return `<div class="field"><label>${esc(field.label)}</label>
                    <input class="input" type="${field.password ? 'password' : (field.type === 'number' ? 'number' : 'text')}"
                        data-dialog-field="${esc(field.name)}" data-dialog-type="${esc(field.type || 'text')}"
                        value="${esc(field.default === undefined || field.default === null ? '' : field.default)}"
                        ${field.min !== undefined ? `min="${esc(field.min)}"` : ''}
                        ${field.max !== undefined ? `max="${esc(field.max)}"` : ''}></div>`;
            }).join('')}</div>`;
            $('#dialog-actions').innerHTML = `
                <button class="btn btn-ghost" data-dialog-cancel>Cancel</button>
                <button class="btn btn-primary" data-dialog-submit>Confirm</button>`;
        } else {
            $('#dialog-body').innerHTML = `<p>${esc((payload && payload.message) || '')}</p>`;
            $('#dialog-actions').innerHTML = `
                <button class="btn btn-ghost" data-dialog-cancel>Cancel</button>
                <button class="btn btn-primary" data-dialog-confirm>${esc((payload && payload.confirmLabel) || 'Confirm')}</button>`;
        }

        modal.classList.remove('hidden');
        const firstInput = $('#dialog-body input, #dialog-body select');
        if (firstInput) firstInput.focus();
    }

    document.addEventListener('click', (event) => {
        if (state.dialogToken === null) return;

        const option = event.target.closest('[data-dialog-option]');
        if (option) { resolveDialog(parseInt(option.dataset.dialogOption, 10)); return; }
        if (event.target.closest('[data-dialog-cancel]') || event.target.id === 'dialog-backdrop') { resolveDialog(null); return; }
        if (event.target.closest('[data-dialog-confirm]')) { resolveDialog(true); return; }

        if (event.target.closest('[data-dialog-submit]')) {
            const values = {};
            $$('[data-dialog-field]').forEach((input) => {
                const type = input.dataset.dialogType;
                if (type === 'checkbox') values[input.dataset.dialogField] = input.checked;
                else if (type === 'number') values[input.dataset.dialogField] = num(input.value, 0);
                else values[input.dataset.dialogField] = input.value;
            });
            resolveDialog(values);
        }
    });

    document.addEventListener('keydown', (event) => {
        if (state.dialogToken === null) return;
        if (event.key === 'Enter') {
            const submit = $('[data-dialog-submit]') || $('[data-dialog-confirm]');
            if (submit) submit.click();
        }
    });

    /* =====================================================================
       MESSAGE BUS
       ===================================================================== */

    window.addEventListener('message', (event) => {
        const message = event.data || {};

        switch (message.action) {
            case 'theme':
                applyTheme(message.theme);
                break;
            case 'openCreator':
                openCreator(message.payload);
                break;
            case 'closeCreator':
                state.open = false;
                $('#creator').classList.add('hidden');
                $('#drawer').classList.add('hidden');
                break;
            case 'jobState':
                // the player's own job changed while the creator is open
                break;
            case 'openBoss':
                openBoss(message.payload);
                break;
            case 'closeBoss':
                state.boss = null;
                $('#boss').classList.add('hidden');
                break;
            case 'dialog':
                showDialog(message.token, message.kind, message.payload);
                break;
            case 'dialogClose':
                state.dialogToken = null;
                $('#dialog').classList.add('hidden');
                break;
            case 'placementStart':
                $('#creator').classList.add('hidden');
                $('#drawer').classList.add('hidden');
                $('#placement').classList.remove('hidden');
                break;
            case 'placementResult': {
                $('#placement').classList.add('hidden');
                $('#creator').classList.remove('hidden');
                $('#drawer').classList.remove('hidden');

                const result = message.payload;
                if (result && state.placementTarget) {
                    applyCoords(state.placementTarget.coords, state.placementTarget.heading, result.coords, result.heading);
                    const radiusInput = $('#drawer-form [data-path="marker.interactDistance"]');
                    if (radiusInput && result.radius) radiusInput.value = result.radius;
                    refreshPreviews();
                    toast('Position captured from the world.', 'success');
                }
                break;
            }
            default:
                break;
        }
    });
})();
