#!/usr/bin/env node
/* =========================================================
   Рендеры страницы для ревью и аудит вёрстки.

   Запуск (сервер должен быть уже поднят):
     python3 -m http.server 8080
     node tools/render-site.mjs            # перерисовать preview/
     node tools/render-site.mjs --audit    # проверить вёрстку, файлы не пишутся

   Зачем отдельный инструмент: preview/ не хранится в репозитории
   (см. .gitignore), значит его должно быть чем воспроизвести.
   Аудит — та же проверка, которой проверялись правки: переполнение
   по горизонтали, битые картинки и расхождение размеров.

   Зависимостей нет: только встроенные модули Node 22+ и локальный
   Chrome или Chromium.
   ========================================================= */

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = 9333;

const args = process.argv.slice(2);
const AUDIT_ONLY = args.includes('--audit');
const BASE = (args.find((a) => a.startsWith('--url=')) || '').replace('--url=', '') || 'http://127.0.0.1:8080';

if (Number(process.versions.node.split('.')[0]) < 22) {
  console.error(`Нужен Node 22+ (встроенный WebSocket). Сейчас ${process.versions.node}.`);
  process.exit(1);
}

/* ---------- Chrome ---------- */

function findChrome() {
  const candidates = [
    process.env.CHROME,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
  ].filter(Boolean);

  const found = candidates.find((p) => existsSync(p));
  if (!found) {
    console.error('Не нашёл Chrome. Укажи путь: CHROME=/путь/к/chrome node tools/render-site.mjs');
    process.exit(1);
  }
  return found;
}

const flags = [
  '--headless=new',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--no-first-run',
  '--disable-breakpad',
  `--remote-debugging-port=${PORT}`,
  // Профиль одноразовый и весит ~50 МБ, поэтому в системный temp,
  // а не в проект.
  '--user-data-dir=' + join(tmpdir(), 'render-site-chrome-profile'),
  'about:blank',
];

// В обычной системе не нужно; пригодится в контейнере или песочнице,
// где вложенный sandbox Chrome не поднимается.
if (process.env.CHROME_NO_SANDBOX) flags.unshift('--no-sandbox', '--disable-setuid-sandbox');

const chrome = spawn(findChrome(), flags, { stdio: 'ignore' });

/* ---------- Минимальный клиент CDP ---------- */

class CDP {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.waiters = [];
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.onopen = resolve;
      ws.onerror = () => reject(new Error('не удалось подключиться к Chrome'));
    });

    const cdp = new CDP(ws);
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id && cdp.pending.has(message.id)) {
        const { resolve, reject } = cdp.pending.get(message.id);
        cdp.pending.delete(message.id);
        message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
      } else if (message.method) {
        for (const waiter of cdp.waiters.slice()) {
          if (waiter.method === message.method) {
            cdp.waiters.splice(cdp.waiters.indexOf(waiter), 1);
            waiter.resolve(message.params);
          }
        }
      }
    };
    return cdp;
  }

  send(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  waitFor(method, timeout = 30000) {
    return new Promise((resolve, reject) => {
      const waiter = { method, resolve };
      this.waiters.push(waiter);
      setTimeout(() => {
        const at = this.waiters.indexOf(waiter);
        if (at >= 0) {
          this.waiters.splice(at, 1);
          reject(new Error(`не дождался ${method}`));
        }
      }, timeout);
    });
  }

  async evaluate(expression) {
    const result = await this.send('Runtime.evaluate', { expression, returnByValue: true });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  }
}

async function debuggerUrl() {
  for (let i = 0; i < 120; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {
      /* Chrome ещё поднимается */
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('Chrome не запустился');
}

/* ---------- Что смотрим ---------- */

const WIDTHS = [390, 430, 620, 768, 860, 1280];
const SCHEMES = ['light', 'dark'];
const PAGES = [
  { lang: 'ru', path: '/' },
  { lang: 'en', path: '/en/' },
];

const PREVIEWS = [
  { out: 'preview/desktop-light.png', lang: 'ru', width: 1280, scheme: 'light' },
  { out: 'preview/desktop-dark.png', lang: 'ru', width: 1280, scheme: 'dark' },
  { out: 'preview/en-desktop.png', lang: 'en', width: 1280, scheme: 'dark' },
  { out: 'preview/mobile-light.png', lang: 'ru', width: 390, scheme: 'light' },
];

const PROBE = `(() => {
  const root = document.documentElement;
  const images = [...document.images].map((i) => ({
    file: i.currentSrc.split('/').pop(),
    natural: [i.naturalWidth, i.naturalHeight],
    declared: [i.getAttribute('width'), i.getAttribute('height')],
    done: i.complete,
  }));
  return JSON.stringify({
    scrollWidth: root.scrollWidth,
    clientWidth: root.clientWidth,
    scrollHeight: root.scrollHeight,
    fontsStatus: document.fonts.status,
    fonts: [...document.fonts].map((f) => ({ family: f.family, weight: f.weight, status: f.status })),
    images,
  });
})()`;

/* ---------- Прогон ---------- */

const cdp = await CDP.connect(await debuggerUrl());
await cdp.send('Page.enable');
await cdp.send('Runtime.enable');

async function load({ path, width, scheme }) {
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width, height: 900, deviceScaleFactor: 1, mobile: false,
  });
  await cdp.send('Emulation.setEmulatedMedia', {
    features: [{ name: 'prefers-color-scheme', value: scheme }],
  });

  const loaded = cdp.waitFor('Page.loadEventFired');
  await cdp.send('Page.navigate', { url: BASE + path });
  await loaded;

  // Растягиваем вьюпорт на всю страницу: так ленивые картинки попадают
  // в зону видимости и успевают загрузиться до снимка.
  const height = await cdp.evaluate('document.documentElement.scrollHeight');
  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width, height, deviceScaleFactor: 1, mobile: false,
  });

  for (let i = 0; i < 40; i++) {
    if (await cdp.evaluate('[...document.images].every((i) => i.complete)')) break;
    await new Promise((r) => setTimeout(r, 250));
  }
  // Шрифты грузятся отдельно от картинок; ждём, иначе снимок
  // покажет системный шрифт и это будет выглядеть как регресс.
  for (let i = 0; i < 40; i++) {
    if (await cdp.evaluate("document.fonts.status === 'loaded'")) break;
    await new Promise((r) => setTimeout(r, 250));
  }

  // Даём доиграть переходам появления секций.
  await new Promise((r) => setTimeout(r, 1500));

  return JSON.parse(await cdp.evaluate(PROBE));
}

