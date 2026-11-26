// ==UserScript==
// @name         Auto Full Bài Tập: 4 AI Providers + 1-User License Key (V10.0)
// @namespace    http://tampermonkey.net/
// @version      10.0
// @description  1 Key kích hoạt cho 1 người dùng duy nhất (chống share key), hỗ trợ 4 nguồn AI đa Key và tự động nộp bài
// @match        *://*/*
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @connect      script.google.com
// @connect      script.googleusercontent.com
// @connect      api.cerebras.ai
// @connect      generativelanguage.googleapis.com
// @connect      openrouter.ai
// @connect      api.groq.com
// ==/UserScript==

(function () {
    'use strict';

    // =========================================================================
    // DÁN LINK WEB APP GOOGLE APPS SCRIPT CỦA BẠN VÀO ĐÂY TRƯỚC KHI MÃ HÓA
    // =========================================================================
    const ACTIVATION_API_URL = 'https://script.google.com/macros/s/AKfycbxyAp32sMVQRGaWHPgxLyWpEENi9O3YlYwGvBMF28_3d-xPebK002nCYzsAmiQjUYHs0Q/exec';

    let isRunning = false;
    let capturedExamJson = null;

    const CEREBRAS_MODELS = ['llama-3.3-70b', 'qwen-3-32b', 'llama3.1-8b'];
    const GEMINI_MODELS = ['gemini-2.5-flash-lite', 'gemini-2.0-flash', 'gemini-3.1-flash-lite-preview', 'gemini-3-flash-preview'];
    const OPENROUTER_MODELS = ['openrouter/free', 'meta-llama/llama-3.3-70b-instruct:free', 'google/gemma-3-27b-it:free', 'qwen/qwen3-32b:free'];
    const GROQ_MODELS = ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b', 'llama-3.1-8b-instant'];

    // =========================================================================
    // 1. TỰ ĐỘNG BẮT JSON ĐỀ THI TỪ NETWORK
    // =========================================================================
    const pageWindow = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;

    function inspectAndCaptureJson(rawText) {
        if (!rawText || typeof rawText !== 'string' || !rawText.includes('"exam_data"')) return;
        try {
            const parsed = JSON.parse(rawText);
            const examData = parsed?.data?.exam_data || parsed?.exam_data;
            if (examData && (examData.multiple_choice || examData.true_false || examData.fill_in_blank || examData.essay)) {
                capturedExamJson = parsed;
                const inputEl = document.getElementById('aq-input');
                if (inputEl) inputEl.value = JSON.stringify(parsed);
                const total = countQuestionsInJson(parsed);
                setStatus(`🎯 Đã bắt đề (${total} câu)!`, '#38bdf8');
            }
        } catch (e) {}
    }

    const origFetch = pageWindow.fetch;
    if (origFetch) {
        pageWindow.fetch = async function (...args) {
            const response = await origFetch.apply(this, args);
            try {
                response.clone().text().then(inspectAndCaptureJson).catch(() => {});
            } catch (e) {}
            return response;
        };
    }

    const origXhrOpen = pageWindow.XMLHttpRequest.prototype.open;
    const origXhrSend = pageWindow.XMLHttpRequest.prototype.send;
    pageWindow.XMLHttpRequest.prototype.open = function (...args) {
        return origXhrOpen.apply(this, args);
    };
    pageWindow.XMLHttpRequest.prototype.send = function (...args) {
        this.addEventListener('load', function () {
            try {
                if (this.responseType === '' || this.responseType === 'text') {
                    inspectAndCaptureJson(this.responseText);
                } else if (this.responseType === 'json' && this.response) {
                    inspectAndCaptureJson(JSON.stringify(this.response));
                }
            } catch (e) {}
        });
        return origXhrSend.apply(this, args);
    };

    // =========================================================================
    // 2. XÁC THỰC KEY KÍCH HOẠT 1 LẦN CHO 1 NGƯỜI DÙNG
    // =========================================================================
    function getDeviceSignature() {
        let sig = localStorage.getItem('aq_device_id');
        if (!sig) {
            sig = 'DEV-' + Math.random().toString(36).substring(2, 10).toUpperCase();
            localStorage.setItem('aq_device_id', sig);
        }
        return sig;
    }

    function isActivatedLocally() {
        const unlocked = localStorage.getItem('aq_license_unlocked') === 'true';
        const boundSig = localStorage.getItem('aq_license_sig');
        return unlocked && boundSig && boundSig === getDeviceSignature();
    }

    function updateLockUIState() {
        const unlocked = isActivatedLocally();
        const lockArea = document.getElementById('aq-protected-area');
        const actInput = document.getElementById('aq-act-key');
        const actBtn = document.getElementById('aq-act-btn');
        const actBadge = document.getElementById('aq-act-badge');

        if (!lockArea || !actInput || !actBtn || !actBadge) return;

        if (unlocked) {
            lockArea.style.opacity = '1';
            lockArea.style.pointerEvents = 'auto';
            actInput.disabled = true;
            actInput.value = localStorage.getItem('aq_license_code') || '••••••••';
            actBtn.style.display = 'none';
            actBadge.textContent = '✅ Đã kích hoạt';
            actBadge.style.color = '#4ade80';
        } else {
            lockArea.style.opacity = '0.35';
            lockArea.style.pointerEvents = 'none';
            actInput.disabled = false;
            actBtn.style.display = 'inline-block';
            actBadge.textContent = '🔒 Chưa kích hoạt';
            actBadge.style.color = '#f87171';
        }
    }

    function verifyActivationKeyOnline(userKey) {
        return new Promise((resolve, reject) => {
            if (!ACTIVATION_API_URL || !ACTIVATION_API_URL.startsWith('http')) {
                reject('Chưa cấu hình link Google Apps Script!');
                return;
            }
            const url = `${ACTIVATION_API_URL}?key=${encodeURIComponent(userKey)}&t=${Date.now()}`;
            GM_xmlhttpRequest({
                method: 'GET',
                url: url,
                timeout: 12000,
                onload: function (res) {
                    const result = (res.responseText || '').trim();
                    if (result === 'OK') {
                        resolve(true);
                    } else if (result === 'USED') {
                        reject('Key này đã được kích hoạt bởi người khác!');
                    } else if (result === 'INVALID') {
                        reject('Mã kích hoạt không đúng!');
                    } else {
                        reject('Lỗi kiểm tra Key từ máy chủ.');
                    }
                },
                ontimeout: () => reject('Quá thời gian kiểm tra Key.'),
                onerror: () => reject('Lỗi mạng khi xác thực Key.')
            });
        });
    }

    // =========================================================================
    // 3. WEB WORKER TIMER & REACT DOM HELPERS
    // =========================================================================
    const workerBlob = new Blob([`
        self.onmessage = function(e) {
            setTimeout(() => self.postMessage(e.data), e.data.delay);
        };
    `], { type: 'application/javascript' });
    const timerWorker = new Worker(URL.createObjectURL(workerBlob));
    let timerId = 0;
    const pendingTimers = new Map();

    timerWorker.onmessage = function (e) {
        const resolve = pendingTimers.get(e.data.id);
        if (resolve) {
            pendingTimers.delete(e.data.id);
            resolve();
        }
    };

    function smartSleep(ms) {
        if (ms <= 0) return Promise.resolve();
        return new Promise((resolve) => {
            const id = ++timerId;
            pendingTimers.set(id, resolve);
            timerWorker.postMessage({ id, delay: ms });
        });
    }

    function setReactFieldValue(el, value) {
        const proto = el.tagName === 'TEXTAREA'
            ? window.HTMLTextAreaElement.prototype
            : window.HTMLInputElement.prototype;
        const nativeSetter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        nativeSetter.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }

    async function clickAndConfirmTfButton(btn) {
        const isSelected = (b) => b.className.includes('bg-green-') || b.className.includes('bg-red-');
        if (isSelected(btn)) return true;

        btn.click();
        const start = Date.now();
        while (Date.now() - start < 350) {
            if (isSelected(btn)) return true;
            await smartSleep(20);
        }
        btn.click();
        await smartSleep(40);
        return isSelected(btn);
    }

    async function waitForQuestionSaved(dialog, qNum, maxWaitMs = 450) {
        const start = Date.now();
        while (Date.now() - start < maxWaitMs) {
            const navBtns = Array.from(dialog.querySelectorAll('button'));
            const qBtn = navBtns.find((b) => b.textContent.trim() === String(qNum));
            if (qBtn && qBtn.title && !qBtn.title.includes('Chưa trả lời')) {
                return true;
            }
            await smartSleep(25);
        }
        return false;
    }

    async function autoSubmitExam() {
        setStatus('📤 Đang nộp bài...', '#38bdf8');
        await smartSleep(200);

        const isSubmitBtn = (btn) => {
            if (!btn || btn.disabled || btn.closest('#auto-quiz-panel')) return false;
            const txt = btn.textContent.trim();
            return /^(nộp bài|hoàn thành|kết thúc|submit)/i.test(txt) || txt.includes('Nộp bài');
        };

        const dialog = document.querySelector('[role="dialog"]');
        let submitBtn = dialog
            ? Array.from(dialog.querySelectorAll('button')).find(isSubmitBtn)
            : Array.from(document.querySelectorAll('button')).find(isSubmitBtn);

        if (!submitBtn) return false;

        submitBtn.click();
        await smartSleep(350);

        const confirmKeywords = /^(xác nhận|đồng ý|nộp bài|có|ok|submit|confirm)$/i;
        const confirmBtn = Array.from(document.querySelectorAll('button'))
            .filter((b) => !b.disabled && !b.closest('#auto-quiz-panel') && b !== submitBtn)
            .find((b) => confirmKeywords.test(b.textContent.trim()));

        if (confirmBtn) {
            confirmBtn.click();
            await smartSleep(200);
        }
        return true;
    }

    // =========================================================================
    // 4. GIAO DIỆN TÍCH HỢP Ô KEY KÍCH HOẠT + 4 NGUỒN AI
    // =========================================================================
    function createUI() {
        const container = document.querySelector('[role="dialog"]') || document.body;
        if (!container) return;

        let panel = document.getElementById('auto-quiz-panel');
        if (panel) {
            if (panel.parentElement !== container) container.appendChild(panel);
            return;
        }

        panel = document.createElement('div');
        panel.id = 'auto-quiz-panel';
        panel.style.cssText = `
            position: fixed !important;
            bottom: 16px !important;
            right: 16px !important;
            width: 400px !important;
            background: #1e293b !important;
            color: #f8fafc !important;
            border-radius: 12px !important;
            box-shadow: 0 10px 25px rgba(0,0,0,0.45) !important;
            z-index: 999999 !important;
            pointer-events: auto !important;
            font-family: system-ui, -apple-system, sans-serif !important;
            font-size: 13px !important;
            overflow: hidden !important;
            border: 1px solid #334155 !important;
        `;

        panel.innerHTML = `
            <div id="aq-header" style="padding: 8px 14px; background: #0f172a; display: flex; justify-content: space-between; align-items: center; user-select: none;">
                <span style="font-weight: 600; color: #38bdf8;">⚡ Auto Multi-AI: 4 Providers (V10.0)</span>
                <div style="display: flex; gap: 8px; align-items: center;">
                    <button id="aq-toggle-keys" type="button" style="background: #1e293b; border: 1px solid #475569; color: #cbd5e1; border-radius: 4px; padding: 1px 6px; cursor: pointer; font-size: 11px;">🔑 Ẩn/Hiện Keys</button>
                    <button id="aq-toggle" type="button" style="background: none; border: none; color: #94a3b8; cursor: pointer; font-size: 12px;">Thu gọn</button>
                </div>
            </div>
            <div id="aq-body" style="padding: 10px 14px;">
                <!-- KHUNG NHẬP KEY KÍCH HOẠT 1 NGƯỜI -->
                <div style="margin-bottom: 8px; padding: 7px 8px; background: #0f172a; border: 1px solid #334155; border-radius: 7px;">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                        <span style="color: #fbbf24; font-size: 11px; font-weight: 600;">🔐 Key kích hoạt (1 người / 1 máy):</span>
                        <span id="aq-act-badge" style="font-size: 11px; font-weight: 600; color: #f87171;">🔒 Chưa kích hoạt</span>
                    </div>
                    <div style="display: flex; gap: 5px;">
                        <input id="aq-act-key" type="text" placeholder="Nhập mã kích hoạt được cấp..." style="
                            flex: 1; box-sizing: border-box; background: #1e293b; color: #f8fafc;
                            border: 1px solid #475569; border-radius: 5px; padding: 4px 8px;
                            font-family: monospace; font-size: 12px; outline: none; pointer-events: auto !important;
                        ">
                        <button id="aq-act-btn" type="button" style="background: #f59e0b; color: #0f172a; border: none; padding: 4px 10px; border-radius: 5px; font-weight: 700; font-size: 11px; cursor: pointer; white-space: nowrap;">Kích hoạt</button>
                    </div>
                </div>

                <!-- VÙNG TÍNH NĂNG ĐƯỢC BẢO VỆ -->
                <div id="aq-protected-area" style="transition: opacity 0.2s;">
                    <div id="aq-keys-box" style="margin-bottom: 6px; display: flex; flex-direction: column; gap: 5px;">
                        <div>
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1px;">
                                <span style="color: #94a3b8; font-size: 11px;">⚡ Cerebras Keys <span id="aq-cer-count" style="color:#f59e0b;"></span>:</span>
                                <a href="https://cloud.cerebras.ai/" target="_blank" style="color: #f59e0b; font-size: 11px; text-decoration: none;">Lấy Key Cerebras ↗</a>
                            </div>
                            <input id="aq-cerebraskey" type="password" placeholder="csk-..., csk-..." style="
                                width: 100%; box-sizing: border-box; background: #0f172a; color: #f8fafc;
                                border: 1px solid #475569; border-radius: 5px; padding: 4px 7px;
                                font-family: monospace; font-size: 11px; outline: none; pointer-events: auto !important;
                            ">
                        </div>

                        <div>
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1px;">
                                <span style="color: #94a3b8; font-size: 11px;">🔑 Gemini Keys <span id="aq-gem-count" style="color:#38bdf8;"></span> (chuẩn tiếng Việt):</span>
                                <a href="https://aistudio.google.com/apikey" target="_blank" style="color: #38bdf8; font-size: 11px; text-decoration: none;">Lấy Key Gemini ↗</a>
                            </div>
                            <input id="aq-geminikey" type="password" placeholder="AIzaSy..., AIzaSy..." style="
                                width: 100%; box-sizing: border-box; background: #0f172a; color: #f8fafc;
                                border: 1px solid #475569; border-radius: 5px; padding: 4px 7px;
                                font-family: monospace; font-size: 11px; outline: none; pointer-events: auto !important;
                            ">
                        </div>

                        <div>
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1px;">
                                <span style="color: #94a3b8; font-size: 11px;">🌐 OpenRouter Keys <span id="aq-or-count" style="color:#c084fc;"></span> (không chặn IP):</span>
                                <a href="https://openrouter.ai/keys" target="_blank" style="color: #c084fc; font-size: 11px; text-decoration: none;">Lấy Key OpenRouter ↗</a>
                            </div>
                            <input id="aq-openrouterkey" type="password" placeholder="sk-or-v1-..., sk-or-v1-..." style="
                                width: 100%; box-sizing: border-box; background: #0f172a; color: #f8fafc;
                                border: 1px solid #475569; border-radius: 5px; padding: 4px 7px;
                                font-family: monospace; font-size: 11px; outline: none; pointer-events: auto !important;
                            ">
                        </div>

                        <div>
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1px;">
                                <span style="color: #94a3b8; font-size: 11px;">🚀 Groq Keys <span id="aq-groq-count" style="color:#4ade80;"></span> (tắt VPN khi dùng):</span>
                                <a href="https://console.groq.com/keys" target="_blank" style="color: #4ade80; font-size: 11px; text-decoration: none;">Lấy Key Groq ↗</a>
                            </div>
                            <input id="aq-groqkey" type="password" placeholder="gsk_..., gsk-..." style="
                                width: 100%; box-sizing: border-box; background: #0f172a; color: #f8fafc;
                                border: 1px solid #475569; border-radius: 5px; padding: 4px 7px;
                                font-family: monospace; font-size: 11px; outline: none; pointer-events: auto !important;
                            ">
                        </div>
                    </div>

                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 3px;">
                        <span style="color: #cbd5e1; font-size: 11px;">JSON đề thi (tự động bắt):</span>
                        <div style="display: flex; gap: 4px;">
                            <button id="aq-paste" type="button" style="background: #3b82f6; color: #fff; border: none; padding: 2px 7px; border-radius: 4px; font-size: 11px; cursor: pointer;">📋 Dán</button>
                            <button id="aq-clear" type="button" style="background: #475569; color: #fff; border: none; padding: 2px 7px; border-radius: 4px; font-size: 11px; cursor: pointer;">Xóa</button>
                        </div>
                    </div>
                    <textarea id="aq-input" rows="2" placeholder="Tự động điền khi mở bài..." style="
                        width: 100%; box-sizing: border-box; background: #0f172a; color: #f8fafc;
                        border: 1px solid #475569; border-radius: 6px; padding: 5px;
                        font-family: monospace; font-size: 11px; resize: vertical; outline: none;
                        user-select: text !important; -webkit-user-select: text !important; pointer-events: auto !important;
                    "></textarea>

                    <div style="display: flex; align-items: center; justify-content: space-between; margin-top: 7px; gap: 4px;">
                        <div style="display: flex; align-items: center; gap: 7px; flex-wrap: wrap;">
                            <label title="Bật khi đề có bài toán/code phức tạp" style="font-size: 11px; color: #cbd5e1; display: flex; align-items: center; gap: 3px; cursor: pointer; user-select: none;">
                                <input id="aq-deepthink" type="checkbox" style="cursor: pointer; accent-color: #f59e0b;">
                                Toán/Code
                            </label>
                            <label style="font-size: 11px; color: #cbd5e1; display: flex; align-items: center; gap: 3px; cursor: pointer; user-select: none;">
                                <input id="aq-autosubmit" type="checkbox" style="cursor: pointer; accent-color: #10b981;">
                                Tự nộp
                            </label>
                            <label style="font-size: 11px; color: #94a3b8; display: flex; align-items: center; gap: 2px;">
                                <input id="aq-delay" type="number" value="60" min="20" step="20" style="width: 40px; background: #0f172a; color: #fff; border: 1px solid #475569; border-radius: 4px; padding: 2px 3px; pointer-events: auto !important;">ms
                            </label>
                        </div>
                        <div style="display: flex; gap: 5px;">
                            <button id="aq-start" type="button" style="background: #10b981; color: #fff; border: none; padding: 6px 11px; border-radius: 6px; font-weight: 600; cursor: pointer; white-space: nowrap;">⚡ Giải & Điền</button>
                            <button id="aq-stop" type="button" style="background: #ef4444; color: #fff; border: none; padding: 6px 11px; border-radius: 6px; font-weight: 600; cursor: pointer; display: none;">⏹ Dừng</button>
                        </div>
                    </div>
                </div>

                <div id="aq-status" style="margin-top: 6px; padding: 5px 8px; background: #0f172a; border-radius: 6px; font-size: 12px; color: #fbbf24; min-height: 18px; line-height: 1.35;">
                    Vui lòng nhập Key kích hoạt để mở khóa công cụ.
                </div>
            </div>
        `;

        container.appendChild(panel);
        panel.addEventListener('focusin', (e) => e.stopPropagation());
        panel.addEventListener('keydown', (e) => e.stopPropagation());

        const actBtn = document.getElementById('aq-act-btn');
        const actInput = document.getElementById('aq-act-key');
        actBtn.addEventListener('click', async () => {
            const code = actInput.value.trim();
            if (!code) {
                setStatus('⚠️ Bạn chưa nhập Key kích hoạt!', '#f87171');
                return;
            }
            actBtn.disabled = true;
            actBtn.textContent = 'Đang kiểm tra...';
            setStatus('⏳ Đang xác thực Key kích hoạt...', '#38bdf8');
            try {
                await verifyActivationKeyOnline(code);
                localStorage.setItem('aq_license_unlocked', 'true');
                localStorage.setItem('aq_license_code', code);
                localStorage.setItem('aq_license_sig', getDeviceSignature());
                updateLockUIState();
                setStatus('✅ Kích hoạt thành công! Đã mở khóa cho tài khoản/máy này.', '#4ade80');
            } catch (errMsg) {
                setStatus(`❌ ${errMsg}`, '#f87171');
            } finally {
                actBtn.disabled = false;
                actBtn.textContent = 'Kích hoạt';
            }
        });

        const toggleBtn = document.getElementById('aq-toggle');
        const bodyDiv = document.getElementById('aq-body');
        toggleBtn.addEventListener('click', () => {
            const isHidden = bodyDiv.style.display === 'none';
            bodyDiv.style.display = isHidden ? 'block' : 'none';
            toggleBtn.textContent = isHidden ? 'Thu gọn' : 'Mở rộng';
        });

        const toggleKeysBtn = document.getElementById('aq-toggle-keys');
        const keysBox = document.getElementById('aq-keys-box');
        toggleKeysBtn.addEventListener('click', () => {
            keysBox.style.display = keysBox.style.display === 'none' ? 'flex' : 'none';
        });

        const cerKeyEl = document.getElementById('aq-cerebraskey');
        const gemKeyEl = document.getElementById('aq-geminikey');
        const orKeyEl = document.getElementById('aq-openrouterkey');
        const groqKeyEl = document.getElementById('aq-groqkey');

        cerKeyEl.value = localStorage.getItem('aq_cerebras_api_key') || '';
        gemKeyEl.value = localStorage.getItem('aq_gemini_api_key') || '';
        orKeyEl.value = localStorage.getItem('aq_openrouter_api_key') || '';
        groqKeyEl.value = localStorage.getItem('aq_groq_api_key') || '';

        const updateAllBadges = () => {
            const setBadge = (id, count) => {
                const el = document.getElementById(id);
                if (el) el.textContent = count > 0 ? `[${count} key]` : '';
            };
            setBadge('aq-cer-count', splitKeys(cerKeyEl.value).length);
            setBadge('aq-gem-count', splitKeys(gemKeyEl.value).length);
            setBadge('aq-or-count', splitKeys(orKeyEl.value).length);
            setBadge('aq-groq-count', splitKeys(groqKeyEl.value).length);
        };
        updateAllBadges();

        const bindKeyInput = (el, storageKey) => {
            el.addEventListener('input', () => {
                localStorage.setItem(storageKey, el.value.trim());
                updateAllBadges();
            });
        };
        bindKeyInput(cerKeyEl, 'aq_cerebras_api_key');
        bindKeyInput(gemKeyEl, 'aq_gemini_api_key');
        bindKeyInput(orKeyEl, 'aq_openrouter_api_key');
        bindKeyInput(groqKeyEl, 'aq_groq_api_key');

        const deepThinkEl = document.getElementById('aq-deepthink');
        deepThinkEl.checked = localStorage.getItem('aq_deep_think') === 'true';
        deepThinkEl.addEventListener('change', () => {
            localStorage.setItem('aq_deep_think', String(deepThinkEl.checked));
        });

        const autoSubmitEl = document.getElementById('aq-autosubmit');
        const savedAutoSubmit = localStorage.getItem('aq_auto_submit');
        autoSubmitEl.checked = savedAutoSubmit === null ? true : savedAutoSubmit === 'true';
        autoSubmitEl.addEventListener('change', () => {
            localStorage.setItem('aq_auto_submit', String(autoSubmitEl.checked));
        });

        const inputEl = document.getElementById('aq-input');
        if (capturedExamJson) {
            inputEl.value = JSON.stringify(capturedExamJson);
        }
        inputEl.addEventListener('input', () => validateJsonPreview(inputEl.value));

        document.getElementById('aq-paste').addEventListener('click', async () => {
            try {
                const text = await navigator.clipboard.readText();
                if (text) {
                    inputEl.value = text;
                    validateJsonPreview(text);
                }
            } catch (err) {
                const fallback = prompt('Dán chuỗi JSON vào đây:');
                if (fallback !== null) {
                    inputEl.value = fallback;
                    validateJsonPreview(fallback);
                }
            }
        });

        document.getElementById('aq-clear').addEventListener('click', () => {
            inputEl.value = '';
            capturedExamJson = null;
            setStatus('Đã xóa JSON.', '#fbbf24');
        });

        document.getElementById('aq-start').addEventListener('click', startSolveAndFill);
        document.getElementById('aq-stop').addEventListener('click', () => stopAuto('Đã dừng thủ công.'));

        updateLockUIState();
        if (isActivatedLocally()) {
            setStatus('Sẵn sàng (Cerebras + Gemini + OpenRouter + Groq).', '#fbbf24');
        }
    }

    function splitKeys(rawStr) {
        if (!rawStr) return [];
        return Array.from(new Set(
            rawStr.split(/[\s,;|\n\r]+/)
                .map(k => k.trim())
                .filter(k => k.length > 10)
        ));
    }

    function setStatus(msg, color = '#fbbf24') {
        const statusEl = document.getElementById('aq-status');
        if (statusEl) {
            statusEl.textContent = msg;
            statusEl.style.color = color;
        }
    }

    function countQuestionsInJson(obj) {
        const examData = obj?.data?.exam_data || obj?.exam_data || obj;
        if (!examData) return 0;
        return (examData.multiple_choice?.length || 0) +
               (examData.true_false?.length || 0) +
               (examData.fill_in_blank?.length || 0) +
               (examData.essay?.length || 0);
    }

    function validateJsonPreview(rawText) {
        if (!rawText.trim()) return;
        try {
            const parsed = JSON.parse(rawText);
            const count = countQuestionsInJson(parsed);
            if (count > 0) {
                setStatus(`✅ Hợp lệ (${count} câu). Bấm "⚡ Giải & Điền".`, '#38bdf8');
            } else {
                setStatus('⚠️ Không thấy exam_data trong JSON.', '#f87171');
            }
        } catch (e) {
            setStatus('⚠️ Sai định dạng JSON.', '#f87171');
        }
    }

    // =========================================================================
    // 5. NÉN ĐỀ THI & HỆ THỐNG XOAY VÒNG 4 NHÀ CUNG CẤP AI
    // =========================================================================
    function buildCompactPrompt(rawJsonObj) {
        const dataRoot = rawJsonObj?.data || rawJsonObj;
        const examData = dataRoot?.exam_data || dataRoot;
        const lines = [];

        if (dataRoot.reading_passage) {
            lines.push(`ĐOẠN VĂN:\n${dataRoot.reading_passage}\n`);
        }

        (examData.multiple_choice || []).forEach(q => {
            const opts = Object.entries(q.options || {}).map(([k, v]) => `${k}.${v}`).join(' | ');
            lines.push(`[TN] ${q.id}: ${q.question} => ${opts}`);
        });

        (examData.true_false || []).forEach(q => {
            const stmts = (q.statements || []).map((s, i) => `(${i + 1}) ${s.text}`).join(' ; ');
            lines.push(`[DS] ${q.id}: ${q.question} => ${stmts}`);
        });

        (examData.fill_in_blank || []).forEach(q => {
            lines.push(`[DT] ${q.id}: ${q.question}`);
        });

        (examData.essay || []).forEach(q => {
            lines.push(`[TL] ${q.id}: ${q.question}`);
        });

        return `Giải nhanh đề thi dưới đây. Xuất kết quả theo đúng định dạng từng dòng "ID|ĐÁP_ÁN" (không markdown, không giải thích thêm):
- Với [TN]: ID|A (hoặc B, C, D)
- Với [DS]: ID|ĐSĐS (4 chữ cái Đ hoặc S ứng với 4 ý)
- Với [DT]: ID|từ cần điền ngắn gọn
- Với [TL]: ID|nội dung tự luận súc tích (nếu nhiều dòng dùng \\n)

${lines.join('\n')}`;
    }

    function parseCompactReply(text) {
        const map = {};
        const clean = text.replace(/<think>[\s\S]*?<\/think>/gi, '')
                          .replace(/```[a-z]*\n?/gi, '')
                          .replace(/```/g, '')
                          .trim();
        const rows = clean.split(/\r?\n/);

        for (const row of rows) {
            const sepIdx = row.indexOf('|');
            if (sepIdx === -1) continue;

            const idStr = row.slice(0, sepIdx).replace(/\D/g, '');
            const valRaw = row.slice(sepIdx + 1).trim();
            if (!idStr || !valRaw) continue;

            const qId = parseInt(idStr, 10);

            if (/^[ĐSTFđstf]{4}$/.test(valRaw)) {
                map[qId] = valRaw.toUpperCase().split('').map(c => (c === 'Đ' || c === 'T'));
            } else if (/^[A-Da-d]$/.test(valRaw)) {
                map[qId] = valRaw.toUpperCase();
            } else {
                map[qId] = valRaw.replace(/\\n/g, '\n');
            }
        }
        return map;
    }

    function callOpenAICompatible(endpointUrl, apiKey, modelName, prompt, extraHeaders = {}) {
        return new Promise((resolve, reject) => {
            GM_xmlhttpRequest({
                method: 'POST',
                url: endpointUrl,
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'Authorization': `Bearer ${apiKey}`,
                    ...extraHeaders
                },
                timeout: 16000,
                data: JSON.stringify({
                    model: modelName,
                    temperature: 0.1,
                    messages: [{ role: 'user', content: prompt }]
                }),
                onload: function (res) {
                    if (res.status < 200 || res.status >= 300) {
                        reject({ status: res.status, message: `HTTP ${res.status} (${modelName})` });
                        return;
                    }
                    try {
                        const data = JSON.parse(res.responseText);
                        const reply = data?.choices?.[0]?.message?.content;
                        if (!reply) {
                            reject({ status: 0, message: 'Phản hồi trống.' });
                            return;
                        }
                        resolve(reply);
                    } catch (e) {
                        reject({ status: 0, message: 'Lỗi đọc dữ liệu JSON.' });
                    }
                },
                ontimeout: () => reject({ status: 408, message: `Timeout (${modelName})` }),
                onerror: () => reject({ status: 0, message: `Lỗi mạng (${modelName})` })
            });
        });
    }

    function callSingleGemini(apiKey, modelName, prompt, isDeepThink) {
        return new Promise((resolve, reject) => {
            const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${encodeURIComponent(apiKey)}`;

            const genConfig = { temperature: 0.1 };
            if (/2\.5|3/.test(modelName) && !/pro/i.test(modelName)) {
                genConfig.thinkingConfig = { thinkingBudget: isDeepThink ? 1024 : 0 };
            }

            GM_xmlhttpRequest({
                method: 'POST',
                url: url,
                headers: { 'Content-Type': 'application/json' },
                timeout: 18000,
                data: JSON.stringify({
                    contents: [{ parts: [{ text: prompt }] }],
                    generationConfig: genConfig
                }),
                onload: function (res) {
                    if (res.status < 200 || res.status >= 300) {
                        reject({ status: res.status, message: `Gemini HTTP ${res.status} (${modelName})` });
                        return;
                    }
                    try {
                        const data = JSON.parse(res.responseText);
                        const reply = data?.candidates?.[0]?.content?.parts?.[0]?.text;
                        if (!reply) {
                            reject({ status: 0, message: 'Gemini phản hồi trống.' });
                            return;
                        }
                        resolve(reply);
                    } catch (e) {
                        reject({ status: 0, message: 'Lỗi đọc dữ liệu Gemini.' });
                    }
                },
                ontimeout: () => reject({ status: 408, message: 'Gemini Timeout' }),
                onerror: () => reject({ status: 0, message: 'Lỗi mạng Gemini' })
            });
        });
    }

    async function solveWithAllProviders({ cerKeys, gemKeys, orKeys, groqKeys }, prompt, isDeepThink) {
        let lastErr = null;
        let hitQuota = false;

        for (let i = 0; i < cerKeys.length; i++) {
            const tag = cerKeys.length > 1 ? ` #${i + 1}` : '';
            for (const model of CEREBRAS_MODELS) {
                if (!isRunning) throw new Error('Đã dừng.');
                setStatus(`⚡ Đang giải bằng Cerebras${tag} (${model})...`, '#f59e0b');
                try {
                    const raw = await callOpenAICompatible('https://api.cerebras.ai/v1/chat/completions', cerKeys[i], model, prompt);
                    const map = parseCompactReply(raw);
                    if (Object.keys(map).length > 0) return { map, source: `Cerebras${tag}` };
                } catch (err) {
                    lastErr = err;
                    if (err.status === 429 || err.status === 401 || err.status === 403) {
                        if (err.status === 429) hitQuota = true;
                        break;
                    }
                    await smartSleep(200);
                }
            }
        }

        for (let i = 0; i < gemKeys.length; i++) {
            const tag = gemKeys.length > 1 ? ` #${i + 1}` : '';
            for (const model of GEMINI_MODELS) {
                if (!isRunning) throw new Error('Đã dừng.');
                setStatus(`🔑 Đang giải bằng Gemini${tag} (${model})...`, '#38bdf8');
                try {
                    const raw = await callSingleGemini(gemKeys[i], model, prompt, isDeepThink);
                    const map = parseCompactReply(raw);
                    if (Object.keys(map).length > 0) return { map, source: `Gemini${tag}` };
                } catch (err) {
                    lastErr = err;
                    if (err.status === 429 || err.status === 401 || err.status === 403) {
                        if (err.status === 429) hitQuota = true;
                        break;
                    }
                    await smartSleep(200);
                }
            }
        }

        for (let i = 0; i < orKeys.length; i++) {
            const tag = orKeys.length > 1 ? ` #${i + 1}` : '';
            for (const model of OPENROUTER_MODELS) {
                if (!isRunning) throw new Error('Đã dừng.');
                setStatus(`🌐 Đang giải bằng OpenRouter${tag} (${model.split('/').pop()})...`, '#c084fc');
                try {
                    const raw = await callOpenAICompatible(
                        'https://openrouter.ai/api/v1/chat/completions',
                        orKeys[i],
                        model,
                        prompt,
                        { 'HTTP-Referer': location.origin, 'X-Title': 'AutoQuizHelper' }
                    );
                    const map = parseCompactReply(raw);
                    if (Object.keys(map).length > 0) return { map, source: `OpenRouter${tag}` };
                } catch (err) {
                    lastErr = err;
                    if (err.status === 429 || err.status === 401 || err.status === 403) {
                        if (err.status === 429) hitQuota = true;
                        break;
                    }
                    await smartSleep(200);
                }
            }
        }

        for (let i = 0; i < groqKeys.length; i++) {
            const tag = groqKeys.length > 1 ? ` #${i + 1}` : '';
            for (const model of GROQ_MODELS) {
                if (!isRunning) throw new Error('Đã dừng.');
                setStatus(`🚀 Đang giải bằng Groq${tag} (${model.split('/').pop()})...`, '#4ade80');
                try {
                    const raw = await callOpenAICompatible('https://api.groq.com/openai/v1/chat/completions', groqKeys[i], model, prompt);
                    const map = parseCompactReply(raw);
                    if (Object.keys(map).length > 0) return { map, source: `Groq${tag}` };
                } catch (err) {
                    lastErr = err;
                    if (err.status === 429 || err.status === 401 || err.status === 403) {
                        if (err.status === 429) hitQuota = true;
                        break;
                    }
                    await smartSleep(200);
                }
            }
        }

        if (hitQuota) {
            throw new Error('⏳ Tất cả Key AI đều đã hết lượt (429)! Hãy dán thêm Key mới hoặc đợi 1 phút.');
        }
        throw new Error(lastErr?.message || 'Không thể kết nối AI, kiểm tra lại Key hoặc mạng.');
    }

    // =========================================================================
    // 6. LUỒNG CHÍNH: GIẢI ĐA NGUỒN -> ĐIỀN XÁC NHẬN TỪNG NÚT -> NỘP BÀI
    // =========================================================================
    function stopAuto(reason, color = '#f87171') {
        isRunning = false;
        const startBtn = document.getElementById('aq-start');
        const stopBtn = document.getElementById('aq-stop');
        if (startBtn) startBtn.style.display = 'inline-block';
        if (stopBtn) stopBtn.style.display = 'none';
        setStatus(reason, color);
    }

    async function startSolveAndFill() {
        if (!isActivatedLocally()) {
            setStatus('🔒 Bạn phải nhập Key kích hoạt ở ô trên cùng trước!', '#f87171');
            return;
        }

        const dialog = document.querySelector('[role="dialog"]');
        if (!dialog) {
            setStatus('⚠️ Không thấy khung bài tập.', '#f87171');
            return;
        }

        const cerKeys = splitKeys(document.getElementById('aq-cerebraskey').value);
        const gemKeys = splitKeys(document.getElementById('aq-geminikey').value);
        const orKeys = splitKeys(document.getElementById('aq-openrouterkey').value);
        const groqKeys = splitKeys(document.getElementById('aq-groqkey').value);

        if (cerKeys.length + gemKeys.length + orKeys.length + groqKeys.length === 0) {
            setStatus('⚠️ Bạn chưa nhập Key AI nào! Hãy dán ít nhất 1 Key (Cerebras, Gemini, OpenRouter hoặc Groq).', '#f87171');
            return;
        }

        const rawJsonText = document.getElementById('aq-input').value.trim();
        if (!rawJsonText) {
            setStatus('⚠️ Chưa có dữ liệu đề thi!', '#f87171');
            return;
        }

        let parsedJson;
        try {
            parsedJson = JSON.parse(rawJsonText);
        } catch (e) {
            setStatus('⚠️ JSON không hợp lệ!', '#f87171');
            return;
        }

        const totalQuestions = countQuestionsInJson(parsedJson);
        if (totalQuestions === 0) {
            setStatus('⚠️ Đề thi không có câu hỏi!', '#f87171');
            return;
        }

        isRunning = true;
        document.getElementById('aq-start').style.display = 'none';
        document.getElementById('aq-stop').style.display = 'inline-block';

        const isDeepThink = document.getElementById('aq-deepthink')?.checked || false;
        const compactPrompt = buildCompactPrompt(parsedJson);
        const startTime = Date.now();

        let solveResult;
        try {
            solveResult = await solveWithAllProviders({ cerKeys, gemKeys, orKeys, groqKeys }, compactPrompt, isDeepThink);
        } catch (err) {
            stopAuto(`❌ ${err.message}`, '#f87171');
            return;
        }

        if (!isRunning) return;

        const answersMap = solveResult.map;
        const elapsedSec = ((Date.now() - startTime) / 1000).toFixed(1);
        setStatus(`✨ ${solveResult.source} giải xong ${Object.keys(answersMap).length} câu (${elapsedSec}s)! Đang điền...`, '#4ade80');

        const delay = Math.max(20, parseInt(document.getElementById('aq-delay').value, 10) || 60);

        while (isRunning) {
            const currentDialog = document.querySelector('[role="dialog"]');
            if (!currentDialog) {
                stopAuto('⚠️ Mất khung bài tập.');
                break;
            }

            const spans = Array.from(currentDialog.querySelectorAll('span'));
            const qLabelSpan = spans.find((s) => /^Câu\s+\d+$/i.test(s.textContent.trim()));
            if (!qLabelSpan) {
                stopAuto('⚠️ Không đọc được số câu.');
                break;
            }
            const currentQNum = parseInt(qLabelSpan.textContent.replace(/\D/g, ''), 10);

            const headerText = qLabelSpan.parentElement ? qLabelSpan.parentElement.textContent : '';
            const isMultipleChoice = headerText.includes('Trắc nghiệm');
            const isTrueFalse = headerText.includes('Đúng sai');
            const isFillInBlank = headerText.includes('Điền chỗ trống');
            const isEssay = headerText.includes('Tự luận');

            const targetAns = answersMap[currentQNum];
            if (targetAns === undefined || targetAns === null) {
                stopAuto(`🛑 Dừng ở Câu ${currentQNum}: Thiếu đáp án.`, '#fbbf24');
                break;
            }

            if (isMultipleChoice) {
                const optionSpans = spans.filter((s) => /^[A-D]\.$/.test(s.textContent.trim()));
                const targetLetter = String(targetAns).trim().toUpperCase();
                const matched = optionSpans.find((s) => s.textContent.trim().replace('.', '').toUpperCase() === targetLetter);

                if (!matched) {
                    stopAuto(`🛑 Câu ${currentQNum}: Không thấy đáp án "${targetAns}".`);
                    break;
                }
                matched.parentElement.click();
            } else if (isTrueFalse) {
                if (!Array.isArray(targetAns)) {
                    stopAuto(`🛑 Câu ${currentQNum}: Sai định dạng Đúng/Sai.`);
                    break;
                }
                const allButtons = Array.from(currentDialog.querySelectorAll('button')).filter((b) => !b.closest('#auto-quiz-panel'));
                const dungBtns = allButtons.filter((b) => b.textContent.trim() === 'Đúng');
                const saiBtns = allButtons.filter((b) => b.textContent.trim() === 'Sai');

                const count = Math.min(targetAns.length, dungBtns.length);
                for (let idx = 0; idx < count; idx++) {
                    const btn = targetAns[idx] ? dungBtns[idx] : saiBtns[idx];
                    await clickAndConfirmTfButton(btn);
                }
            } else if (isFillInBlank) {
                const targetInput = Array.from(currentDialog.querySelectorAll('input[type="text"], input:not([type])'))
                    .find((inp) => !inp.closest('#auto-quiz-panel'));
                if (!targetInput) {
                    stopAuto(`🛑 Câu ${currentQNum}: Không thấy ô điền từ.`);
                    break;
                }
                targetInput.focus();
                setReactFieldValue(targetInput, String(targetAns));
            } else if (isEssay) {
                const targetTextarea = Array.from(currentDialog.querySelectorAll('textarea'))
                    .find((ta) => !ta.closest('#auto-quiz-panel'));
                if (!targetTextarea) {
                    stopAuto(`🛑 Câu ${currentQNum}: Không thấy ô tự luận.`);
                    break;
                }
                targetTextarea.focus();
                setReactFieldValue(targetTextarea, String(targetAns));
            }

            await waitForQuestionSaved(currentDialog, currentQNum, 400);
            await smartSleep(delay);
            if (!isRunning) break;

            const nextBtn = Array.from(currentDialog.querySelectorAll('button')).find((b) => b.textContent.includes('Câu tiếp'));
            if (!nextBtn || nextBtn.disabled) {
                const shouldAutoSubmit = document.getElementById('aq-autosubmit')?.checked;
                if (shouldAutoSubmit && await autoSubmitExam()) {
                    stopAuto(`🎉 Hoàn tất & Đã nộp bài! (${solveResult.source}: ${elapsedSec}s)`, '#4ade80');
                } else {
                    stopAuto(`🎉 Hoàn tất đến Câu ${currentQNum}! (${solveResult.source}: ${elapsedSec}s)`, '#4ade80');
                }
                break;
            }

            nextBtn.click();
            await smartSleep(delay);
        }
    }

    setInterval(createUI, 1000);
})();