function complain(report) {
  const problems = new Set();

  if (report.scrollWidth > report.clientWidth) {
    problems.add(`переполнение по горизонтали +${report.scrollWidth - report.clientWidth}px`);
  }

  // Шрифт с неверным путём в @font-face не ломает вёрстку — текст просто
  // подменяется системным. Поэтому проверяем состояние явно.
  for (const font of report.fonts) {
    if (font.status === 'error') problems.add(`шрифт ${font.family} ${font.weight} не загрузился`);
  }
  if (report.fontsStatus !== 'loaded') {
    problems.add(`document.fonts.status = ${report.fontsStatus}`);
  }

  for (const image of report.images) {
    if (!image.done || image.natural[0] === 0) {
      problems.add(`битая картинка ${image.file}`);
      continue;
    }

    // width/height в разметке — это размеры бокса, они не обязаны совпадать
    // с размерами файла (логотип 96×96 показывается в 32×32). Важно, чтобы
    // совпадали пропорции: иначе <img> резервирует не тот бокс, и после
    // пересъёмки в другом разрешении страница поедет.
    const [dw, dh] = image.declared.map(Number);
    if (dw && dh) {
      const declared = dw / dh;
      const natural = image.natural[0] / image.natural[1];
      if (Math.abs(declared - natural) / natural > 0.01) {
        problems.add(
          `${image.file}: пропорции в разметке ${dw}×${dh}, у файла ${image.natural[0]}×${image.natural[1]}`,
        );
      }
    }
  }

  return [...problems];
}

function describe(problems) {
  if (!problems.length) return 'ок';
  const shown = problems.slice(0, 2).join('; ');
  return `ПРОБЛЕМЫ: ${shown}${problems.length > 2 ? ` (+${problems.length - 2})` : ''}`;
}

try {
  if (AUDIT_ONLY) {
    let failures = 0;
    console.log(`Аудит ${BASE} — переполнение, битые картинки, размеры\n`);
    console.log('локаль  тема   ширина   страница      высота   картинок   шрифты   результат');
    for (const { lang, path } of PAGES) {
      for (const scheme of SCHEMES) {
        for (const width of WIDTHS) {
          const report = await load({ path, width, scheme });
          const problems = complain(report);
          if (problems.length) failures++;
          console.log(
            `  ${lang}   ${scheme.padEnd(5)} ${String(width).padStart(5)}   ` +
            `${String(report.scrollWidth).padStart(4)}/${String(report.clientWidth).padEnd(4)}   ` +
            `${String(report.scrollHeight).padStart(6)}   ${String(report.images.length).padStart(6)}   ` +
            `${report.fonts.filter((f) => f.status === 'loaded').length}/${report.fonts.length}    ` +
            describe(problems),
          );
        }
      }
    }
    console.log(failures ? `\nПровалов: ${failures}` : '\nВсё чисто.');
    process.exitCode = failures ? 1 : 0;
  } else {
    for (const preview of PREVIEWS) {
      const path = preview.lang === 'ru' ? '/' : '/en/';
      const report = await load({ path, width: preview.width, scheme: preview.scheme });
      const shot = await cdp.send('Page.captureScreenshot', { format: 'png' });
      mkdirSync(join(ROOT, 'preview'), { recursive: true });
      writeFileSync(join(ROOT, preview.out), Buffer.from(shot.data, 'base64'));

      const problems = complain(report);
      console.log(
        `${preview.out}  ${preview.width}px ${preview.scheme}  ` +
        `${report.scrollWidth}×${report.scrollHeight}  ` +
        describe(problems),
      );
    }
    console.log('\nГотово. Аудит целиком: node tools/render-site.mjs --audit');
  }
} finally {
  cdp.ws.close();
  chrome.kill('SIGKILL');
}
